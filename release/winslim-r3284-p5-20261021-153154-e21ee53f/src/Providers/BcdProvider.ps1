function Test-BcdElementVerify {
    # Le os proprios comandos bcdedit do script (nao precisa de metadado extra
    # no catalogo) e determina o estado ESPERADO final de cada elemento,
    # respeitando a ordem dos comandos (um /set depois de um /deletevalue no
    # mesmo elemento vence, como na execucao real).
    # Importante: bcdedit /set usa true/false, mas /enum EXIBE Yes/No - mapeado abaixo.
    param([string]$ScriptText)
    $expectedState = [ordered]@{}
    $tokens = [regex]::Matches($ScriptText, 'bcdedit\s+/(set|deletevalue)\s+(\S+)(?:\s+(\S+))?', 'IgnoreCase')
    foreach ($m in $tokens) {
        $verb = $m.Groups[1].Value.ToLower()
        $elem = $m.Groups[2].Value
        if ($verb -eq 'deletevalue') { $expectedState[$elem] = $null; continue }
        $val = $m.Groups[3].Value
        $expectedState[$elem] = switch ($val.ToLower()) { 'true' { 'Yes' } 'false' { 'No' } default { $val } }
    }
    $enumResult = Invoke-NativeCommand -FilePath 'bcdedit' -Arguments @('/enum', '{current}')
    $enumOutput = $enumResult.Output
    $checks = @()
    foreach ($elem in $expectedState.Keys) {
        $exp = $expectedState[$elem]
        $line = if ($enumOutput) { (@($enumOutput -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($elem) } | Select-Object -First 1) } else { $null }
        $actual = if ($line) { ($line -replace "(?i)^.*$([regex]::Escape($elem))\s+", '').Trim() } else { $null }
        if ($null -eq $exp) {
            $checks += [PSCustomObject]@{ Type = 'BCD'; Target = $elem; Expected = '<ausente/padrão>'; Actual = $(if ($actual) { $actual } else { '<ausente>' }); Pass = ($null -eq $actual) }
        } else {
            $pass = (Normalize-BcdComparableValue -Value $actual) -eq (Normalize-BcdComparableValue -Value $exp)
            $checks += [PSCustomObject]@{ Type = 'BCD'; Target = $elem; Expected = $exp; Actual = $(if ($actual) { $actual } else { '<indeterminado>' }); Pass = [bool]$pass }
        }
    }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2 / 2.1) - rigor extra pedido: Undo precisa
# saber se o elemento EXISTIA originalmente ou nao. "bcdedit /set X no" como
# undo universal esta ERRADO se o elemento nunca existia antes. Por isso
# Backup-BcdElementState roda ANTES de qualquer Apply, e Restore usa Remove
# quando Exists=false. Comandos nativos passam por Invoke-NativeCommand
# (ErrorActionPreference local 'Continue' - nao herda 'Stop' do chamador).
# ============================================================================

function Get-BcdElementState {
    param([string]$Element, [string]$Store = '{current}')
    $result = Invoke-NativeCommand -FilePath 'bcdedit' -Arguments @('/enum', $Store)
    if (-not $result.Output -or $result.ExitCode -ne 0) {
        return [PSCustomObject]@{ Element = $Element; Exists = $false; Value = $null; Queryable = $false }
    }
    $line = (@($result.Output -split "`r?`n") | Where-Object { $_ -match [regex]::Escape($Element) } | Select-Object -First 1)
    if (-not $line) { return [PSCustomObject]@{ Element = $Element; Exists = $false; Value = $null; Queryable = $true } }
    $val = ($line -replace "(?i)^.*$([regex]::Escape($Element))\s+", '').Trim()
    return [PSCustomObject]@{ Element = $Element; Exists = $true; Value = $val; Queryable = $true }
}

function Backup-BcdElementState {
    <#
        Backup: alem de capturar o estado do elemento especifico (para Undo
        rapido), exporta a BCD store inteira para Backups/ como rede de
        seguranca adicional (bcdedit /export) - permite bcdedit /import na
        pior hipotese, mesmo que o Undo por elemento falhe por algum motivo.
    #>
    param([string]$Element, [string]$Store = '{current}')
    $state = Get-BcdElementState -Element $Element -Store $Store
    try {
        $backupDir = Join-Path $ScriptRoot 'Backups'
        if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
        $exportPath = Join-Path $backupDir "bcd-export-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff').bcd"
        $exportResult = Invoke-NativeCommand -FilePath 'bcdedit' -Arguments @('/export', $exportPath)
        if ($exportResult.ExitCode -eq 0 -and (Test-Path $exportPath)) {
            $state | Add-Member -NotePropertyName 'BcdExportPath' -NotePropertyValue $exportPath -Force
        } else {
            Write-Log "BcdProvider: bcdedit /export falhou (ExitCode=$($exportResult.ExitCode)). Backup por elemento mantido." 'WARN'
        }
    } catch {
        Write-Log "BcdProvider: falha ao exportar BCD store completo antes do Apply ($($_.Exception.Message)). Prosseguindo só com backup por elemento." 'WARN'
    }
    return $state
}

