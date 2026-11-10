#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R2
 Leitura de hardware/contexto para Dashboard e Analise do Sistema.

 Regra arquitetural: este arquivo e estritamente read-only. Nao aplica tweak,
 nao executa provider e nao altera configuracao do Windows.
#>

function ConvertTo-WinSlimPercent {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        $n = [double]$Value
        if ([double]::IsNaN($n) -or [double]::IsInfinity($n)) { return $null }
        if ($n -lt 0) { $n = 0 }
        if ($n -gt 100) { $n = 100 }
        return [int][Math]::Round($n)
    } catch { return $null }
}

function Get-WinSlimStorageDescriptor {
    [CmdletBinding()]
    param()

    $result = [ordered]@{
        Type = 'Desconhecido'
        Bus = 'Desconhecido'
        Model = 'Nao identificado'
        SizeGB = $null
    }

    try {
        $disk = Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -ErrorAction Stop |
            Sort-Object -Property Size -Descending | Select-Object -First 1
        if ($null -ne $disk) {
            $result.Model = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { 'Disco fisico' }
            if ($disk.Size) { $result.SizeGB = [int][Math]::Round([double]$disk.Size / 1GB) }
            $result.Type = switch ([int]$disk.MediaType) {
                3 { 'HDD' }
                4 { 'SSD' }
                5 { 'SCM' }
                default { 'Desconhecido' }
            }
            $result.Bus = switch ([int]$disk.BusType) {
                1 { 'SCSI' }
                2 { 'ATAPI' }
                3 { 'ATA' }
                7 { 'USB' }
                8 { 'RAID' }
                10 { 'SAS' }
                11 { 'SATA' }
                17 { 'NVMe' }
                18 { 'SCM' }
                19 { 'UFS' }
                default { 'Desconhecido' }
            }
            if ($result.Bus -eq 'NVMe') { $result.Type = 'NVMe' }
            return [pscustomobject]$result
        }
    } catch { }

    try {
        $disk = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop |
            Sort-Object -Property Size -Descending | Select-Object -First 1
        if ($null -ne $disk) {
            if ($disk.Model) { $result.Model = ([string]$disk.Model -replace '\s+', ' ').Trim() }
            if ($disk.Size) { $result.SizeGB = [int][Math]::Round([double]$disk.Size / 1GB) }
            $probe = "{0} {1}" -f $disk.Model, $disk.MediaType
            if ($probe -match '(?i)NVMe') { $result.Type = 'NVMe'; $result.Bus = 'NVMe' }
            elseif ($probe -match '(?i)SSD|Solid State') { $result.Type = 'SSD' }
            elseif ($probe -match '(?i)HDD|Fixed hard disk') { $result.Type = 'HDD' }
            if ($disk.InterfaceType) { $result.Bus = [string]$disk.InterfaceType }
        }
    } catch { }

    return [pscustomobject]$result
}

function Get-WinSlimDeviceType {
    [CmdletBinding()]
    param()

    try {
        $enclosure = Get-CimInstance -ClassName Win32_SystemEnclosure -ErrorAction Stop | Select-Object -First 1
        $codes = @($enclosure.ChassisTypes)
        $portable = @(8,9,10,11,12,14,18,21,30,31,32)
        foreach ($code in $codes) {
            if ($portable -contains [int]$code) { return 'Notebook' }
        }
        if ($codes.Count -gt 0) { return 'Desktop' }
    } catch { }

    try {
        $battery = Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $battery) { return 'Notebook' }
    } catch { }
    return 'Desktop/PC'
}

