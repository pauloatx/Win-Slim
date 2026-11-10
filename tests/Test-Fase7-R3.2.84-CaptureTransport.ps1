#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/validation/WinSlimCaptureData.ps1')
Import-WinSlimCaptureDataTypes -Root $Root -IncludeTransportFixtures
$results=@(Invoke-WinSlimCaptureMember CaptureTransportFixture RunAll $null @((Join-Path $script:CaptureBuild 'transport-data')))
$results | ForEach-Object {Write-Host $_}
if(@($results | Where-Object {$_ -like '[[]FAIL]*'}).Count -gt 0){throw 'Production transport/preview behavioral failures; no collector executable used'}
Write-Host ('Transport/preview: '+$results.Count+' checks, real in-process OS pipes; DLL without Main, no blocked source, process or ETW. '+$script:CaptureBuild)
