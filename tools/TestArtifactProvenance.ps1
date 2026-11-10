#requires -Version 5.1
function Write-WinSlimTestArtifactRecord {
 [CmdletBinding()]
 param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Artifact,[Parameter(Mandatory=$true)][string]$Compiler,[string[]]$Sources,[int]$CompilerExit,[ValidateSet('Compiled','ExecutionFailed','Completed')][string]$Stage='Compiled')
 $directory=Join-Path ([IO.Path]::GetFullPath($Root)) 'logs\test-artifacts'
 [void][IO.Directory]::CreateDirectory($directory)
 $readHash={param([string]$Path)
  $full=[IO.Path]::GetFullPath($Path)
  try{$item=Get-Item -LiteralPath $full -ErrorAction Stop;[pscustomobject]@{Path=$full;SHA256=(Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash;Bytes=$item.Length;ModifiedUtc=$item.LastWriteTimeUtc.ToString('o');Error=$null}}
  catch{[pscustomobject]@{Path=$full;SHA256=$null;Bytes=$null;ModifiedUtc=$null;Error=$_.Exception.Message}}
 }
 $binary=& $readHash $Artifact
 $compilerRecord=& $readHash $Compiler
 $sourceRecords=@(foreach($source in $Sources){& $readHash $source})
 $record=[ordered]@{SchemaVersion=1;Utc=[DateTime]::UtcNow.ToString('o');Stage=$Stage;CompilerExit=$CompilerExit;Artifact=$binary;Compiler=$compilerRecord;Sources=$sourceRecords;ExecutedByRecorder=$false;SecurityVerdict='Not assessed by hash/provenance recorder'}
 $path=Join-Path $directory ('artifact-'+[guid]::NewGuid().ToString('N')+'.json')
 [IO.File]::WriteAllText($path,($record | ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
 [pscustomobject]@{Path=$path;ArtifactSHA256=$binary.SHA256;ArtifactReadable=($null -ne $binary.SHA256);InputsReadable=($null -ne $compilerRecord.SHA256 -and $sourceRecords.Count -gt 0 -and @($sourceRecords | Where-Object {$null -eq $_.SHA256}).Count -eq 0);SourceCount=$sourceRecords.Count}
}
