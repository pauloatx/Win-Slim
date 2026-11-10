# Win-Slim R3.2.72: focused read-only performance queries; same metric definitions.
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
