function Test-PowerCfgVerify {
    # Hibernacao: confirmavel via registro (robusto, sem depender do idioma
    # do Windows). Plano de energia ativo: 'powercfg /getactivescheme' tem
    # texto localizado, mas o GUID dentro da saida NAO muda por idioma -
    # extrai só o GUID via regex em vez de comparar a frase inteira.
    param([string]$ScriptText)
    $checks = @()
    if ($ScriptText -match '(?i)powercfg\s+/hibernate\s+(on|off)') {
        $expectOn = ($Matches[1].ToLower() -eq 'on')
        $cur = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction SilentlyContinue
        $actual = if ($cur -and ($cur.PSObject.Properties.Name -contains 'HibernateEnabled')) { [bool]$cur.HibernateEnabled } else { $null }
        $checks += [PSCustomObject]@{ Type = 'PowerCfg'; Target = 'Hibernação (HibernateEnabled)'; Expected = $expectOn; Actual = $(if ($null -ne $actual) { $actual } else { '<indeterminado>' }); Pass = ($null -ne $actual -and $actual -eq $expectOn) }
    }
    $guidMatch = [regex]::Match($ScriptText, '(?i)/setactive\s+([0-9a-f-]{36})')
    if ($guidMatch.Success) {
        $expectedGuid = $guidMatch.Groups[1].Value.ToLower()
        $activeResult = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/getactivescheme')
        $actualGuidMatch = if ($activeResult.Output) { [regex]::Match($activeResult.Output, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'IgnoreCase') } else { $null }
        $actualGuid = if ($actualGuidMatch -and $actualGuidMatch.Success) { $actualGuidMatch.Value.ToLower() } else { $null }
        $checks += [PSCustomObject]@{ Type = 'PowerCfg'; Target = 'Plano de energia ativo'; Expected = $expectedGuid; Actual = $(if ($actualGuid) { $actualGuid } else { '<indeterminado>' }); Pass = ($null -ne $actualGuid -and $actualGuid -eq $expectedGuid) }
    }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2 / 2.1)
# ============================================================================

function Get-HibernateState {
    $cur = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name 'HibernateEnabled' -ErrorAction SilentlyContinue
    $val = if ($cur -and ($cur.PSObject.Properties.Name -contains 'HibernateEnabled')) { [bool]$cur.HibernateEnabled } else { $null }
    return [PSCustomObject]@{ Setting = 'Hibernate'; Enabled = $val; Queryable = ($null -ne $val) }
}

function Set-HibernateState {
    param([bool]$Enabled)
    $arg = if ($Enabled) { 'on' } else { 'off' }
    $r = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/hibernate', $arg)
    Assert-NativeCommandSuccess -Result $r -Operation "powercfg /hibernate $arg" | Out-Null
}

function Get-ActivePowerScheme {
    $result = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/getactivescheme')
    $m = if ($result.ExitCode -eq 0 -and $result.Output) { [regex]::Match($result.Output, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'IgnoreCase') } else { $null }
    $guid = if ($m -and $m.Success) { $m.Value.ToLower() } else { $null }
    return [PSCustomObject]@{ Setting = 'ActiveScheme'; Guid = $guid; Queryable = ($null -ne $guid) }
}

function Set-ActivePowerScheme {
    param([string]$Guid)
    $r = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/setactive', $Guid)
    Assert-NativeCommandSuccess -Result $r -Operation "powercfg /setactive $Guid" | Out-Null
}

# Sub-configuracoes (CPU throttling, core parking, USB selective suspend,
# PCIe ASPM, idle states etc.) todas usam o MESMO mecanismo de indice - uma
# API generica aqui cobre varios gaps futuros da Fase 5 de uma vez so.
function Get-PowerSettingIndex {
    param([string]$SubgroupGuid, [string]$SettingGuid, [string]$Scheme = 'SCHEME_CURRENT')
    $result = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/query', $Scheme, $SubgroupGuid, $SettingGuid)
    if ($result.ExitCode -ne 0 -or -not $result.Output) { return [PSCustomObject]@{ AC = $null; DC = $null; Queryable = $false } }
    # Fase 2.1B: nao depender dos rotulos em ingles do powercfg. Os indices
    # atuais AC/DC sao os dois ultimos valores 0x... da consulta especifica
    # do setting, independentemente do idioma da interface do Windows.
    $hexMatches = @([regex]::Matches($result.Output, '(?i)0x([0-9a-f]+)'))
    $ac = $null; $dc = $null
    if ($hexMatches.Count -ge 2) {
        $ac = [Convert]::ToInt64($hexMatches[$hexMatches.Count - 2].Groups[1].Value, 16)
        $dc = [Convert]::ToInt64($hexMatches[$hexMatches.Count - 1].Groups[1].Value, 16)
    }
    return [PSCustomObject]@{ AC = $ac; DC = $dc; Queryable = ($null -ne $ac -and $null -ne $dc) }
}

