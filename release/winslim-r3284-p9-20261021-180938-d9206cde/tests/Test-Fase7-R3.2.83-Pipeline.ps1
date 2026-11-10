#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tests\regression\RegressionProcess.ps1')
. (Join-Path $Root 'tests\regression\NativeDelegation.ps1')
. (Join-Path $Root 'tools\ReleasePipeline.ps1')
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};Write-Host ('[OK] '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action}catch{$failed=$true};Check $failed $Message}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-pipeline-'+[guid]::NewGuid().ToString('N'))
$shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Run-Fixture([string]$Script,[string]$Fixture,[string]$Extra=''){
 $tag=[guid]::NewGuid().ToString('N')
 $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$Script+'" -Root "'+$Fixture+'" '+$Extra
 $result=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments $arguments -WorkingDirectory $temp -Stdout (Join-Path $temp ($tag+'.out')) -Stderr (Join-Path $temp ($tag+'.err')) -TimeoutSeconds 90
 if($result.ExitCode -ne 0){Write-Host (Get-Content -LiteralPath (Join-Path $temp ($tag+'.out')) -Raw)}
 return [int]$result.ExitCode
}
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $cases=@([pscustomobject]@{id='REG-FIXTURE-001'})
 $good=[pscustomobject]@{Passed=$true;ExitCode=0;Results=@([pscustomobject]@{Id='REG-FIXTURE-001';Status='Passed';ExitCode=0})}
 Assert-WinSlimCompleteRegression -Report $good -Cases $cases -ProcessExit 0
 Reject {Assert-WinSlimCompleteRegression -Report $good -Cases $cases -ProcessExit 7} 'exit code real prevalece sobre Passed'
 foreach($rows in @(@{Rows=@()},@{Rows=@($good.Results[0],$good.Results[0])},@{Rows=@([pscustomobject]@{Id='REG-OTHER-001';Status='Passed';ExitCode=0})},@{Rows=@([pscustomobject]@{Id='REG-FIXTURE-001';Status='Failed';ExitCode=0})},@{Rows=@([pscustomobject]@{Id='REG-FIXTURE-001';Status='Passed';ExitCode=$null})})){
  $bad=[pscustomobject]@{Passed=$true;ExitCode=0;Results=$rows.Rows}
  Reject {Assert-WinSlimCompleteRegression -Report $bad -Cases $cases -ProcessExit 0} 'relatorio vazio/duplicado/desconhecido/falho/sem codigo rejeitado'
 }
 # Actual harness and native-delegation helper with disposable child scripts.
 $fixture=Join-Path $temp 'Delegacao com espaços'
 [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tests\regression'))
 foreach($name in @('Executar-Regressoes.ps1','tests/regression/RegressionPaths.ps1','tests/regression/RegressionProcess.ps1','tests/regression/NativeDelegation.ps1')){
  Copy-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $fixture $name)
 }
 $registry=New-Object Collections.ArrayList
 $native=[pscustomobject]@{id='REG-UI-001';bugs=@('fixture');scenario='fixture';script='tests/Test-Fase7-R3.2.83-NativeUI.ps1';timeoutSeconds=30;integratedNative=$true}
 [void]$registry.Add($native)
 foreach($entry in (Get-WinSlimNativeDelegation)){
  [void]$registry.Add([pscustomobject]@{id=$entry.Id;bugs=@('fixture');scenario='fixture';script=$entry.Script;timeoutSeconds=30})
  $child='param([string]$Root); Add-Content -LiteralPath (Join-Path $Root "calls.txt") -Value "'+$entry.Id+'"; exit 0'
  [IO.File]::WriteAllText((Join-Path $fixture $entry.Script),$child)
 }
 $nativeText=@'
