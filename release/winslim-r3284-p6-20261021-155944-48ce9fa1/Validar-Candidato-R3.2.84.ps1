#requires -Version 5.1
[CmdletBinding()]
param([AllowNull()][AllowEmptyString()][string]$Root,[switch]$NoLaunch,[switch]$CollectOnly)
$ErrorActionPreference='Stop'
$code=1;$run=$null
try {
 $scriptDirectory=Split-Path -Parent $PSCommandPath
 . (Join-Path $scriptDirectory 'tests\regression\RegressionPaths.ps1')
 $Root=Resolve-WinSlimRegressionRoot -InputRoot $Root -ScriptDirectory $scriptDirectory
 . (Join-Path $Root 'tools\ReleasePipeline.ps1')
 if($env:OS -ne 'Windows_NT'){throw 'Requer Windows PowerShell 5.1. Nenhuma validacao nativa foi aprovada.'}
 if($CollectOnly){
  $run=Get-ChildItem -LiteralPath (Join-Path $Root 'logs') -Directory -Filter 'candidato-r3284-*' | Where-Object {Test-Path -LiteralPath (Join-Path $_.FullName 'summary.json')} | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
  if(-not $run){throw 'Nenhuma validacao desta versao encontrada. Execute Iniciar-Validacao.bat primeiro.'}
  $zip=Export-WinSlimDiagnostic -Root $Root -RunDirectory $run -IncludeBackups
  Write-Host ('Envie somente este arquivo: '+$zip)
  exit 0
 }
 $run=Join-Path $Root ('logs\candidato-r3284-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 [void][IO.Directory]::CreateDirectory($run)
 $reportPath=Join-Path $run 'regressions.json'
 $summary=[ordered]@{Revision='R3.2.84';Patch=6;Utc=[DateTime]::UtcNow.ToString('o');TechnicalPassed=$false;ProductionApproved=$false;Error=$null;ManualValidation='Pending'}
 $targetExe=Join-Path $Root 'bin\WinSlim.UI.Native.R3.2.84.exe'
 foreach($running in @(Get-Process -Name 'WinSlim.UI.Native.R3.2.84' -ErrorAction SilentlyContinue)){
  try {if($running.Path -and [IO.Path]::GetFullPath($running.Path) -ieq [IO.Path]::GetFullPath($targetExe)){throw 'Feche o Win-Slim desta pasta e execute Iniciar-Validacao.bat novamente.'}} finally {$running.Dispose()}
 }
 $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 Write-Host 'Validacao completa: testes, compilacao e WPF. Nenhum ajuste de producao sera aplicado.'
 & $shell -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'Executar-Regressoes.ps1') -Root $Root -ResultPath $reportPath
 $gateExit=$LASTEXITCODE
 if(-not (Test-Path -LiteralPath $reportPath)){throw 'O gate nao gerou relatorio desta execucao.'}
 $report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
 $manifest=Get-Content -LiteralPath (Join-Path $Root 'tests\regression\cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert-WinSlimCompleteRegression -Report $report -Cases @($manifest.cases) -ProcessExit $gateExit
 $summary.TechnicalPassed=$true
 $code=0
} catch {
 if($null -ne (Get-Variable summary -ErrorAction SilentlyContinue)){$summary.Error=$_.Exception.Message}
 Write-Host ('[FALHA] '+$_.Exception.Message) -ForegroundColor Red
 Write-Host ('Origem: '+$_.InvocationInfo.PositionMessage)
 Write-Host $_.ScriptStackTrace
 $code=1
} finally {
 if($run -and -not $CollectOnly){
  try {
   $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding UTF8
   $zip=Export-WinSlimDiagnostic -Root $Root -RunDirectory $run
   Write-Host ('Diagnostico pronto: '+$zip)
  }catch{Write-Host ('Falha ao reunir diagnostico: '+$_.Exception.Message);$code=1}
 }
}
if($code -eq 0){
 Write-Host 'GATE TECNICO APROVADO. Validacao real do lote e restauracao permanecem pendentes.' -ForegroundColor Green
 if(-not $NoLaunch){
  try {
   $exe=Join-Path $Root 'bin\WinSlim.UI.Native.R3.2.84.exe'
   if(-not (Test-Path -LiteralPath $exe)){throw 'Executavel validado nao encontrado.'}
   Start-Process -FilePath $exe -ArgumentList @('--root',('"'+$Root+'"')) -WorkingDirectory $Root | Out-Null
  }catch{Write-Host ('Falha ao abrir aplicativo: '+$_.Exception.Message);$code=1}
 }
}
exit $code
