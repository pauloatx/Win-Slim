#requires -Version 5.1
[CmdletBinding()]
param([AllowNull()][AllowEmptyString()][string]$Root,[string]$ResultPath)
$ErrorActionPreference='Stop'
$results=New-Object System.Collections.ArrayList
$reportDir=$null
$exitCode=1
try {
 $scriptDirectory=Split-Path -Parent $PSCommandPath
 # Resolve after parameter binding; do not pass an implicit/empty root to GetFullPath.
 . (Join-Path $scriptDirectory 'tests\regression\RegressionPaths.ps1')
 . (Join-Path $scriptDirectory 'tests\regression\RegressionProcess.ps1')
 $Root=Resolve-WinSlimRegressionRoot -InputRoot $Root -ScriptDirectory $scriptDirectory
 $reportDir=Join-Path $Root ('logs\regressao-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 [void][IO.Directory]::CreateDirectory($reportDir)
 if($env:OS -ne 'Windows_NT'){throw 'A suite nativa requer Windows e Windows PowerShell 5.1. Nenhum teste foi aprovado.'}
 . (Join-Path $scriptDirectory 'tools\TestExecutionPolicy.ps1')
 Assert-WinSlimTestExecutionAllowed -Family FullRegressionGate
 $controlledLocalValidation=Test-WinSlimControlledLocalValidation
 $manifest=Get-Content -LiteralPath (Join-Path $Root 'tests\regression\cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($manifest.schemaVersion -ne 1 -or @($manifest.cases).Count -eq 0){throw 'Cadastro de regressoes ausente ou invalido.'}
 $ids=@{}
 # Validate the entire registry before starting any test.
 foreach($case in $manifest.cases){
  $id=[string]$case.id
  if($id -notmatch '\AREG-[A-Z]+-[0-9]{3}\z' -or $ids.ContainsKey($id)){throw ('ID ausente, invalido ou duplicado: '+$id)}
  $ids[$id]=$true
  if(@($case.bugs).Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$case.scenario)){throw ('Cenario ou bug ausente: '+$id)}
  $path=[IO.Path]::GetFullPath((Join-Path $Root ([string]$case.script)))
  if(-not $path.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.ps1'){throw ('Script invalido: '+$id)}
  $timeout=[int]$case.timeoutSeconds
  if($timeout -lt 1 -or $timeout -gt 1800){throw ('Timeout invalido: '+$id)}
 }
 foreach($case in $manifest.cases){
  if($case.integratedNative -eq $true){
   . (Join-Path $Root 'tests\regression\NativeDelegation.ps1')
   Assert-WinSlimNativeDelegation -Cases @($manifest.cases) -NativeCase $case
  }
 }
 $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 foreach($case in $manifest.cases){
  $id=[string]$case.id
  $out=Join-Path $reportDir ($id+'.stdout.log');$err=Join-Path $reportDir ($id+'.stderr.log')
  $timer=[Diagnostics.Stopwatch]::StartNew();$status='Failed';$code=$null;$reason=$null;$process=$null
  Write-Host ('[EXECUTANDO] '+$id+' - '+$case.scenario)
  try {
   $path=[IO.Path]::GetFullPath((Join-Path $Root ([string]$case.script)))
   if($Root -match '["\r\n]' -or $path -match '["\r\n]'){throw 'Caminho nao suportado.'}
   $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$path+'" -Root "'+$Root.TrimEnd('\')+'"'
   if($case.integratedNative -eq $true){$arguments+=' -IntegratedMode'}
   $execution=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments $arguments -WorkingDirectory $Root -Stdout $out -Stderr $err -TimeoutSeconds ([int]$case.timeoutSeconds)
   $code=$execution.ExitCode
   if($code -eq 0){$status='Passed'}else{$reason='Script retornou codigo '+$code}
  } catch {$reason=$_.Exception.Message}
  finally {if($null -ne $process){$process.Dispose()};$timer.Stop()}
  [void]$results.Add([pscustomobject]@{Id=$id;Bugs=@($case.bugs);Scenario=[string]$case.scenario;Status=$status;ExitCode=$code;DurationMs=$timer.ElapsedMilliseconds;Error=$reason;Stdout=$out;Stderr=$err})
  Write-Host ('['+$status+'] '+$id+' - '+$timer.ElapsedMilliseconds+' ms')
  if($controlledLocalValidation -and $status -ne 'Passed'){
   Write-Host 'Validacao local controlada interrompida na primeira falha; execucoes restantes nao foram aprovadas.'
   break
  }
 }
 $exitCode=if(@($results | Where-Object {$_.Status -ne 'Passed'}).Count -eq 0){0}else{1}
} catch {
 [void]$results.Add([pscustomobject]@{Id='HARNESS';Status='Failed';Error=$_.Exception.Message})
 Write-Host ('[FALHA] '+$_.Exception.Message)
 Write-Host ('Origem: '+$_.InvocationInfo.PositionMessage)
 $exitCode=1
} finally {
 if($null -ne $reportDir){
  $report=[pscustomobject]@{SchemaVersion=1;Utc=[DateTime]::UtcNow.ToString('o');Passed=($exitCode -eq 0);ExitCode=$exitCode;Results=@($results.ToArray())}
  $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $reportDir 'resultado.json') -Encoding UTF8
  if(-not [string]::IsNullOrWhiteSpace($ResultPath)){
   $resolvedResult=[IO.Path]::GetFullPath($ResultPath)
   $logsRoot=[IO.Path]::GetFullPath((Join-Path $Root 'logs')).TrimEnd('\')+'\'
   if(-not $resolvedResult.StartsWith($logsRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'ResultPath deve ficar em logs.'}
   [void][IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedResult))
   Copy-Item -LiteralPath (Join-Path $reportDir 'resultado.json') -Destination $resolvedResult -Force
  }
  Write-Host ('Relatorios: '+$reportDir)
 }
}
Write-Host ('Resultado da regressao: '+$exitCode)
exit $exitCode