function Set-PowerSettingIndex {
    param([string]$SubgroupGuid, [string]$SettingGuid, [int]$AcValue, [int]$DcValue, [string]$Scheme = 'SCHEME_CURRENT')
    $rAc = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/setacvalueindex', $Scheme, $SubgroupGuid, $SettingGuid, $AcValue)
    Assert-NativeCommandSuccess -Result $rAc -Operation "powercfg /setacvalueindex $Scheme $SubgroupGuid $SettingGuid $AcValue" | Out-Null
    $rDc = Invoke-NativeCommand -FilePath 'powercfg' -Arguments @('/setdcvalueindex', $Scheme, $SubgroupGuid, $SettingGuid, $DcValue)
    Assert-NativeCommandSuccess -Result $rDc -Operation "powercfg /setdcvalueindex $Scheme $SubgroupGuid $SettingGuid $DcValue" | Out-Null
    # Ativar pelo GUID real evita depender de SCHEME_CURRENT ser aceito em /setactive.
    $active = Get-ActivePowerScheme
    if ($active.Queryable) { Set-ActivePowerScheme -Guid $active.Guid }
}

function Invoke-PowerCfgProvider {
    <#
        Correção Fase 2.1: $before era calculado incondicionalmente ANTES de
        checar $Action, e usado como fallback silencioso no Undo sem
        BackupData - exatamente o mesmo bug do RegistryProvider (no Undo,
        "antes" tem que ser o backup persistido, nunca uma consulta ao vivo
        feita depois que o Apply já rodou). Agora só calcula estado "antes"
        de verdade dentro do ramo Apply; Undo exige BackupData ou lança erro.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [ValidateSet('Hibernate', 'Scheme', 'SettingIndex')] [string]$Mode,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        [bool]$TargetHibernate = $false,
        [string]$TargetSchemeGuid,
        [string]$SubgroupGuid, [string]$SettingGuid, [int]$TargetAc, [int]$TargetDc,
        $BackupData = $null
    )
    $errorMsg = $null
    $changed = $false
    $referenceState = $null

    function Get-CurrentState {
        switch ($Mode) {
            'Hibernate' { Get-HibernateState }
            'Scheme' { Get-ActivePowerScheme }
            'SettingIndex' { Get-PowerSettingIndex -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid }
        }
    }

    try {
        if ($Action -eq 'Apply') {
            $referenceState = Get-CurrentState
            switch ($Mode) {
                'Hibernate' { Set-HibernateState -Enabled $TargetHibernate }
                'Scheme' { Set-ActivePowerScheme -Guid $TargetSchemeGuid }
                'SettingIndex' { Set-PowerSettingIndex -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -AcValue $TargetAc -DcValue $TargetDc }
            }
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' (modo $Mode) requer BackupData persistido - não há como restaurar com segurança sem o estado original salvo."
            }
            $referenceState = $BackupData
            switch ($Mode) {
                'Hibernate' { Set-HibernateState -Enabled $referenceState.Enabled }
                'Scheme' { Set-ActivePowerScheme -Guid $referenceState.Guid }
                'SettingIndex' { Set-PowerSettingIndex -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -AcValue $referenceState.AC -DcValue $referenceState.DC }
            }
        }
        $changed = $true
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $after = Get-CurrentState

    $verifyOk = if ($errorMsg) { $false } else {
        switch ($Mode) {
            'Hibernate' { $after.Queryable -and ($after.Enabled -eq $(if ($Action -eq 'Apply') { $TargetHibernate } else { $referenceState.Enabled })) }
            'Scheme' { $after.Queryable -and ($after.Guid -eq $(if ($Action -eq 'Apply') { $TargetSchemeGuid.ToLower() } else { $referenceState.Guid })) }
            'SettingIndex' {
                $expAc = if ($Action -eq 'Apply') { $TargetAc } else { $referenceState.AC }
                $expDc = if ($Action -eq 'Apply') { $TargetDc } else { $referenceState.DC }
                $after.Queryable -and ($after.AC -eq $expAc) -and ($after.DC -eq $expDc)
            }
        }
    }

    $expectedText = switch ($Mode) {
        'Hibernate' { "Enabled=$(if ($Action -eq 'Apply') { $TargetHibernate } else { $referenceState.Enabled })" }
        'Scheme' { "Guid=$(if ($Action -eq 'Apply') { $TargetSchemeGuid } else { $referenceState.Guid })" }
        'SettingIndex' { "AC=$(if ($Action -eq 'Apply') { $TargetAc } else { $referenceState.AC });DC=$(if ($Action -eq 'Apply') { $TargetDc } else { $referenceState.DC })" }
    }
    $actualText = switch ($Mode) {
        'Hibernate' { "Enabled=$($after.Enabled)" }
        'Scheme' { "Guid=$($after.Guid)" }
        'SettingIndex' { "AC=$($after.AC);DC=$($after.DC)" }
    }
    $verifyCheck = [PSCustomObject]@{ Type = 'PowerCfg'; Target = $Mode; Expected = $expectedText; Actual = $actualText; Pass = [bool]$verifyOk }

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool](-not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore $referenceState -StateAfter $after `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = @($verifyCheck) }) `
        -Restart 'None' -ErrorMessage $errorMsg
}
