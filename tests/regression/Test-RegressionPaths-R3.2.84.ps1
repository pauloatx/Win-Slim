#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tests\regression\RegressionPaths.ps1')
. (Join-Path $Root 'tests\regression\RegressionProcess.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-paths-'+[guid]::NewGuid().ToString('N'))
try {
 $fixture=Join-Path $temp 'Projeto com espaços e acentuação'
 [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tests\regression'))
 $expected=(Get-Item -LiteralPath $fixture).FullName
 foreach($inputPath in @($null,'',$fixture,($fixture+'\'))){
  $actual=Resolve-WinSlimRegressionRoot -InputRoot $inputPath -ScriptDirectory $fixture
  if($actual.TrimEnd('\') -ne $expected.TrimEnd('\')){throw 'Caminho normalizado incorretamente.'}
 }
 $file=Join-Path $fixture 'arquivo.txt';[IO.File]::WriteAllText($file,'fixture')
 $rejected=$false;try {Resolve-WinSlimRegressionRoot -InputRoot $file -ScriptDirectory $fixture | Out-Null}catch{$rejected=$true}
 if(-not $rejected){throw 'Arquivo foi aceito como pasta.'}
 Write-Host '[OK] Caminhos vazios, explicitos, acentuados e com barra final; arquivo rejeitado.'
 # Run the real harness against isolated passing/failing suites, including default Root from another cwd.
 Copy-Item -LiteralPath (Join-Path $Root 'Executar-Regressoes.ps1') -Destination $fixture
 [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'tools'))
 [void][IO.Directory]::CreateDirectory((Join-Path $fixture 'release'))
 Copy-Item -LiteralPath (Join-Path $Root 'tools\TestExecutionPolicy.ps1') -Destination (Join-Path $fixture 'tools')
 # Only inert pass/fail scripts exist in this disposable fixture.
 [IO.File]::WriteAllText((Join-Path $fixture 'release\security-incidents.json'),'{"schemaVersion":1,"incidents":[]}')
 Copy-Item -LiteralPath (Join-Path $Root 'tests\regression\RegressionPaths.ps1') -Destination (Join-Path $fixture 'tests\regression')
 Copy-Item -LiteralPath (Join-Path $Root 'tests\regression\RegressionProcess.ps1') -Destination (Join-Path $fixture 'tests\regression')
 $manifest=[ordered]@{schemaVersion=1;cases=@([ordered]@{id='REG-FIXTURE-001';bugs=@('fixture');scenario='Caso isolado';script='tests/pass.ps1';timeoutSeconds=20})}
 $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixture 'tests\regression\cases.json') -Encoding UTF8
 $child=Join-Path $fixture 'tests\pass.ps1'
 $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 foreach($mode in @('default','explicit','failure')){
  $fixtureExit=if($mode -eq 'failure'){1}else{0}
  [IO.File]::WriteAllText($child,('param([string]$Root); exit '+$fixtureExit))
  $argsText='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $fixture 'Executar-Regressoes.ps1')+'"'
  if($mode -ne 'default'){$argsText+=' -Root "'+$fixture+'"'}
  $execution=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments $argsText -WorkingDirectory $temp -Stdout (Join-Path $temp ($mode+'.out')) -Stderr (Join-Path $temp ($mode+'.err')) -TimeoutSeconds 30
  if($execution.ExitCode -ne $fixtureExit){throw ('Exit code incorreto no cenario '+$mode+'. Veja '+(Get-Content -LiteralPath (Join-Path $temp ($mode+'.out')) -Raw))}
  $latest=Get-ChildItem -LiteralPath (Join-Path $fixture 'logs') -Directory | Sort-Object Name -Descending | Select-Object -First 1
  $result=Get-Content -LiteralPath (Join-Path $latest.FullName 'resultado.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  if($result.Passed -ne ($fixtureExit -eq 0) -or @($result.Results).Count -ne 1){throw 'Resumo do harness incorreto.'}
  Write-Host ('[OK] Harness real: '+$mode+'; exit code e resultado.json consistentes.')
 }
 # A duplicated suite must fail registration before any child script can run.
 $marker=Join-Path $fixture 'child-executed.txt'
 [IO.File]::WriteAllText($child,('param([string]$Root); [IO.File]::WriteAllText((Join-Path $Root "child-executed.txt"),"unexpected"); exit 0'))
 $manifest.cases=@($manifest.cases[0],$manifest.cases[0])
 $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixture 'tests\regression\cases.json') -Encoding UTF8
 $argsText='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $fixture 'Executar-Regressoes.ps1')+'" -Root "'+$fixture+'"'
 $execution=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments $argsText -WorkingDirectory $temp -Stdout (Join-Path $temp 'duplicate.out') -Stderr (Join-Path $temp 'duplicate.err') -TimeoutSeconds 30
 $latest=Get-ChildItem -LiteralPath (Join-Path $fixture 'logs') -Directory | Sort-Object Name -Descending | Select-Object -First 1
 $result=Get-Content -LiteralPath (Join-Path $latest.FullName 'resultado.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($execution.ExitCode -ne 1 -or $result.Passed -ne $false -or @($result.Results).Count -ne 1 -or $result.Results[0].Id -cne 'HARNESS' -or $result.Results[0].Error -notlike '*REG-FIXTURE-001*' -or (Test-Path -LiteralPath $marker)){throw 'Cadastro duplicado nao foi rejeitado antes de executar o filho.'}
 Write-Host '[OK] Cadastro duplicado bloqueia todos os filhos e identifica o ID em resultado.json.'
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
