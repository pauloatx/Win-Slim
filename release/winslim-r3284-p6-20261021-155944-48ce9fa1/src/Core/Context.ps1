function Get-WinMajorVersion {
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    if ($build -ge 22000) { return '11' } else { return '10' }
}

# ============================================================================
# AUTO-DETECÇÃO DE HARDWARE (CPU / RAM / GPU / disco) - mantido como estava,
# ainda usado pelo badge discreto do cabeçalho da UI atual.
# ============================================================================
function Get-HardwareSummary {
    $info = [ordered]@{ CPU = $null; RamGB = $null; GPUs = @(); DiskType = $null }
    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu -and $cpu.Name) { $info.CPU = ($cpu.Name -replace '\s+', ' ').Trim() }
    } catch { Write-Log "Auto-detecção: falha ao ler CPU ($($_.Exception.Message))." 'WARN' }
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs -and $cs.TotalPhysicalMemory) { $info.RamGB = [Math]::Round($cs.TotalPhysicalMemory / 1GB) }
    } catch { Write-Log "Auto-detecção: falha ao ler RAM ($($_.Exception.Message))." 'WARN' }
    try {
        $info.GPUs = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch 'Microsoft Basic|Remote Display|Meta Virtual|Citrix' } |
            Select-Object -ExpandProperty Name)
    } catch { Write-Log "Auto-detecção: falha ao ler GPU ($($_.Exception.Message))." 'WARN' }
    try {
        $disk = Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop | Select-Object -First 1
        if ($disk) { $info.DiskType = switch ([int]$disk.MediaType) { 4 { 'SSD' } 3 { 'HDD' } default { $null } } }
    } catch { Write-Log "Auto-detecção: falha ao ler tipo de disco ($($_.Exception.Message))." 'WARN' }
    return [pscustomobject]$info
}