function ConvertTo-BcdInputValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    switch ($Value.ToString().Trim().ToLowerInvariant()) {
        'yes'   { return 'true' }
        'sim'   { return 'true' }
        'true'  { return 'true' }
        '1'     { return 'true' }
        'no'    { return 'false' }
        'nao'   { return 'false' }
        'não'   { return 'false' }
        'false' { return 'false' }
        '0'     { return 'false' }
        default { return $Value }
    }
}

function Normalize-BcdComparableValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    switch ($Value.ToString().Trim().ToLowerInvariant()) {
        'yes'   { return 'true' }
        'sim'   { return 'true' }
        'true'  { return 'true' }
        '1'     { return 'true' }
        'no'    { return 'false' }
        'nao'   { return 'false' }
        'não'   { return 'false' }
        'false' { return 'false' }
        '0'     { return 'false' }
        default { return $Value.ToString().Trim().ToLowerInvariant() }
    }
}

function Set-BcdElementValue {
    param([string]$Element, [string]$Value, [string]$Store = '{current}')
    $normalized = ConvertTo-BcdInputValue -Value $Value
    $r = Invoke-NativeCommand -FilePath 'bcdedit' -Arguments @('/set', $Store, $Element, $normalized)
    Assert-NativeCommandSuccess -Result $r -Operation "bcdedit /set $Store $Element $normalized" | Out-Null
}

function Remove-BcdElementValue {
    param([string]$Element, [string]$Store = '{current}')
    $r = Invoke-NativeCommand -FilePath 'bcdedit' -Arguments @('/deletevalue', $Store, $Element)
    # /deletevalue devolve erro se o elemento ja estiver ausente. Para Undo de
    # um estado originalmente ausente, isso ja satisfaz o estado desejado.
    if ($r.ExitCode -ne 0) {
        $cur = Get-BcdElementState -Element $Element -Store $Store
        if ($cur.Exists) { Assert-NativeCommandSuccess -Result $r -Operation "bcdedit /deletevalue $Store $Element" | Out-Null }
    }
}

function Restore-BcdElementState {
    # Undo: distingue "existia" de "nao existia" - nunca inventa um valor.
    param($StateBefore, [string]$Store = '{current}')
    if (-not $StateBefore.Exists) {
        Remove-BcdElementValue -Element $StateBefore.Element -Store $Store
    } else {
        Set-BcdElementValue -Element $StateBefore.Element -Value $StateBefore.Value -Store $Store
    }
}

function Test-BcdElementValue {
    param([string]$Element, $ExpectedValue, [bool]$ExpectedExists = $true, [string]$Store = '{current}')
    $cur = Get-BcdElementState -Element $Element -Store $Store
    $normalizedExpected = Normalize-BcdComparableValue -Value $ExpectedValue
    $normalizedActual = Normalize-BcdComparableValue -Value $cur.Value
    $pass = if (-not $ExpectedExists) { -not $cur.Exists } else { $cur.Exists -and ($normalizedActual -eq $normalizedExpected) }
    return [PSCustomObject]@{ Type = 'BCD'; Target = $Element; Expected = $(if ($ExpectedExists) { $ExpectedValue } else { '<ausente>' }); Actual = $(if ($cur.Exists) { $cur.Value } else { '<ausente>' }); Pass = [bool]$pass }
}

function Invoke-BcdProvider {
    <#
        Correção Fase 2.1: Backup-BcdElementState (que EXPORTA a store, uma
        operação não-trivial) só roda no Apply. No Undo, o $referenceState é
        SEMPRE o BackupData recebido - nunca uma consulta "ao vivo" no
        momento do Undo, que já refletiria o estado JÁ ALTERADO (mesmo bug
        do RegistryProvider: consultar "antes" depois de já ter mudado).
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$Element,
        [string]$TargetValue = 'true',
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null,
        [string]$Store = '{current}'
    )
    $errorMsg = $null
    $changed = $false
    $referenceState = $null

    try {
        if ($Action -eq 'Apply') {
            $referenceState = Backup-BcdElementState -Element $Element -Store $Store
            Set-BcdElementValue -Element $Element -Value $TargetValue -Store $Store
            $changed = $true
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar o elemento BCD '$Element' com segurança sem o estado original salvo."
            }
            $referenceState = $BackupData
            Restore-BcdElementState -StateBefore $referenceState -Store $Store
            $changed = $true
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $after = Get-BcdElementState -Element $Element -Store $Store
    $verifyCheck = if ($errorMsg) {
        [PSCustomObject]@{ Type = 'BCD'; Target = $Element; Expected = '<não verificável - erro na execução>'; Actual = '<não verificável>'; Pass = $false }
    } elseif ($Action -eq 'Apply') {
        Test-BcdElementValue -Element $Element -ExpectedValue $TargetValue -ExpectedExists $true -Store $Store
    } else {
        Test-BcdElementValue -Element $Element -ExpectedValue $referenceState.Value -ExpectedExists $referenceState.Exists -Store $Store
    }

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]($changed -and -not $errorMsg -and $verifyCheck.Pass)) -Changed $changed `
        -StateBefore $referenceState -StateAfter $after `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyCheck.Pass; Checks = @($verifyCheck) }) `
        -Restart 'Reboot' -ErrorMessage $errorMsg
}
