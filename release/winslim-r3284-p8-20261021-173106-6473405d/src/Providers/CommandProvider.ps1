function Test-DismVerify {
    # So Reserved Storage tem um estado persistente para conferir - SFC e
    # limpeza de componentes (EXT-003/EXTRA-006) sao acoes pontuais sem
    # 'ligado/desligado' (ja documentado via rollbackNote nesses dois).
    param([string]$ScriptText)
    $checks = @()
    $m = [regex]::Match($ScriptText, '(?i)Set-ReservedStorageState\s+/State:(\w+)')
    if ($m.Success) {
        $expected = $m.Groups[1].Value
        $result = Invoke-NativeCommand -FilePath 'DISM' -Arguments @('/Online', '/Get-ReservedStorageState')
        $pass = $result.Output -and ($result.Output -match [regex]::Escape($expected))
        $checks += [PSCustomObject]@{ Type = 'DISM'; Target = 'Reserved Storage State'; Expected = $expected; Actual = $(if ($result.Output) { 'ver DISM /Get-ReservedStorageState no log' } else { '<indeterminado>' }); Pass = [bool]$pass }
    }
    return @($checks)
}

function Test-FeatureVerify {
    # Get-WindowsOptionalFeature devolve objeto estruturado (.State) - sem
    # risco de parsing de texto localizado.
    param([string]$ScriptText)
    $checks = @()
    $disableMatch = [regex]::Match($ScriptText, '(?i)Disable-WindowsOptionalFeature\s+-Online\s+-FeatureName\s+(\S+)')
    $enableMatch = [regex]::Match($ScriptText, '(?i)Enable-WindowsOptionalFeature\s+-Online\s+-FeatureName\s+(\S+)')
    $m = if ($disableMatch.Success) { $disableMatch } else { $enableMatch }
    if ($m.Success) {
        $featureName = $m.Groups[1].Value
        $expected = if ($disableMatch.Success) { 'Disabled' } else { 'Enabled' }
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue
        $actual = if ($feat) { $feat.State.ToString() } else { $null }
        $checks += [PSCustomObject]@{ Type = 'Feature'; Target = $featureName; Expected = $expected; Actual = $(if ($actual) { $actual } else { '<indeterminado>' }); Pass = ($actual -eq $expected) }
    }
    return @($checks)
}

# ============================================================================
# fsutil behavior - API completa (Fase 2 / 2.1, piloto ntfs-last-access-off)
#
# IMPORTANTE (achado real, nao hipotetico): em Windows 10 1803+ o valor
# default de 'disablelastaccess' costuma ja vir como 3 (System Managed,
# Disabled), nao 0. A saida tem 4 estados possiveis:
#   0 = User Managed, Enabled     2 = System Managed, Enabled
#   1 = User Managed, Disabled    3 = System Managed, Disabled
# "Desabilitado" = valor IMPAR (1 ou 3), nao "== 1" especificamente. Por
# isso comando executado (ExitCode 0) != estado verificado - e preciso
# reconsultar e interpretar o numero, nao so confirmar que o comando rodou.
# Comandos nativos passam por Invoke-NativeCommand (nao herdam o
# ErrorActionPreference 'Stop' do chamador).
# ============================================================================

function Get-FsutilBehaviorState {
    param([string]$Setting)
    $result = Invoke-NativeCommand -FilePath 'fsutil' -Arguments @('behavior', 'query', $Setting)
    if ($result.ExitCode -ne 0 -or -not $result.Output) {
        return [PSCustomObject]@{ Setting = $Setting; Value = $null; Raw = $result.Output; Queryable = $false }
    }
    $m = [regex]::Match($result.Output, '(?i)=\s*(\d+)')
    if ($m.Success) {
        return [PSCustomObject]@{ Setting = $Setting; Value = [int]$m.Groups[1].Value; Raw = $result.Output.Trim(); Queryable = $true }
    }
    return [PSCustomObject]@{ Setting = $Setting; Value = $null; Raw = $result.Output.Trim(); Queryable = $false }
}

function Set-FsutilBehaviorState {
    param([string]$Setting, [int]$Value)
    $r = Invoke-NativeCommand -FilePath 'fsutil' -Arguments @('behavior', 'set', $Setting, $Value)
    Assert-NativeCommandSuccess -Result $r -Operation "fsutil behavior set $Setting $Value" | Out-Null
}

function Test-FsutilDisabledOddEven {
    # Para settings do tipo disablelastaccess: desabilitado = valor impar.
    param([string]$Setting, [bool]$ExpectDisabled)
    $cur = Get-FsutilBehaviorState -Setting $Setting
    $isDisabled = $cur.Queryable -and (($cur.Value % 2) -eq 1)
    $pass = $cur.Queryable -and ($isDisabled -eq $ExpectDisabled)
    return [PSCustomObject]@{ Type = 'Command'; Target = "fsutil behavior $Setting"; Expected = $(if ($ExpectDisabled) { 'desabilitado (valor ímpar)' } else { 'habilitado (valor par)' }); Actual = $(if ($cur.Queryable) { $cur.Value } else { '<indeterminado>' }); Pass = $pass }
}

function Backup-FsutilBehaviorState {
    param([string]$Setting)
    return Get-FsutilBehaviorState -Setting $Setting
}

function Restore-FsutilBehaviorState {
    param($StateBefore)
    if ($StateBefore.Queryable -and $null -ne $StateBefore.Value) {
        Set-FsutilBehaviorState -Setting $StateBefore.Setting -Value $StateBefore.Value
    }
}

function Invoke-FsutilOddEvenProvider {
    <#
        Correção Fase 2.1: $before era calculado incondicionalmente ANTES de
        checar $Action - no Undo isso reconsultava o valor JÁ ALTERADO pelo
        Apply, e o fallback "senão usa $before" tornava o Undo um no-op
        disfarçado quando BackupData não era passado. Agora Undo exige
        BackupData (lançado erro se ausente) e usa isso como $referenceState
        em toda a função, inclusive no cálculo de $expectDisabled.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Setting,
        [int]$TargetValue = 1,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null
    )
    $errorMsg = $null
    $changed = $false
    $referenceState = $null

    try {
        if ($Action -eq 'Apply') {
            $referenceState = Backup-FsutilBehaviorState -Setting $Setting
            Set-FsutilBehaviorState -Setting $Setting -Value $TargetValue
            $changed = $true
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar '$Setting' com segurança sem o valor original salvo."
            }
            $referenceState = $BackupData
            Restore-FsutilBehaviorState -StateBefore $referenceState
            $changed = $true
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $after = Get-FsutilBehaviorState -Setting $Setting
    $expectDisabled = if ($errorMsg) { $null }
        elseif ($Action -eq 'Apply') { ($TargetValue % 2) -eq 1 }
        else { $referenceState.Queryable -and (($referenceState.Value % 2) -eq 1) }
    $verifyCheck = if ($null -eq $expectDisabled) {
        [PSCustomObject]@{ Type = 'Command'; Target = "fsutil behavior $Setting"; Expected = '<não verificável - erro na execução>'; Actual = '<não verificável>'; Pass = $false }
    } else {
        Test-FsutilDisabledOddEven -Setting $Setting -ExpectDisabled $expectDisabled
    }

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]($changed -and -not $errorMsg -and $verifyCheck.Pass)) -Changed $changed `
        -StateBefore $referenceState -StateAfter $after `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyCheck.Pass; Checks = @($verifyCheck) }) `
        -Restart 'Reboot' -ErrorMessage $errorMsg
}
