#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-pm-regression-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $binary=Join-Path $Root 'third_party\PresentMon\PresentMon-2.6.0-x64.exe'
 if(-not (Test-Path -LiteralPath $binary) -or (Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash.ToLowerInvariant() -cne 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af'){throw 'Coletor oficial ausente ou adulterado.'}
 foreach($name in @('LICENSE.txt','THIRD_PARTY.txt','README-ConsoleApplication.md','provenance.json')){if(-not (Test-Path -LiteralPath (Join-Path $Root ('third_party\PresentMon\'+$name)))){throw ('Documento ausente: '+$name)}}
 $csc=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 if(-not (Test-Path -LiteralPath $csc)){$csc=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
 $exe=Join-Path $temp 'PresentMonHarness.exe'
 $framework=Split-Path -Parent $csc
 & $csc /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014 ('/reference:'+(Join-Path $framework 'System.dll')) ('/reference:'+(Join-Path $framework 'System.Core.dll')) ('/out:'+$exe) (Join-Path $Root 'src\UI\Native\R3_2_83\PresentMonBenchmark.cs') (Join-Path $Root 'tests\PresentMonHarness.cs')
 if($LASTEXITCODE -ne 0){throw 'Compilacao do harness PresentMon falhou.'}
 & $exe
 if($LASTEXITCODE -ne 0){throw 'Regressao PresentMon falhou.'}
 Write-Host '[OK] PresentMon: parser, estatisticas, isolamento, hash, processo simulado, falha, cancelamento e comparacao.'
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
