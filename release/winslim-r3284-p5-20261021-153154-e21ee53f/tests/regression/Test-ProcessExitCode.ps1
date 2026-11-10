#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tests\regression\RegressionProcess.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-exitcode-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $shell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 foreach($code in @(0,1,7)){
  $file=Join-Path $temp ('exit'+$code+'.ps1');[IO.File]::WriteAllText($file,('exit '+$code))
  $r=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments ('-NoLogo -NoProfile -NonInteractive -File "'+$file+'"') -WorkingDirectory $temp -Stdout (Join-Path $temp 'stdout.log') -Stderr (Join-Path $temp 'stderr.log') -TimeoutSeconds 15
  if($null -eq $r.ExitCode -or $r.ExitCode -ne $code){throw ('Codigo incorreto para filho rapido: '+$code)}
  Write-Host ('[OK] Filho rapido retorna exatamente '+$code)
 }
 $file=Join-Path $temp 'streams.ps1'
 [IO.File]::WriteAllText($file,'[Console]::Out.WriteLine(("o" * 131072));[Console]::Error.WriteLine(("e" * 131072));exit 0')
 $out=Join-Path $temp 'stdout.log';$err=Join-Path $temp 'stderr.log'
 $r=Invoke-WinSlimRegressionProcess -Executable $shell -Arguments ('-NoLogo -NoProfile -NonInteractive -File "'+$file+'"') -WorkingDirectory $temp -Stdout $out -Stderr $err -TimeoutSeconds 15
 if($r.ExitCode -ne 0 -or (Get-Item -LiteralPath $out).Length -lt 131072 -or (Get-Item -LiteralPath $err).Length -lt 131072){throw 'Captura simultanea stdout/stderr falhou.'}
 Write-Host '[OK] Saidas maiores que o buffer dos pipes capturadas sem bloquear.'
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
