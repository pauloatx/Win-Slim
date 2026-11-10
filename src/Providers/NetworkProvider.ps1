function Test-NetworkVerify {
    # Prioriza cmdlets estruturados (Get-NetFirewallProfile) quando existem -
    # zero risco de idioma. Registro embutido reaproveita Test-EmbeddedRegistryVerify.
    param([string]$ScriptText)
    $checks = @()

    $fwMatch = [regex]::Match($ScriptText, "(?i)Set-NetFirewallProfile\s+-Profile\s+([\w,]+)\s+-Enabled\s+(True|False)")
    if ($fwMatch.Success) {
        $expected = [bool]::Parse($fwMatch.Groups[2].Value)
        foreach ($p in ($fwMatch.Groups[1].Value -split ',')) {
            $cur = Get-NetFirewallProfile -Profile $p -ErrorAction SilentlyContinue
            $actual = if ($cur) { $cur.Enabled } else { $null }
            $checks += [PSCustomObject]@{ Type = 'Network'; Target = "Firewall ($p)"; Expected = $expected; Actual = $(if ($null -ne $actual) { $actual } else { '<indeterminado>' }); Pass = ($null -ne $actual -and $actual -eq $expected) }
        }
    }
    foreach ($c in Test-EmbeddedRegistryVerify -ScriptText $ScriptText) { $checks += $c }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2 / 2.1) - regra explicita: backup e POR
# INTERFACE (GUID), nunca global. Uma maquina com 2+ adaptadores fisicos
# (ex.: Wi-Fi + Ethernet) precisa restaurar CADA UM pro que era antes, nao
# aplicar o mesmo valor "medio" pra todos.
# ============================================================================

