function Test-ServiceVerify {
    param($ServiceOps, [switch]$Undo)
    $checks = @()
    foreach ($s in @($ServiceOps)) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        $expected = if ($Undo) { $s.OriginalType } else { $s.StartupType }
        $pass = $svc -and ($svc.StartType.ToString() -eq $expected)
        $checks += [PSCustomObject]@{ Type = 'Service'; Target = $s.Name; Expected = $expected; Actual = $(if ($svc) { $svc.StartType.ToString() } else { '<serviço ausente>' }); Pass = [bool]$pass }
    }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2)
# ============================================================================

function Get-ServiceState {
    # Detect: StartupType + Status + DelayedAutoStart (esse ultimo nao vem
    # de Get-Service - so existe no Registro, em DelayedAutostart DWORD).
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [PSCustomObject]@{ Name = $Name; Exists = $false; StartupType = $null; Status = $null; DelayedAutoStart = $null }
    }
    $delayed = $false
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        $val = (Get-ItemProperty -Path $regPath -Name 'DelayedAutostart' -ErrorAction SilentlyContinue).DelayedAutostart
        $delayed = [bool]$val
    } catch { }
    return [PSCustomObject]@{
        Name             = $Name
        Exists           = $true
        StartupType      = $svc.StartType.ToString()
        Status           = $svc.Status.ToString()
        DelayedAutoStart = $delayed
    }
}

function Set-ServiceState {
    param([string]$Name, [string]$StartupType, [bool]$DelayedAutoStart = $false, [switch]$StopNow)
    if ($StopNow) { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Name -StartupType $StartupType -ErrorAction SilentlyContinue
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        if (Test-Path $regPath) {
            New-ItemProperty -Path $regPath -Name 'DelayedAutostart' -PropertyType DWord -Value ([int][bool]$DelayedAutoStart) -Force | Out-Null
        }
    } catch { }
}

function Test-ServiceValue {
    param([string]$Name, [string]$ExpectedStartupType)
    $cur = Get-ServiceState -Name $Name
    $pass = $cur.Exists -and ($cur.StartupType -eq $ExpectedStartupType)
    return [PSCustomObject]@{ Type = 'Service'; Target = $Name; Expected = $ExpectedStartupType; Actual = $(if ($cur.Exists) { $cur.StartupType } else { '<serviço ausente>' }); Pass = [bool]$pass }
}

function Backup-ServiceState {
    param([string]$Name)
    return Get-ServiceState -Name $Name
}

function Restore-ServiceState {
    param($StateBefore)
    if (-not $StateBefore.Exists) { return }
    Set-ServiceState -Name $StateBefore.Name -StartupType $StateBefore.StartupType -DelayedAutoStart $StateBefore.DelayedAutoStart
    # Fase 2.1B: StartupType sozinho nao e rollback exato. Restaura tambem
    # o estado operacional quando o snapshot era inequivocamente Running/Stopped.
    if ($StateBefore.Status -eq 'Running') { Start-Service -Name $StateBefore.Name -ErrorAction SilentlyContinue }
    elseif ($StateBefore.Status -eq 'Stopped') { Stop-Service -Name $StateBefore.Name -Force -ErrorAction SilentlyContinue }
}

function Invoke-ServiceProvider {
    <#
        Correções Fase 2.1 (mesmas de Invoke-RegistryProvider, aplicadas por
        consistência - todo provider tinha o mesmo padrão de risco):
        array simples em vez de Generic.List; $referenceState explícito
        (Undo exige BackupData, nunca cai pra $stateBefore vazio); Verify só
        passa se o número de checks bater com o número de operações.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] $ServiceOps,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null
    )
    $stateBefore = @()
    $stateAfter = @()
    $referenceState = @()
    $changed = $false
    $errorMsg = $null

    try {
        if ($Action -eq 'Apply') {
            foreach ($op in @($ServiceOps)) {
                $before = Backup-ServiceState -Name $op.Name
                $stateBefore += $before
                Set-ServiceState -Name $op.Name -StartupType $op.StartupType -StopNow:($op.StartupType -eq 'Disabled')
                $changed = $true
            }
            $referenceState = $stateBefore
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar com segurança sem o estado original salvo."
            }
            $referenceState = @($BackupData)
            foreach ($before in $referenceState) {
                Restore-ServiceState -StateBefore $before
                $changed = $true
            }
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    foreach ($op in @($ServiceOps)) { $stateAfter += (Get-ServiceState -Name $op.Name) }

    $verifyChecks = @()
    foreach ($op in @($ServiceOps)) {
        $cur = Get-ServiceState -Name $op.Name
        if ($Action -eq 'Apply') {
            $expectStopped = ($op.StartupType -eq 'Disabled')
            $pass = $cur.Exists -and ($cur.StartupType -eq $op.StartupType) -and (-not $cur.DelayedAutoStart) -and
                    (-not $expectStopped -or $cur.Status -eq 'Stopped')
            $verifyChecks += [PSCustomObject]@{
                Type='Service'; Target=$op.Name;
                Expected="StartupType=$($op.StartupType);DelayedAutoStart=False$(if ($expectStopped) { ';Status=Stopped' } else { '' })";
                Actual="StartupType=$($cur.StartupType);DelayedAutoStart=$($cur.DelayedAutoStart);Status=$($cur.Status)"; Pass=[bool]$pass
            }
        } else {
            $matchRef = @($referenceState) | Where-Object { $_.Name -eq $op.Name } | Select-Object -First 1
            if ($matchRef -and $matchRef.Exists) {
                $statusPass = if ($matchRef.Status -in @('Running','Stopped')) { $cur.Status -eq $matchRef.Status } else { $true }
                $pass = $cur.Exists -and ($cur.StartupType -eq $matchRef.StartupType) -and
                        ([bool]$cur.DelayedAutoStart -eq [bool]$matchRef.DelayedAutoStart) -and $statusPass
                $verifyChecks += [PSCustomObject]@{
                    Type='Service'; Target=$op.Name;
                    Expected="StartupType=$($matchRef.StartupType);DelayedAutoStart=$($matchRef.DelayedAutoStart);Status=$($matchRef.Status)";
                    Actual="StartupType=$($cur.StartupType);DelayedAutoStart=$($cur.DelayedAutoStart);Status=$($cur.Status)"; Pass=[bool]$pass
                }
            } else {
                $verifyChecks += [PSCustomObject]@{ Type='Service'; Target=$op.Name; Expected='<referencia valida>'; Actual='<referencia ausente ou servico nunca existiu>'; Pass=$false }
            }
        }
    }
    $verifyOk = (@($verifyChecks).Count -eq @($ServiceOps).Count) -and (@($verifyChecks).Count -gt 0) -and (-not (@($verifyChecks) | Where-Object { -not $_.Pass }))

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool](-not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore @($stateBefore) -StateAfter @($stateAfter) `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = @($verifyChecks) }) `
        -Restart 'Service' -ErrorMessage $errorMsg
}
