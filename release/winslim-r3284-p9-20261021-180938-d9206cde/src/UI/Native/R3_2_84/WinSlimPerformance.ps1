# Win-Slim R3.2.84: focused read-only performance queries; same metric definitions.
function Get-WinSlimUiPerformanceSnapshot {
    [CmdletBinding()]
    param([scriptblock]$OnMetric)
    $perf = [ordered]@{ CPU=$null; GPU=$null; RAM=$null; Disk=$null }
    try {
        $p = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -Property Name,PercentProcessorTime -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $p) { $perf.CPU = ConvertTo-WinSlimPercent $p.PercentProcessorTime }
    } catch { }
    if ($null -ne $OnMetric) { try { & $OnMetric 'CPU' $perf.CPU | Out-Null } catch { } }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -Property TotalVisibleMemorySize,FreePhysicalMemory -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $os -and $null -ne $os.TotalVisibleMemorySize -and [double]$os.TotalVisibleMemorySize -gt 0 -and $null -ne $os.FreePhysicalMemory) {
            $perf.RAM = ConvertTo-WinSlimPercent (100.0 * (1.0 - ([double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)))
        }
    } catch { }
    if ($null -ne $OnMetric) { try { & $OnMetric 'RAM' $perf.RAM | Out-Null } catch { } }
    try {
        $d = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -Property Name,PercentDiskTime -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $d) { $perf.Disk = ConvertTo-WinSlimPercent $d.PercentDiskTime }
    } catch { }
    if ($null -ne $OnMetric) { try { & $OnMetric 'Disk' $perf.Disk | Out-Null } catch { } }
    try {
        # Keep the existing GPU definition: maximum utilization reported across engines.
        $engines = @(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Property UtilizationPercentage -ErrorAction Stop | Where-Object { $null -ne $_.UtilizationPercentage })
        if ($engines.Count -gt 0) { $perf.GPU = ConvertTo-WinSlimPercent (($engines | Measure-Object -Property UtilizationPercentage -Maximum).Maximum) }
    } catch { }
    if ($null -ne $OnMetric) { try { & $OnMetric 'GPU' $perf.GPU | Out-Null } catch { } }
    return [pscustomobject]$perf
}

# Optional, read-only providers; never loads a DLL, starts a service or installs a driver.
function Get-WinSlimOverlaySensors {
    $usage=Get-WinSlimUiPerformanceSnapshot
    $result=[ordered]@{CPU=$usage.CPU;GPU=$usage.GPU;RAM=$usage.RAM;CpuTemperature=$null;GpuTemperature=$null;VramMiB=$null;TemperatureProvider=$null}
    try {
        $adapters=@(Get-CimInstance -ClassName Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -Property Name,DedicatedUsage -OperationTimeoutSec 1 -ErrorAction Stop | Where-Object {$_.Name -match '^luid_' -and $null -ne $_.DedicatedUsage -and [double]$_.DedicatedUsage -ge 0 -and [double]$_.DedicatedUsage -lt 1099511627776})
        if($adapters.Count -gt 0){$result.VramMiB=[Math]::Round((($adapters | Measure-Object DedicatedUsage -Maximum).Maximum / 1MB),1)}
    } catch { }
    foreach($provider in @('root\LibreHardwareMonitor','root\OpenHardwareMonitor')){
        try {
            $hardware=@(Get-CimInstance -Namespace $provider -ClassName Hardware -Property Identifier,HardwareType -OperationTimeoutSec 1 -ErrorAction Stop)
            $sensors=@(Get-CimInstance -Namespace $provider -ClassName Sensor -Filter "SensorType='Temperature'" -Property Name,Parent,Value,SensorType -OperationTimeoutSec 1 -ErrorAction Stop)
            foreach($kind in @('Cpu','Gpu')){
                $key=$kind+'Temperature'
                if($null -ne $result[$key]){continue}
                $parents=@($hardware | Where-Object {if($kind -eq 'Cpu'){$_.HardwareType -ieq 'CPU'}else{$_.HardwareType -in @('GpuNvidia','GpuAti','GpuAmd','GpuIntel')}} | ForEach-Object {$_.Identifier})
                $values=@($sensors | Where-Object {$_.Parent -in $parents -and $_.SensorType -eq 'Temperature' -and $null -ne $_.Value -and [double]$_.Value -gt 0 -and [double]$_.Value -lt 130 -and $(if($kind -eq 'Cpu'){$_.Name -match '^(CPU Package|CPU Core #\d+|Core Max|Core \(Tctl/Tdie\))$'}else{$_.Name -eq 'GPU Core'})} | ForEach-Object {[double]$_.Value})
                if($values.Count -gt 0){$result[$key]=($values | Measure-Object -Maximum).Maximum;$result.TemperatureProvider=$provider}
            }
            if($null -ne $result.CpuTemperature -and $null -ne $result.GpuTemperature){break}
        } catch { }
    }
    return [pscustomobject]$result
}
