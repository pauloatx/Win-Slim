param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src\UI\Fase7\SystemContextView.R2.ps1')
. (Join-Path $Root 'src\UI\Native\R3_2_70\WinSlimPerformance.ps1')
$script:calls=New-Object System.Collections.ArrayList
$script:mode='normal'
function Get-CimInstance {
 [CmdletBinding()]
 param([string]$ClassName,[string]$Filter,[string[]]$Property)
 [void]$script:calls.Add([pscustomobject]@{Class=$ClassName;Filter=$Filter;Properties=$Property})
 if($script:mode -eq 'failure'){throw 'fixture unavailable'}
 switch($ClassName){
  'Win32_PerfFormattedData_PerfOS_Processor' {[pscustomobject]@{PercentProcessorTime=12}}
  'Win32_OperatingSystem' {[pscustomobject]@{TotalVisibleMemorySize=1000;FreePhysicalMemory=$(if($script:mode -eq 'full'){0}else{700})}}
  'Win32_PerfFormattedData_PerfDisk_PhysicalDisk' {[pscustomobject]@{PercentDiskTime=4}}
  'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' {if($script:mode -ne 'no-gpu'){@([pscustomobject]@{UtilizationPercentage=8},[pscustomobject]@{UtilizationPercentage=23})}}
 }
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$p=Get-WinSlimUiPerformanceSnapshot
Require ($p.CPU -eq 12 -and [math]::Abs($p.RAM-30) -lt 0.001 -and $p.Disk -eq 4 -and $p.GPU -eq 23) 'Valores/formulas alterados'
Require ($script:calls.Count -eq 4) 'Numero de consultas alterado'
foreach($c in $script:calls){Require ($c.Properties.Count -gt 0) 'Consulta precisa limitar propriedades'}
Require ($script:calls[0].Filter -eq "Name='_Total'" -and $script:calls[2].Filter -eq "Name='_Total'") 'CPU/Disco precisam filtrar no provedor'
$script:mode='full';$p=Get-WinSlimUiPerformanceSnapshot;Require ($p.RAM -eq 100) 'RAM livre zero deve mostrar 100%'
$script:mode='no-gpu';$p=Get-WinSlimUiPerformanceSnapshot;Require ($null -eq $p.GPU -and $p.CPU -eq 12) 'GPU ausente deve permanecer indisponivel sem afetar CPU'
$script:mode='failure';$p=Get-WinSlimUiPerformanceSnapshot;Require ($null -eq $p.CPU -and $null -eq $p.GPU -and $null -eq $p.RAM -and $null -eq $p.Disk) 'Falhas nao podem virar valores ficticios'
Write-Host 'Performance collector: formulas, filtros, propriedades e falhas isoladas OK'
