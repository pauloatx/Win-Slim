#requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$computer = Get-CimInstance Win32_ComputerSystem
if ($computer.Model -notmatch 'VirtualBox' -or -not $root.StartsWith('C:\WinSlim\Testes\Build\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Este executor deve rodar somente no staging da VM VirtualBox.'
}
$runId = Split-Path -Leaf $root
$evidence = Join-Path $root 'logs\integration'
[void][IO.Directory]::CreateDirectory($evidence)
$summary = [ordered]@{RunId=$runId;Computer=$env:COMPUTERNAME;Model=$computer.Model;HostBinaryPassed=$false;CandidatePassed=$false;RestoreWindowsPassed=$false;DiagnosticBuildLogsPassed=$false;ProductionApproved=$false;ManualValidation='Pending';Errors=@()}
$code = 1
try {
    $exe = Join-Path $root 'bin\WinSlim.UI.Native.R3.2.84.exe'
    $summary.HostBinarySHA256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    $self = Join-Path $evidence 'host-binary-selftest.json'
    $process = Start-Process -FilePath $exe -ArgumentList ('--root "'+$root+'" --self-test "'+$self+'"') -WorkingDirectory $root -WindowStyle Hidden -Wait -PassThru
    try {
        $summary.HostBinaryPassed = ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $self) -and (Get-Content -LiteralPath $self -Raw -Encoding UTF8 | ConvertFrom-Json).ok -eq $true)
        if (-not $summary.HostBinaryPassed) { $summary.Errors += 'Self-test do binario compilado no host falhou.' }
    } finally { $process.Dispose() }
    & (Join-Path $root 'Iniciar-Validacao.bat') /ci
    $summary.CandidatePassed = ($LASTEXITCODE -eq 0)
    if (-not $summary.CandidatePassed) { $summary.Errors += 'Gate completo da candidata falhou; consulte os logs por caso.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $root 'WinSlim-Diagnostico-R3.2.84.zip'))
    try {
        $buildLogs = @(Get-ChildItem -LiteralPath (Join-Path $root 'logs') -File | Where-Object {$_.Name -match 'r3\.2\.84(?![0-9]|\.[0-9])' -and $_.Extension -in @('.log','.json')})
        if ($buildLogs.Count -eq 0) { throw 'Nenhum log corrente foi produzido.' }
        foreach ($file in $buildLogs) {
            $entry = @($archive.Entries | Where-Object {$_.FullName.Replace('\','/') -ceq ('build/'+$file.Name)})
            if ($entry.Count -ne 1) { throw ('ZIP sem log unico: '+$file.Name) }
            $stream = $entry[0].Open(); $hasher = [Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-','') } finally { $stream.Dispose(); $hasher.Dispose() }
            if ($hash -cne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw ('Log arquivado divergente: '+$file.Name) }
        }
        $summary.DiagnosticBuildLogsPassed = $true
        $summary.DiagnosticBuildEntries = $buildLogs.Count
    } finally { $archive.Dispose() }
    $shell = Join-Path $PSHOME 'powershell.exe'
    & $shell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'tests\Test-Fase7-R3.2.84-RestoreWindows.ps1') -Root $root
    $summary.RestoreWindowsPassed = ($LASTEXITCODE -eq 0)
    if (-not $summary.RestoreWindowsPassed) { $summary.Errors += 'RestoreWindows falhou.' }
    if ($summary.HostBinaryPassed -and $summary.CandidatePassed -and $summary.RestoreWindowsPassed -and $summary.DiagnosticBuildLogsPassed) { $code = 0 }
} catch {
    $summary.Errors += $_.Exception.Message
    Write-Output ($_ | Out-String)
} finally {
    $summary.ExitCode = $code
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
    # Export all build/self-test logs as well as the application's diagnostic ZIP.
    # The directory is unique: existing host evidence is never replaced.
    $destination = Join-Path '\\vboxsvr\WinSlim_Logs' $runId
    if (Test-Path -LiteralPath $destination) { throw 'Pasta de evidencia ja existe; nao sera sobrescrita.' }
    [void][IO.Directory]::CreateDirectory($destination)
    Copy-Item -LiteralPath (Join-Path $root 'logs') -Destination $destination -Recurse
    $diagnostic = Join-Path $root 'WinSlim-Diagnostico-R3.2.84.zip'
    if (Test-Path -LiteralPath $diagnostic) { Copy-Item -LiteralPath $diagnostic -Destination $destination }
    Write-Output ('Evidencias completas: '+$destination)
    Write-Output ($summary | ConvertTo-Json -Depth 8)
}
exit $code
