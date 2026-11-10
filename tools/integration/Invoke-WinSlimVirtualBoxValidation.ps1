#requires -Version 5.1
[CmdletBinding()]
param([string]$VM='teste win-slim-win11', [string]$Snapshot='WINSLIM_BASELINE')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runId = 'winslim-r3284-p4-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$builds = 'C:\WinSlim-Integracao\Builds'
$logs = 'C:\WinSlim-Integracao\Logs'
$destination = Join-Path $builds $runId
$archive = Join-Path $logs ($runId+'-host')
if (Test-Path -LiteralPath $destination) { throw 'Staging ja existe.' }
[void][IO.Directory]::CreateDirectory($destination)
[void][IO.Directory]::CreateDirectory($archive)
foreach ($entry in (Get-ChildItem -LiteralPath $root -Force)) {
    if ($entry.Name -in @('.git','.agents','.codex','.aws','logs','Backups','__pycache__') -or $entry.Name -like 'WinSlim-Diagnostico-*.zip') { continue }
    Copy-Item -LiteralPath $entry.FullName -Destination $destination -Recurse
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Test-WinSlimVmCandidate.ps1') -Destination $destination
foreach ($name in @('resultado.json','execucao.log','inventario.txt')) {
    $old = Join-Path $logs $name
    if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination $archive }
}
Copy-Item -LiteralPath (Join-Path $root 'logs\build-native-r3.2.84.log') -Destination (Join-Path $archive 'host-build.log')
[ordered]@{RunId=$runId;Source=$root;VM=$VM;Snapshot=$Snapshot;HostBinarySHA256=(Get-FileHash -LiteralPath (Join-Path $destination 'bin\WinSlim.UI.Native.R3.2.84.exe')).Hash} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $archive 'staging.json') -Encoding UTF8
Write-Output ('RunId: '+$runId)
Write-Output ('Staging: '+$destination)
# The controller retries GuestControl after boot. No password prompt is answered;
# only its interactive boot acknowledgement is automated for this lab execution.
function Read-Host {
    param([string]$Prompt)
    if ($Prompt -notlike 'Entre no Windows da VM*') { throw ('Prompt inesperado: '+$Prompt) }
    Write-Host 'Boot iniciado; o controlador verificara a disponibilidade do GuestControl.'
    return ''
}
& 'C:\WinSlim-Codex-VirtualBox-Pacote-Unico\WinSlim-VirtualBox.ps1' -VM $VM -Acao Executar -UsarCredencialSalva -Snapshot $Snapshot -Teste ($runId+'\Test-WinSlimVmCandidate.ps1') -RestaurarAntes -RestaurarDepois
