# 6. ROLLBACK PROFISSIONAL - captura o estado REAL antes de cada alteração
# ============================================================================
if (Test-Path $RollbackPath) {
    $RollbackData = @{}
    try { (Get-Content $RollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $RollbackData[$_.Name] = $_.Value } } catch { $RollbackData = @{} }
} else { $RollbackData = @{} }

function Save-Rollback { $RollbackData | ConvertTo-Json -Depth 10 | Out-File -FilePath $RollbackPath -Encoding UTF8 }

function Get-CurrentRegistryState {
    param($Path, $Name)
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($item -and ($item.PSObject.Properties.Name -contains $Name)) {
            return [PSCustomObject]@{ Existed = $true; Value = $item.$Name }
        }
    }
    return [PSCustomObject]@{ Existed = $false; Value = $null }
}

function Backup-BeforeApply {
    param([string]$TweakId, $Payload)
    $snap = [PSCustomObject]@{ timestamp = (Get-Date -Format 'o'); registry = @(); service = @() }
    if ($Payload.registry) {
        foreach ($r in $Payload.registry) {
            $cur = Get-CurrentRegistryState -Path $r.Path -Name $r.Name
            $snap.registry += [PSCustomObject]@{ Path = $r.Path; Name = $r.Name; Type = $r.Type; Existed = $cur.Existed; PriorValue = $cur.Value }
        }
    }
    if ($Payload.service) {
        foreach ($s in $Payload.service) {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            if ($svc) { $snap.service += [PSCustomObject]@{ Name = $s.Name; PriorStartupType = $svc.StartType.ToString() } }
        }
    }
    $RollbackData[$TweakId] = $snap
}

function Restore-FromSnapshot {
    param([string]$TweakId)
    if (-not $RollbackData.ContainsKey($TweakId)) { return $false }
    $snap = $RollbackData[$TweakId]
    foreach ($r in $snap.registry) {
        if ($r.Existed) { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.PriorValue -Type $r.Type }
        else { Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue }
    }
    foreach ($s in $snap.service) {
        Set-Service -Name $s.Name -StartupType $s.PriorStartupType -ErrorAction SilentlyContinue
    }
    $RollbackData.Remove($TweakId)
    return $true
}

# ============================================================================
