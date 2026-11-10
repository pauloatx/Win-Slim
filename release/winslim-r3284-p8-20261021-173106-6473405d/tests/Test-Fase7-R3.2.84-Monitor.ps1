#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-monitor-harness-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
 if(-not (Test-Path -LiteralPath (Join-Path $framework 'csc.exe'))){$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319'}
 $sources=@('PresentMonBenchmark.cs','BenchmarkLive.cs','PresentMonMonitor.cs') | ForEach-Object {Join-Path $Root ('src\UI\Native\R3_2_84\'+$_)}
 $exe=Join-Path $temp 'MonitorHarness.exe'
 & (Join-Path $framework 'csc.exe') /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014 ('/reference:'+(Join-Path $framework 'System.dll')) ('/reference:'+(Join-Path $framework 'System.Core.dll')) ('/out:'+$exe) @sources (Join-Path $Root 'tests\MonitorHarness.cs')
 if($LASTEXITCODE -ne 0){throw 'Monitor harness compilation failed.'}
 & $exe
 if($LASTEXITCODE -ne 0){throw 'Monitor behavioral regression failed.'}
 & (Join-Path $PSScriptRoot 'Test-Fase7-R3.2.84-OverlaySensors.ps1') -Root $Root
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
