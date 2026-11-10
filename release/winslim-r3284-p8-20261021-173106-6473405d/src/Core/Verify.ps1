function New-EngineContext {
    # Mantém compatibilidade com quem já chama New-EngineContext (Run-Batch),
    # mas agora devolve o $Context formal completo via Get-SystemContext.
    $sys = Get-SystemContext -HwInfo $HwInfo -WinVersion $WinVersion -WinBuild $WinBuild
    return [PSCustomObject]@{
        WinVersion     = $WinVersion
        WinBuild       = $WinBuild
        Hardware       = $HwInfo
        SimulationMode = $script:SimulationMode
        ScriptRoot     = $ScriptRoot
        Timestamp      = (Get-Date -Format 'o')
        System         = $sys
    }
}

function Test-TweakVerify {
    param($Tweak, [switch]$Undo, [int]$Level = -1)
    $payload = $Tweak
    if ($Tweak.type -eq 'multilevel') {
        $idx = if ($Level -lt 0) { 0 } else { $Level }
        $payload = $Tweak.levels[$idx]
    }
    $classes = @($Tweak.rollbackClass)
    $supported = @('Registry', 'Service', 'BCD', 'PowerCfg', 'Network', 'AppX', 'ScheduledTask', 'DISM', 'Feature')
    if (-not (@($classes | Where-Object { $supported -contains $_ }))) {
        return [PSCustomObject]@{ Success = $true; Applicable = $false; Checks = @() }
    }

    $checks = @()
    if ($payload.registry) {
        foreach ($c in Test-RegistryVerify -RegistryOps $payload.registry -Undo:$Undo) { $checks += $c }
    }
    if ($payload.service) {
        foreach ($c in Test-ServiceVerify -ServiceOps $payload.service -Undo:$Undo) { $checks += $c }
    }

    $scriptText = if ($Undo) { $payload.UndoScript -join "`n" } else { $payload.InvokeScript -join "`n" }
    if ($classes -contains 'Registry' -and -not $payload.registry) {
        foreach ($c in Test-EmbeddedRegistryVerify -ScriptText $scriptText) { $checks += $c }
    }
    if ($classes -contains 'BCD') { foreach ($c in Test-BcdElementVerify -ScriptText $scriptText) { $checks += $c } }
    if ($classes -contains 'PowerCfg') { foreach ($c in Test-PowerCfgVerify -ScriptText $scriptText) { $checks += $c } }
    if ($classes -contains 'Network') { foreach ($c in Test-NetworkVerify -ScriptText $scriptText) { $checks += $c } }
    if ($classes -contains 'AppX' -and $payload.packages) { foreach ($c in Test-AppxVerify -Packages $payload.packages -Undo:$Undo) { $checks += $c } }
    if ($classes -contains 'ScheduledTask') { foreach ($c in Test-ScheduledTaskVerify -ScriptText $scriptText) { $checks += $c } }
    if ($classes -contains 'DISM') { foreach ($c in Test-DismVerify -ScriptText $scriptText) { $checks += $c } }
    if ($classes -contains 'Feature') { foreach ($c in Test-FeatureVerify -ScriptText $scriptText) { $checks += $c } }

    # Fase 2.1B: verificacao aplicavel com ZERO checks nao pode ser sucesso.
    # Sem evidencia observavel, o resultado correto e inconclusivo/falha, nunca PASS.
    $allPass = (@($checks).Count -gt 0) -and (-not (@($checks) | Where-Object { -not $_.Pass }))
    return [PSCustomObject]@{ Success = [bool]$allPass; Applicable = $true; Checks = @($checks) }
}

function Invoke-Tweak {
    param(
        [Parameter(Mandatory)] $Tweak,
        [ValidateSet('Apply', 'Undo', 'Verify')] [string]$Action = 'Apply',
        [int]$Level = -1,
        $Context = $null,
        [switch]$StrictVerify
    )
    if (-not $Context) { $Context = New-EngineContext }
    $undo = ($Action -eq 'Undo')

    $result = [PSCustomObject]@{
        Id           = $Tweak.id
        Action       = $Action
        Success      = $false
        Changed      = $false
        Verification = $null
        Restart      = $Tweak.restartScope
        Warning      = $null
        Error        = $null
    }

    if ($Action -eq 'Verify') {
        $result.Verification = Test-TweakVerify -Tweak $Tweak -Level $Level
        $result.Success = $result.Verification.Success
        return $result
    }

    $applied = Invoke-TweakEngine -Tweak $Tweak -Undo:$undo -Level $Level
    $result.Success = [bool]$applied
    $result.Changed = [bool]$applied

    if ($applied -and -not $Context.SimulationMode) {
        $v = Test-TweakVerify -Tweak $Tweak -Undo:$undo -Level $Level
        $result.Verification = $v
        if ($v.Applicable -and -not $v.Success) {
            $result.Warning = 'Apply retornou sucesso, mas a verificação pós-apply encontrou divergência (ver log).'
            $mismatches = (@($v.Checks) | Where-Object { -not $_.Pass } | ForEach-Object { "$($_.Target) esperado=$($_.Expected) atual=$($_.Actual)" }) -join '; '
            Write-Log "[VERIFY] $($Tweak.id) divergência: $mismatches" 'WARN'
            # Fase 3: o Transaction Manager usa -StrictVerify. Nesse modo,
            # Apply sem confirmação observável NÃO pode ser tratado como sucesso,
            # pois uma transação precisa decidir rollback com base no Verify.
            if ($StrictVerify) {
                $result.Success = $false
                $result.Error = "Verificação pós-apply falhou: $mismatches"
            }
        }
    }
    if (-not $applied) { $result.Error = 'Falha na aplicação - ver winslim-log.txt para detalhes.' }
    return $result
}