function Get-ActivePhysicalAdapters {
    try { return @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' }) }
    catch { Write-Log "NetworkProvider: falha ao listar adaptadores fisicos ($($_.Exception.Message))." 'WARN'; return @() }
}

function Get-NicTcpState {
    # Detect: TcpNoDelay/TcpAckFrequency/TcpDelAckTicks de UMA interface (por GUID).
    param([string]$InterfaceGuid)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $keyPath = Join-Path $base $InterfaceGuid
    if (-not (Test-Path $keyPath)) { return [PSCustomObject]@{ InterfaceGuid = $InterfaceGuid; Exists = $false } }
    $cur = Get-ItemProperty -Path $keyPath -ErrorAction SilentlyContinue
    return [PSCustomObject]@{
        InterfaceGuid    = $InterfaceGuid
        Exists           = $true
        TcpNoDelay       = if ($cur.PSObject.Properties.Name -contains 'TcpNoDelay') { $cur.TcpNoDelay } else { $null }
        TcpAckFrequency  = if ($cur.PSObject.Properties.Name -contains 'TcpAckFrequency') { $cur.TcpAckFrequency } else { $null }
        TcpDelAckTicks   = if ($cur.PSObject.Properties.Name -contains 'TcpDelAckTicks') { $cur.TcpDelAckTicks } else { $null }
    }
}

function Set-NicTcpState {
    param([string]$InterfaceGuid, [int]$TcpNoDelay = 1, [int]$TcpAckFrequency = 1, [int]$TcpDelAckTicks = 0)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $keyPath = Join-Path $base $InterfaceGuid
    if (-not (Test-Path $keyPath)) { return }
    New-ItemProperty -Path $keyPath -Name 'TcpNoDelay' -Value $TcpNoDelay -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'TcpAckFrequency' -Value $TcpAckFrequency -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'TcpDelAckTicks' -Value $TcpDelAckTicks -PropertyType DWord -Force | Out-Null
}

function Restore-NicTcpState {
    # Undo por interface: remove os valores que nao existiam antes; restaura
    # os que existiam. Nunca assume "0" ou "remover tudo" pra todo mundo.
    param($StateBefore)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $keyPath = Join-Path $base $StateBefore.InterfaceGuid
    if (-not (Test-Path $keyPath)) { return }
    foreach ($name in @('TcpNoDelay', 'TcpAckFrequency', 'TcpDelAckTicks')) {
        if ($null -eq $StateBefore.$name) {
            Remove-ItemProperty -Path $keyPath -Name $name -ErrorAction SilentlyContinue
        } else {
            Set-ItemProperty -Path $keyPath -Name $name -Value $StateBefore.$name -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-NetworkNagleProvider {
    <#
        Correção Fase 2.1: $stateBefore só era populado dentro do ramo Apply;
        no ramo Undo, o fallback "senão usa $stateBefore" caía numa lista
        VAZIA (mesmo bug de referência-ausente dos outros providers). Agora
        Undo exige BackupData e usa isso como $referenceState, sem exceção.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null
    )
    $adapters = Get-ActivePhysicalAdapters
    $stateBefore = @()
    $stateAfter = @()
    $referenceState = @()
    $changed = $false
    $errorMsg = $null

    try {
        if ($Action -eq 'Apply') {
            foreach ($a in $adapters) {
                $before = Get-NicTcpState -InterfaceGuid $a.InterfaceGuid
                $stateBefore += $before
                if ($before.Exists) { Set-NicTcpState -InterfaceGuid $a.InterfaceGuid; $changed = $true }
            }
            $referenceState = $stateBefore
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar as interfaces de rede com segurança sem o estado original salvo."
            }
            $referenceState = @($BackupData)
            foreach ($before in $referenceState) {
                Restore-NicTcpState -StateBefore $before
                $changed = $true
            }
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $verifyChecks = @()
    if ($Action -eq 'Apply') {
        foreach ($a in $adapters) {
            $after = Get-NicTcpState -InterfaceGuid $a.InterfaceGuid
            $stateAfter += $after
            $pass = $after.Exists -and $after.TcpNoDelay -eq 1 -and $after.TcpAckFrequency -eq 1 -and $after.TcpDelAckTicks -eq 0
            $verifyChecks += [PSCustomObject]@{
                Type='Network'; Target="Nagle ($($a.Name))";
                Expected='TcpNoDelay=1;TcpAckFrequency=1;TcpDelAckTicks=0';
                Actual="TcpNoDelay=$($after.TcpNoDelay);TcpAckFrequency=$($after.TcpAckFrequency);TcpDelAckTicks=$($after.TcpDelAckTicks)"; Pass=[bool]$pass
            }
        }
        $expectedCount = @($adapters).Count
    } else {
        # Verify usa os GUIDs persistidos no backup, mesmo que um adaptador
        # tenha mudado de Status entre Apply e Undo.
        foreach ($ref in @($referenceState)) {
            $after = Get-NicTcpState -InterfaceGuid $ref.InterfaceGuid
            $stateAfter += $after
            $pass = ($after.Exists -eq $ref.Exists) -and
                    ($after.TcpNoDelay -eq $ref.TcpNoDelay) -and
                    ($after.TcpAckFrequency -eq $ref.TcpAckFrequency) -and
                    ($after.TcpDelAckTicks -eq $ref.TcpDelAckTicks)
            $verifyChecks += [PSCustomObject]@{
                Type='Network'; Target="Nagle ($($ref.InterfaceGuid))";
                Expected="Exists=$($ref.Exists);TcpNoDelay=$($ref.TcpNoDelay);TcpAckFrequency=$($ref.TcpAckFrequency);TcpDelAckTicks=$($ref.TcpDelAckTicks)";
                Actual="Exists=$($after.Exists);TcpNoDelay=$($after.TcpNoDelay);TcpAckFrequency=$($after.TcpAckFrequency);TcpDelAckTicks=$($after.TcpDelAckTicks)"; Pass=[bool]$pass
            }
        }
        $expectedCount = @($referenceState).Count
    }
    $verifyOk = ($expectedCount -gt 0) -and (@($verifyChecks).Count -eq $expectedCount) -and (-not (@($verifyChecks) | Where-Object { -not $_.Pass }))

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool](-not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore @($stateBefore) -StateAfter @($stateAfter) `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = @($verifyChecks) }) `
        -Restart 'None' -ErrorMessage $errorMsg
}
