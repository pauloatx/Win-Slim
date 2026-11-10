#requires -Version 5.1
function Get-WinSlimNativeIntegrityResults {
 [CmdletBinding()]
 param([string]$Root,[System.Collections.IDictionary]$Expected,
       [ValidateSet('BeforeBuild','AfterBuild')][string]$Phase,$BuildReceipt)
 $rootPath=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
 if($null -eq $Expected -or $Expected.Count -eq 0){throw 'Release integrity list is empty.'}
 if($Phase -eq 'AfterBuild'){
  if($null -eq $BuildReceipt -or $BuildReceipt.schemaVersion -ne 1 -or
     $BuildReceipt.inputs -notmatch '\A[0-9a-fA-F]{64}\z' -or
     $BuildReceipt.exeHash -notmatch '\A[0-9a-fA-F]{64}\z' -or
     $BuildReceipt.configHash -notmatch '\A[0-9a-fA-F]{64}\z'){
   throw 'Current successful build receipt is missing or invalid.'
  }
 }
 foreach($name in @($Expected.Keys | Sort-Object)){
  $expectedHash=[string]$Expected[$name]
  if($expectedHash -notmatch '\A[0-9a-fA-F]{64}\z'){throw 'Invalid release integrity hash.'}
  $path=[IO.Path]::GetFullPath((Join-Path $Root $name))
  if(-not $path.StartsWith($rootPath,[StringComparison]::OrdinalIgnoreCase)){throw 'Integrity path outside root.'}
  # Only the two outputs produced by the official build change identity.
  # All delivered input hashes are checked before compilation and again after it.
  if($Phase -eq 'AfterBuild'){
   switch(([string]$name).Replace('\','/')){
    'bin/WinSlim.UI.Native.R3.2.84.exe' {$expectedHash=[string]$BuildReceipt.exeHash}
    'bin/WinSlim.UI.Native.R3.2.84.exe.config' {$expectedHash=[string]$BuildReceipt.configHash}
   }
  }
  $actual=$null
  if(Test-Path -LiteralPath $path -PathType Leaf){$actual=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
  [pscustomobject]@{Path=[string]$name;ExpectedSHA256=$expectedHash.ToLowerInvariant();ActualSHA256=$actual;Passed=($null -ne $actual -and $actual -eq $expectedHash)}
 }
}