# ============================================================================
# CONTEXTO FORMAL (Fase 1 do backlog) - fonte de verdade do sistema, consumida
# pelo Planner (Fase 4) para resolver hardwareRules/mutexGroup/dependencies.
# Cada campo é detectado isoladamente: falhar em um (ex.: TPM ausente, sem
# UEFI/Secure Boot, VM sem sensores) nunca derruba os outros nem a UI.
# ============================================================================
function Get-SystemContext {
    param($HwInfo, [string]$WinVersion, [string]$WinBuild)

    $ctx = [ordered]@{
        OS = $null; Build = $null; Architecture = $null
        CPU = $null; GPU = @(); RAM = $null; Storage = $null
        SecureBoot = $null; TPM = $null; VBS = $null; HVCI = $null; HyperV = $null
        PowerPlan = $null; NetworkAdapters = @(); Services = @(); PendingReboot = $false
        IsAdmin = $false
    }

    $ctx.OS = $WinVersion
    $ctx.Build = $WinBuild
    $ctx.CPU = $HwInfo.CPU
    $ctx.GPU = @($HwInfo.GPUs)
    $ctx.RAM = $HwInfo.RamGB
    $ctx.Storage = $HwInfo.DiskType

    try { $ctx.Architecture = $env:PROCESSOR_ARCHITECTURE } catch { }

    try { $ctx.IsAdmin = Test-IsAdmin } catch { $ctx.IsAdmin = $false }

    try {
        # Confirm-SecureBootUEFI lança exceção em BIOS legado (sem UEFI) -
        # isso é uma resposta válida ("não suportado"), não um erro de
        # detecção. Por isso Supported/Enabled são campos SEPARADOS: "false"
        # sozinho não deixa claro se o hardware não suporta Secure Boot ou se
        # suporta e está desligado - distinção que hardwareRules vai precisar.
        $enabled = Confirm-SecureBootUEFI -ErrorAction Stop
        $ctx.SecureBoot = [PSCustomObject]@{ Supported = $true; Enabled = [bool]$enabled }
    } catch {
        # O tipo .NET exato da exceção não é garantido em toda versão do
        # PowerShell/Windows, mas a mensagem "not supported on this platform"
        # É documentada e estável (é o texto literal que Confirm-SecureBootUEFI
        # emite em BIOS legado/sem UEFI). Checar o texto é mais confiável do
        # que apostar num tipo de exceção que eu não consigo confirmar 100%.
        if ($_.Exception.Message -match '(?i)not supported on this platform') {
            $ctx.SecureBoot = [PSCustomObject]@{ Supported = $false; Enabled = $null }
            Write-Log "Contexto: Secure Boot não suportado (BIOS legado, sem UEFI)." 'INFO'
        } else {
            $ctx.SecureBoot = [PSCustomObject]@{ Supported = $null; Enabled = $null }
            Write-Log "Contexto: não foi possível determinar suporte a Secure Boot ($($_.Exception.Message))." 'WARN'
        }
    }

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $ctx.TPM = [PSCustomObject]@{ Present = $tpm.TpmPresent; Ready = $tpm.TpmReady }
    } catch {
        $ctx.TPM = [PSCustomObject]@{ Present = $false; Ready = $false }
        Write-Log "Contexto: TPM não detectável neste sistema ($($_.Exception.Message))." 'INFO'
    }

    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop
        $ctx.VBS = [bool]($dg.VirtualizationBasedSecurityStatus -eq 2)
        $ctx.HVCI = [bool]($dg.SecurityServicesRunning -contains 2)
    } catch {
        Write-Log "Contexto: falha ao ler status de VBS/HVCI ($($_.Exception.Message))." 'WARN'
    }

    try {
        # "Hypervisor presente" (HypervisorPresent) NÃO é o mesmo que
        # "recurso Hyper-V instalado/habilitado" - uma VM rodando dentro de
        # outro hypervisor, ou WSL2/Docker usando o Hypervisor Platform sem
        # o Hyper-V completo instalado, também retornam HypervisorPresent=true.
        # Por isso os 4 sinais ficam separados; um tweak "hyper-v-off" precisa
        # saber especificamente FeatureInstalled, não só se algum hypervisor
        # qualquer está ativo no momento.
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $hypervisorRunning = [bool]$cs.HypervisorPresent

        $featureInstalled = $null
        try {
            $feat = Get-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -ErrorAction Stop
            $featureInstalled = ($feat.State.ToString() -eq 'Enabled')
        } catch { }

        $launchType = $null
        try {
            $bcdOut = (bcdedit /enum '{current}' 2>&1 | Out-String)
            $m = [regex]::Match($bcdOut, '(?i)hypervisorlaunchtype\s+(\S+)')
            if ($m.Success) { $launchType = $m.Groups[1].Value }
        } catch { }

        $wsl2 = $false
        try {
            $wslFeat = Get-WindowsOptionalFeature -Online -FeatureName 'VirtualMachinePlatform' -ErrorAction Stop
            $wsl2 = ($wslFeat.State.ToString() -eq 'Enabled')
        } catch { }

        $ctx.HyperV = [PSCustomObject]@{
            FeatureInstalled  = $featureInstalled
            HypervisorRunning = $hypervisorRunning
            LaunchType        = $launchType
            WSL2Detected      = $wsl2
        }
    } catch { Write-Log "Contexto: falha ao ler estado do Hyper-V ($($_.Exception.Message))." 'WARN' }

    try {
        $out = (powercfg /getactivescheme 2>&1 | Out-String)
        $g = [regex]::Match($out, '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', 'IgnoreCase')
        if ($g.Success) { $ctx.PowerPlan = $g.Value.ToLower() }
    } catch { Write-Log "Contexto: falha ao ler plano de energia ativo ($($_.Exception.Message))." 'WARN' }

    try {
        $ctx.NetworkAdapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name)
    } catch { Write-Log "Contexto: falha ao listar adaptadores de rede ($($_.Exception.Message))." 'WARN' }

    # Services fica vazio por padrão de propósito: dump de TODOS os serviços é
    # caro e a maioria irrelevante. O Planner (Fase 4) consulta serviços
    # específicos sob demanda quando uma hardwareRule/dependency precisar.
    $ctx.Services = @()

    try {
        $pendingKeys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        $ctx.PendingReboot = [bool]($pendingKeys | Where-Object { Test-Path $_ })
        if (-not $ctx.PendingReboot) {
            $pfro = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue)
            $ctx.PendingReboot = [bool]($pfro -and $pfro.PendingFileRenameOperations)
        }
    } catch { Write-Log "Contexto: falha ao checar reboot pendente ($($_.Exception.Message))." 'WARN' }

    return [PSCustomObject]$ctx
}
