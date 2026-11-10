#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family PresentMonHarness
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\TestArtifactProvenance.ps1')
$completed=$false
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
 $sources=@('src\UI\Native\R3_2_84\PresentMonBenchmark.cs','src\UI\Native\R3_2_84\BenchmarkLive.cs','src\UI\Native\R3_2_84\PresentMonMonitor.cs','tests\PresentMonHarness.cs') | ForEach-Object {Join-Path $Root $_}
 & $csc /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014 ('/reference:'+(Join-Path $framework 'System.dll')) ('/reference:'+(Join-Path $framework 'System.Core.dll')) ('/out:'+$exe) @sources
 $compilerExit=$LASTEXITCODE
 $record=Write-WinSlimTestArtifactRecord -Root $Root -Artifact $exe -Compiler $csc -Sources $sources -CompilerExit $compilerExit
 Write-Host ('Test artifact provenance: '+$record.Path)
 if($compilerExit -ne 0 -or -not $record.ArtifactReadable -or -not $record.InputsReadable){throw 'Compilacao ou leitura do auxiliar falhou. Evidencias preservadas; nao repetir com outro nome.'}
 & $exe
 if($LASTEXITCODE -ne 0){throw 'Regressao PresentMon falhou.'}
 Write-Host '[OK] PresentMon: parser, estatisticas, isolamento, hash, processo simulado, falha, cancelamento e comparacao.'
 $completed=$true
} finally {
 if(-not $completed){if($record){try{Write-WinSlimTestArtifactRecord -Root $Root -Artifact $exe -Compiler $csc -Sources $sources -CompilerExit $compilerExit -Stage ExecutionFailed | Out-Null}catch{Write-Host 'Nao foi possivel acrescentar a etapa de falha; registros anteriores preservados.'}};Write-Host ('Falha: pasta temporaria preservada para investigacao: '+$temp)}
 else{$full=[IO.Path]::GetFullPath($temp);$parent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\');if($full.StartsWith($parent+'\',[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -match '\Awinslim-pm-regression-[0-9a-f]{32}\z' -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}}
}