function Get-WinSlimUiSystemSnapshot {
    [CmdletBinding()]
    param()

    $snapshot = [ordered]@{
        CollectedAt = Get-Date
        OSName = 'Windows'
        OSVersion = $null
        Build = $null
        Architecture = $env:PROCESSOR_ARCHITECTURE
        CPUName = 'Nao identificado'
        CPUCores = $null
        CPUThreads = $null
        GPUName = 'Nao identificado'
        GPUDriver = $null
        RamGB = $null
        StorageType = 'Desconhecido'
        StorageBus = 'Desconhecido'
        StorageModel = 'Nao identificado'
        StorageSizeGB = $null
        DeviceType = 'Desktop/PC'
        IsAdmin = $false
        SecureBoot = 'Indisponivel'
        TPM = 'Indisponivel'
        VBS = 'Indisponivel'
        HVCI = 'Indisponivel'
        BitLocker = 'Indisponivel'
        PendingReboot = $false
        Network = 'Nenhum adaptador fisico ativo'
        PowerPlan = 'Indisponivel'
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        if ($os.Caption) { $snapshot.OSName = ([string]$os.Caption -replace '^Microsoft\s+', '').Trim() }
        if ($os.Version) { $snapshot.OSVersion = [string]$os.Version }
        if ($os.BuildNumber) { $snapshot.Build = [string]$os.BuildNumber }
        if ($os.OSArchitecture) { $snapshot.Architecture = [string]$os.OSArchitecture }
    } catch { }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        if ($cpu.Name) { $snapshot.CPUName = ([string]$cpu.Name -replace '\s+', ' ').Trim() }
        if ($cpu.NumberOfCores) { $snapshot.CPUCores = [int]$cpu.NumberOfCores }
        if ($cpu.NumberOfLogicalProcessors) { $snapshot.CPUThreads = [int]$cpu.NumberOfLogicalProcessors }
    } catch { }

    try {
        $gpu = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -and $_.Name -notmatch '(?i)Microsoft Basic|Remote Display|Citrix|Virtual Display' } |
            Sort-Object -Property AdapterRAM -Descending | Select-Object -First 1
        if ($null -ne $gpu) {
            $snapshot.GPUName = ([string]$gpu.Name -replace '\s+', ' ').Trim()
            if ($gpu.DriverVersion) { $snapshot.GPUDriver = [string]$gpu.DriverVersion }
        }
    } catch { }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop | Select-Object -First 1
        if ($cs.TotalPhysicalMemory) { $snapshot.RamGB = [int][Math]::Round([double]$cs.TotalPhysicalMemory / 1GB) }
    } catch { }

    $storage = Get-WinSlimStorageDescriptor
    $snapshot.StorageType = $storage.Type
    $snapshot.StorageBus = $storage.Bus
    $snapshot.StorageModel = $storage.Model
    $snapshot.StorageSizeGB = $storage.SizeGB
    $snapshot.DeviceType = Get-WinSlimDeviceType

    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $snapshot.IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }

    try {
        $sb = Confirm-SecureBootUEFI -ErrorAction Stop
        $snapshot.SecureBoot = if ([bool]$sb) { 'Ativo' } else { 'Desativado' }
    } catch {
        if ($_.Exception.Message -match '(?i)not supported|nao.*suport') { $snapshot.SecureBoot = 'Nao suportado' }
        else { $snapshot.SecureBoot = 'Indisponivel' }
    }

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if (-not $tpm.TpmPresent) { $snapshot.TPM = 'Ausente' }
        elseif ($tpm.TpmReady) { $snapshot.TPM = 'Presente / pronto' }
        else { $snapshot.TPM = 'Presente / nao pronto' }
    } catch { }

    try {
        $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $dg) {
            $snapshot.VBS = if ([int]$dg.VirtualizationBasedSecurityStatus -eq 2) { 'Ativo' } else { 'Desativado' }
            $snapshot.HVCI = if (@($dg.SecurityServicesRunning) -contains 2) { 'Ativo' } else { 'Desativado' }
        }
    } catch { }

    try {
        $osDrive = $env:SystemDrive
        $bl = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $bl) {
            $snapshot.BitLocker = if ($bl.ProtectionStatus.ToString() -match '(?i)On|1') { 'Protegido' } else { 'Desativado' }
        }
    } catch { }

    try {
        $pending = $false
        foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )) {
            if (Test-Path -LiteralPath $key) { $pending = $true; break }
        }
        if (-not $pending) {
            $pfro = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
            if ($null -ne $pfro -and $pfro.PendingFileRenameOperations) { $pending = $true }
        }
        $snapshot.PendingReboot = [bool]$pending
    } catch { }

    try {
        $adapters = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name)
        if ($adapters.Count -gt 0) { $snapshot.Network = ($adapters -join ', ') }
    } catch { }

    try {
        $pp = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -Name ActivePowerScheme -ErrorAction Stop
        if ($pp.ActivePowerScheme) { $snapshot.PowerPlan = [string]$pp.ActivePowerScheme }
    } catch { }

    return [pscustomobject]$snapshot
}

function Get-WinSlimUiPerformanceSnapshot {
    [CmdletBinding()]
    param()

    $perf = [ordered]@{
        CPU = $null
        GPU = $null
        RAM = $null
        Disk = $null
    }

    try {
        $p = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        $perf.CPU = ConvertTo-WinSlimPercent $p.PercentProcessorTime
    } catch { }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -First 1
        if ($os.TotalVisibleMemorySize -and $os.FreePhysicalMemory) {
            $used = 100.0 * (1.0 - ([double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize))
            $perf.RAM = ConvertTo-WinSlimPercent $used
        }
    } catch { }

    try {
        $d = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop |
            Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        $perf.Disk = ConvertTo-WinSlimPercent $d.PercentDiskTime
    } catch { }

    try {
        $engines = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -ErrorAction Stop |
            Where-Object { $null -ne $_.UtilizationPercentage })
        if ($engines.Count -gt 0) {
            $max = ($engines | Measure-Object -Property UtilizationPercentage -Maximum).Maximum
            $perf.GPU = ConvertTo-WinSlimPercent $max
        }
    } catch { }

    return [pscustomobject]$perf
}
