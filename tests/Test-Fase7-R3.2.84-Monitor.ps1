#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family MonitorHarness
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\TestArtifactProvenance.ps1')
$completed=$false
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-monitor-harness-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
 if(-not (Test-Path -LiteralPath (Join-Path $framework 'csc.exe'))){$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319'}
 $sources=@('PresentMonBenchmark.cs','BenchmarkLive.cs','PresentMonMonitor.cs') | ForEach-Object {Join-Path $Root ('src\UI\Native\R3_2_84\'+$_)}
 $exe=Join-Path $temp 'MonitorHarness.exe'
 & (Join-Path $framework 'csc.exe') /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014 ('/reference:'+(Join-Path $framework 'System.dll')) ('/reference:'+(Join-Path $framework 'System.Core.dll')) ('/out:'+$exe) @sources (Join-Path $Root 'tests\MonitorHarness.cs')
 $compilerExit=$LASTEXITCODE
 $record=Write-WinSlimTestArtifactRecord -Root $Root -Artifact $exe -Compiler (Join-Path $framework 'csc.exe') -Sources @($sources+(Join-Path $Root 'tests\MonitorHarness.cs')) -CompilerExit $compilerExit
 Write-Host ('Test artifact provenance: '+$record.Path)
 if($compilerExit -ne 0 -or -not $record.ArtifactReadable -or -not $record.InputsReadable){throw 'Monitor harness compile/read failed. Evidence retained; do not rename/retry.'}
 & $exe
 if($LASTEXITCODE -ne 0){throw 'Monitor behavioral regression failed.'}
 & (Join-Path $PSScriptRoot 'Test-Fase7-R3.2.84-OverlaySensors.ps1') -Root $Root
 $completed=$true
} finally {
 if(-not $completed){if($record){try{Write-WinSlimTestArtifactRecord -Root $Root -Artifact $exe -Compiler (Join-Path $framework 'csc.exe') -Sources @($sources+(Join-Path $Root 'tests\MonitorHarness.cs')) -CompilerExit $compilerExit -Stage ExecutionFailed | Out-Null}catch{Write-Host 'Failed to append failure stage; earlier records retained.'}};Write-Host ('Failure: test directory retained for investigation: '+$temp)}
 else{$full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\');if($full.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -match '\Awinslim-monitor-harness-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}}
}
