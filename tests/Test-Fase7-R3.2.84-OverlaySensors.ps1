param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src/UI/Native/R3_2_84/WinSlimPerformance.ps1')
function ConvertTo-WinSlimPercent($value){if($null -eq $value){return $null};return [double]$value}
$script:mode='normal'
function Get-CimInstance {
 [CmdletBinding()]param([string]$ClassName,[string]$Namespace,[string]$Filter,[string[]]$Property,[int]$OperationTimeoutSec)
 if($script:mode -eq 'missing'){throw 'Provider missing'}
 switch($ClassName){
  'Win32_PerfFormattedData_PerfOS_Processor' {[pscustomobject]@{PercentProcessorTime=15}}
  'Win32_OperatingSystem' {[pscustomobject]@{TotalVisibleMemorySize=1000;FreePhysicalMemory=500}}
  'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' {[pscustomobject]@{UtilizationPercentage=75}}
  'Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory' {@([pscustomobject]@{Name='luid_1';DedicatedUsage=2GB},[pscustomobject]@{Name='luid_2';DedicatedUsage=1GB},[pscustomobject]@{Name='pid_4';DedicatedUsage=8GB})}
  'Hardware' {@([pscustomobject]@{Identifier='/cpu/0';HardwareType='Cpu'},[pscustomobject]@{Identifier='/gpu/0';HardwareType='GpuNvidia'})}
  'Sensor' {@([pscustomobject]@{Parent='/cpu/0';SensorType='Temperature';Name='CPU Package';Value=$(if($script:mode -eq 'invalid'){[double]::NaN}else{65})},[pscustomobject]@{Parent='/gpu/0';SensorType='Temperature';Name='GPU Core';Value=72},[pscustomobject]@{Parent='/gpu/0';SensorType='Temperature';Name='GPU Memory';Value=95},[pscustomobject]@{Parent='/cpu/0';SensorType='Temperature';Name='Distance to TjMax';Value=100})}
 }
}
$result=Get-WinSlimOverlaySensors
if($result.CPU -ne 15 -or $result.GPU -ne 75 -or $result.RAM -ne 50 -or $result.VramMiB -ne 2048 -or $result.CpuTemperature -ne 65 -or $result.GpuTemperature -ne 72){throw 'Optional sensor values or device association incorrect.'}
$script:mode='invalid';$result=Get-WinSlimOverlaySensors
if($null -ne $result.CpuTemperature -or $result.GpuTemperature -ne 72){throw 'Invalid CPU temperature must not become zero or affect GPU.'}
$script:mode='missing';$result=Get-WinSlimOverlaySensors
foreach($name in @('CPU','GPU','RAM','CpuTemperature','GpuTemperature','VramMiB')){if($null -ne $result.$name){throw ('Unavailable reading must be null: '+$name)}}
Write-Host '[OK] Optional sensors: values, parent/type association, invalid/missing provider, no fake zeros.'
