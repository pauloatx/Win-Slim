function Invoke-WinSlimRegressionProcess {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$Executable,[Parameter(Mandatory=$true)][string]$Arguments,[Parameter(Mandatory=$true)][string]$WorkingDirectory,[Parameter(Mandatory=$true)][string]$Stdout,[Parameter(Mandatory=$true)][string]$Stderr,[int]$TimeoutSeconds=90)
 $process=New-Object Diagnostics.Process
 $outputTask=$null;$errorTask=$null
 try {
  $start=New-Object Diagnostics.ProcessStartInfo
  $start.FileName=$Executable;$start.Arguments=$Arguments;$start.WorkingDirectory=$WorkingDirectory
  $start.UseShellExecute=$false;$start.CreateNoWindow=$true
  $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
  $process.StartInfo=$start
  if(-not $process.Start()){throw 'O processo de teste nao iniciou.'}
  # Keep the original process handle alive; Start-Process/Refresh can lose the exit code on PS5.1.
  $handle=$process.Handle
  $outputTask=$process.StandardOutput.ReadToEndAsync()
  $errorTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($TimeoutSeconds*1000)){
   & (Join-Path $env:SystemRoot 'System32\taskkill.exe') /PID $process.Id /T /F 2>&1 | Out-Null
   [void]$process.WaitForExit(5000)
   throw 'Tempo limite excedido; teste reprovado.'
  }
  $process.WaitForExit()
  $code=$process.ExitCode
  if($null -eq $code){throw 'Codigo de saida indisponivel; teste nao pode ser aprovado.'}
  return [pscustomobject]@{ExitCode=[int]$code}
 } finally {
  try {
   $encoding=New-Object Text.UTF8Encoding($false)
   if($null -ne $outputTask){if(-not $outputTask.Wait(5000)){throw 'Timeout drenando stdout do teste.'};[IO.File]::WriteAllText($Stdout,$outputTask.GetAwaiter().GetResult(),$encoding)}
   if($null -ne $errorTask){if(-not $errorTask.Wait(5000)){throw 'Timeout drenando stderr do teste.'};[IO.File]::WriteAllText($Stderr,$errorTask.GetAwaiter().GetResult(),$encoding)}
  } finally {$process.Dispose()}
 }
}
