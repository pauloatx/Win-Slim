function Assert-WinSlimCompleteRegression {
 param($Report,[object[]]$Cases,[int]$ProcessExit)
 if($ProcessExit -ne 0 -or $null -eq $Report -or $Report.Passed -ne $true -or $Report.ExitCode -ne 0){throw 'O gate completo nao passou.'}
 $expected=@{};$seen=@{}
 foreach($case in $Cases){if($expected.ContainsKey([string]$case.id)){throw 'Cadastro duplicado.'};$expected[[string]$case.id]=$true}
 if($expected.Count -eq 0 -or @($Report.Results).Count -ne $expected.Count){throw 'Relatorio incompleto ou vazio.'}
 foreach($row in $Report.Results){
  $id=[string]$row.Id
  if(-not $expected.ContainsKey($id) -or $seen.ContainsKey($id) -or $row.Status -cne 'Passed' -or $null -eq $row.ExitCode -or $row.ExitCode -ne 0){throw ('Resultado invalido: '+$id)}
  $seen[$id]=$true
 }
}
function Export-WinSlimDiagnostic {
 param([string]$Root,[string]$RunDirectory,[switch]$IncludeBackups)
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $staging=Join-Path ([IO.Path]::GetTempPath()) ('winslim-diagnostic-'+[guid]::NewGuid().ToString('N'))
 $temporary=Join-Path $Root ('logs\diagnostic-'+[guid]::NewGuid().ToString('N')+'.zip')
 $destination=Join-Path $Root 'WinSlim-Diagnostico-R3.2.84.zip'
 try {
  # The run summary identifies the evidence revision, including failed runs.
  # Do not silently package another revision when metadata cannot be read.
  $summary=Get-Content -LiteralPath (Join-Path $RunDirectory 'summary.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  $revision=[string]$summary.Revision
  if($revision -notmatch '\AR[0-9]+\.[0-9]+\.[0-9]+\z'){throw 'Revisao do diagnostico ausente ou invalida.'}
  $revisionPattern='(?<![A-Za-z0-9])'+[regex]::Escape($revision)+'(?![0-9]|\.[0-9])'
  [void][IO.Directory]::CreateDirectory($staging)
  Copy-Item -LiteralPath $RunDirectory -Destination (Join-Path $staging 'validacao') -Recurse
  $report=Join-Path $RunDirectory 'regressions.json'
  if(Test-Path -LiteralPath $report){
   $data=Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
   $directories=@($data.Results | ForEach-Object {if($_.Stdout){Split-Path -Parent $_.Stdout}} | Select-Object -Unique)
   foreach($dir in $directories){
    $full=[IO.Path]::GetFullPath($dir)
    $logs=[IO.Path]::GetFullPath((Join-Path $Root 'logs')).TrimEnd('\')+'\'
    if(-not $full.StartsWith($logs,[StringComparison]::OrdinalIgnoreCase)){throw 'Pasta de evidencia fora de logs.'}
    if(Test-Path -LiteralPath $full){Copy-Item -LiteralPath $full -Destination (Join-Path $staging (Split-Path -Leaf $full)) -Recurse}
   }
  }
  $build=Join-Path $staging 'build';[void][IO.Directory]::CreateDirectory($build)
  foreach($file in (Get-ChildItem -LiteralPath (Join-Path $Root 'logs') -File | Where-Object {$_.Name -match $revisionPattern -and $_.Extension -in @('.log','.json')})){
   Copy-Item -LiteralPath $file.FullName -Destination $build -ErrorAction Stop
  }
  $backups=Join-Path $Root 'Backups\UI'
  if($IncludeBackups -and (Test-Path -LiteralPath $backups)){Copy-Item -LiteralPath $backups -Destination (Join-Path $staging 'Backups-UI') -Recurse}
  $benchmarks=Join-Path $Root 'Benchmarks'
  if(Test-Path -LiteralPath $benchmarks){
   $destinationBenchmarks=Join-Path $staging 'Benchmarks';[void][IO.Directory]::CreateDirectory($destinationBenchmarks)
   foreach($summary in (Get-ChildItem -LiteralPath $benchmarks -Filter 'summary.json' -File -Recurse)){
    $name=(Split-Path -Leaf $summary.DirectoryName)+'.json'
    Copy-Item -LiteralPath $summary.FullName -Destination (Join-Path $destinationBenchmarks $name)
   }
  }
  [IO.Compression.ZipFile]::CreateFromDirectory($staging,$temporary)
  $archive=[IO.Compression.ZipFile]::OpenRead($temporary)
  try{if($archive.Entries.Count -eq 0){throw 'ZIP vazio.'}}finally{$archive.Dispose()}
  if(Test-Path -LiteralPath $destination){
   # PS5.1 binds a null string argument as an empty backup path. Use a real path.
   $previous=$destination+'.previous-'+[guid]::NewGuid().ToString('N')
   [IO.File]::Replace($temporary,$destination,$previous)
   if(Test-Path -LiteralPath $previous){Remove-Item -LiteralPath $previous -Force}
  }else{[IO.File]::Move($temporary,$destination)}
  return $destination
 } finally {
  if(Test-Path -LiteralPath $staging){Remove-Item -LiteralPath $staging -Recurse -Force}
  if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}
 }
}