param([string]$Root,[switch]$IntegratedMode)
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tests/regression/NativeDelegation.ps1')
foreach($entry in (Get-WinSlimNativeDelegation)){
 Invoke-WinSlimNativePrerequisite -Root $Root -Script $entry.Script -IntegratedMode:$IntegratedMode -AssertResult {param($ok,$message)if(-not $ok){throw $message}} -Message $entry.Id
}
exit 0
'@
 [IO.File]::WriteAllText((Join-Path $fixture $native.script),$nativeText)
 $manifestPath=Join-Path $fixture 'tests\regression\cases.json'
 [pscustomobject]@{schemaVersion=1;cases=@($registry.ToArray())} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
 $code=Run-Fixture (Join-Path $fixture 'Executar-Regressoes.ps1') $fixture
 Check ($code -eq 0) 'harness integrado real passou'
 $calls=@(Get-Content -LiteralPath (Join-Path $fixture 'calls.txt'))
 Check ($calls.Count -eq 10 -and @($calls | Select-Object -Unique).Count -eq 10) 'dez suites executadas exatamente uma vez no modo integrado'
 Remove-Item -LiteralPath (Join-Path $fixture 'calls.txt')
 $code=Run-Fixture (Join-Path $fixture $native.script) $fixture
 Check ($code -eq 0 -and @(Get-Content -LiteralPath (Join-Path $fixture 'calls.txt')).Count -eq 10) 'modo isolado preserva todas as dez suites'
 Remove-Item -LiteralPath (Join-Path $fixture 'calls.txt')
 $invalid=@($registry.ToArray() | Where-Object {$_.id -ne 'REG-PERF-001'})
 [pscustomobject]@{schemaVersion=1;cases=$invalid} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
 $code=Run-Fixture (Join-Path $fixture 'Executar-Regressoes.ps1') $fixture
 Check ($code -eq 1 -and -not (Test-Path -LiteralPath (Join-Path $fixture 'calls.txt'))) 'delegacao incompleta bloqueia antes de executar filhos'
 # Actual candidate script, with a synthetic regression harness: never invokes production settings.
 $candidate=Join-Path $temp 'Candidato com acentuação'
 [void][IO.Directory]::CreateDirectory((Join-Path $candidate 'tools'))
 [void][IO.Directory]::CreateDirectory((Join-Path $candidate 'tests\regression'))
 Copy-Item -LiteralPath (Join-Path $Root 'tools\ReleasePipeline.ps1') -Destination (Join-Path $candidate 'tools')
 Copy-Item -LiteralPath (Join-Path $Root 'Validar-Candidato-R3.2.83.ps1') -Destination $candidate
 Copy-Item -LiteralPath (Join-Path $Root 'tests\regression\RegressionPaths.ps1') -Destination (Join-Path $candidate 'tests\regression')
 foreach($launcher in @('Iniciar-Validacao.bat','Coletar-Diagnostico.bat')){Copy-Item -LiteralPath (Join-Path $Root $launcher) -Destination $candidate}
 [pscustomobject]@{schemaVersion=1;cases=$cases} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $candidate 'tests\regression\cases.json') -Encoding UTF8
 foreach($mode in @('valid','empty','failure','missing')){
  $body='param([string]$Root,[string]$ResultPath); '
  if($mode -eq 'missing'){$body+='exit 0'}else{
   $report=if($mode -eq 'empty'){[pscustomobject]@{Passed=$true;ExitCode=0;Results=@()}}else{$good}
   $json=$report | ConvertTo-Json -Depth 8 -Compress
   $body+="[IO.File]::WriteAllText(`$ResultPath,'"+$json.Replace("'","''")+"'); exit "+$(if($mode -eq 'failure'){'7'}else{'0'})
  }
  [IO.File]::WriteAllText((Join-Path $candidate 'Executar-Regressoes.ps1'),$body)
  $code=Run-Fixture (Join-Path $candidate 'Validar-Candidato-R3.2.83.ps1') $candidate '-NoLaunch'
  $expected=if($mode -eq 'valid'){0}else{1}
  Check ($code -eq $expected) ('pipeline real: '+$mode+' retorna '+$expected)
  $last=Get-ChildItem -LiteralPath (Join-Path $candidate 'logs') -Directory -Filter 'candidato-*' | Sort-Object Name -Descending | Select-Object -First 1
  $summary=Get-Content -LiteralPath (Join-Path $last.FullName 'summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  Check ($summary.TechnicalPassed -eq ($mode -eq 'valid') -and $summary.ProductionApproved -eq $false) 'resumo distingue gate tecnico e producao; nunca reutiliza relatorio antigo'
  Check (Test-Path -LiteralPath (Join-Path $candidate 'WinSlim-Diagnostico-R3.2.83.zip')) 'ZIP de diagnostico automatico tambem em falha'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead((Join-Path $candidate 'WinSlim-Diagnostico-R3.2.83.zip'))
  try {
   $entry=$archive.GetEntry('validacao/summary.json')
   if($null -eq $entry){$entry=$archive.GetEntry('validacao\summary.json')}
   Check ($null -ne $entry) 'ZIP contem resumo desta validacao'
   $reader=New-Object IO.StreamReader($entry.Open())
   try{$savedSummary=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}
   Check ($savedSummary.Utc -ceq $summary.Utc -and $savedSummary.TechnicalPassed -eq $summary.TechnicalPassed -and $savedSummary.Error -ceq $summary.Error) 'ZIP existente substituido: conteudo novo, inclusive em falha'
  }finally{$archive.Dispose()}
 }
 # Regression for the exact omitted-root startup that was not covered by explicit-Root fixtures.
 $json=$good | ConvertTo-Json -Depth 8 -Compress
 $body='param([string]$Root,[string]$ResultPath); '+"[IO.File]::WriteAllText(`$ResultPath,'"+$json.Replace("'","''")+"'); exit 0"
 [IO.File]::WriteAllText((Join-Path $candidate 'Executar-Regressoes.ps1'),$body)
 foreach($rootMode in @('omitted','empty','whitespace')){
  $argsText='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $candidate 'Validar-Candidato-R3.2.83.ps1')+'" -NoLaunch'
  if($rootMode -ne 'omitted'){
   $wrapper=Join-Path $candidate ('invoke-'+$rootMode+'.ps1')
   $literal=if($rootMode -eq 'empty'){"''"}else{"'   '"}
   $wrapperText="& (Join-Path `$PSScriptRoot 'Validar-Candidato-R3.2.83.ps1') -NoLaunch -Root "+$literal+"`r`nexit `$LASTEXITCODE"
   [IO.File]::WriteAllText($wrapper,$wrapperText,(New-Object Text.UTF8Encoding($true)))
   $argsText='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$wrapper+'"'
  }
  $execution=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments $argsText -WorkingDirectory $temp -Stdout (Join-Path $temp ($rootMode+'.out')) -Stderr (Join-Path $temp ($rootMode+'.err')) -TimeoutSeconds 30
  Check ($execution.ExitCode -eq 0) ('pasta resolvida apos parametros: '+$rootMode+' a partir de outro cwd')
 }
 # Exercise the real .bat entry points, including spaces/accents and the trailing-slash quote boundary.
 foreach($launcher in @('Iniciar-Validacao.bat','Coletar-Diagnostico.bat')){
  $argsText='/d /s /c ""'+(Join-Path $candidate $launcher)+'" /ci"'
  $execution=Invoke-WinSlimRegressionProcess -Executable (Join-Path $env:SystemRoot 'System32\cmd.exe') -Arguments $argsText -WorkingDirectory $temp -Stdout (Join-Path $temp ($launcher+'.out')) -Stderr (Join-Path $temp ($launcher+'.err')) -TimeoutSeconds 45
  Check ($execution.ExitCode -eq 0) ('launcher real passou: '+$launcher)
 }
 $last=Get-ChildItem -LiteralPath (Join-Path $candidate 'logs') -Directory -Filter 'candidato-*' | Sort-Object Name -Descending | Select-Object -First 1
 $backupDir=Join-Path $candidate 'Backups\UI\fixture';[void][IO.Directory]::CreateDirectory($backupDir)
 [IO.File]::WriteAllText((Join-Path $backupDir 'snapshot.json'),'fixture-backup')
 $before=(Get-FileHash -LiteralPath (Join-Path $last.FullName 'summary.json')).Hash
 $code=Run-Fixture (Join-Path $candidate 'Validar-Candidato-R3.2.83.ps1') $candidate '-CollectOnly'
 Check ($code -eq 0 -and (Get-FileHash -LiteralPath (Join-Path $last.FullName 'summary.json')).Hash -eq $before) 'coleta posterior preserva resultado e nao repete testes'
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $candidate 'WinSlim-Diagnostico-R3.2.83.zip'))
 try{Check (@($zip.Entries | Where-Object {$_.FullName.Replace('\','/') -eq 'Backups-UI/fixture/snapshot.json'}).Count -eq 1) 'coleta posterior inclui backup para verificar Apply/Undo'}finally{$zip.Dispose()}
 $destination=Join-Path $candidate 'WinSlim-Diagnostico-R3.2.83.zip'
 $beforeHash=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
 $locked=[IO.File]::Open($destination,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{Reject {Export-WinSlimDiagnostic -Root $candidate -RunDirectory $last.FullName | Out-Null} 'arquivo em uso rejeita publicacao sem apagar ZIP anterior'}finally{$locked.Dispose()}
 Check ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ceq $beforeHash) 'ZIP anterior preservado byte a byte quando substituicao falha'
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
