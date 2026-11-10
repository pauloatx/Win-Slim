#requires -Version 5.1
# Runs the R62 gate with visible progress and UTF-8 diagnostics.
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$test=Join-Path $root 'tests\Test-Fase7-R3.2.80-NativeUI.ps1'
$log=Join-Path $root 'logs\gate-native-r3.2.80-visivel.log'
$writer=$null
$code=1
try {
 if(-not (Test-Path -LiteralPath $test -PathType Leaf)){throw 'Extraia os arquivos na pasta winslim_fase7_r3_2_70, ao lado de Executar-WinSlim-R3.2.80.bat.'}
 [void][IO.Directory]::CreateDirectory((Split-Path -Parent $log))
 $encoding=New-Object Text.UTF8Encoding($false)
 $writer=New-Object IO.StreamWriter($log,$false,$encoding)
 $writer.AutoFlush=$true
 $writer.WriteLine(('Inicio: '+[DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')))
 $writer.WriteLine(('PowerShell: '+$PSVersionTable.PSVersion.ToString()))
 # Continue only in the wrapper so redirected error records remain visible.
 # The original test retains its own Stop policy and all original checks.
 $ErrorActionPreference='Continue'
 & $test -Root $root *>&1 | ForEach-Object {
  $line=($_ | Out-String -Width 240).TrimEnd([char[]]"`r`n")
  $writer.WriteLine($line)
  Write-Host $line
 }
 $code=if($null -eq $LASTEXITCODE){1}else{[int]$LASTEXITCODE}
 $ErrorActionPreference='Stop'
 if($code -ne 0){
  $startup=Join-Path $root 'logs\ui-native-r3.2.80.log'
  if(Test-Path -LiteralPath $startup -PathType Leaf){
   $heading='Diagnostico adicional da Native UI (ultimas 20 linhas):'
   $writer.WriteLine($heading);Write-Host $heading
   foreach($entry in @(Get-Content -LiteralPath $startup -Encoding UTF8 -Tail 20)){$writer.WriteLine($entry);Write-Host $entry}
  }
 }
} catch {
 $message='[ERRO] '+$_.Exception.Message
 Write-Host $message
 if($null -ne $writer){$writer.WriteLine($message);$writer.WriteLine($_.ScriptStackTrace)}
 $code=1
} finally {
 if($null -ne $writer){$writer.WriteLine(('Resultado: '+$code));$writer.Dispose()}
}
Write-Host ('Log: '+$log)
exit $code
