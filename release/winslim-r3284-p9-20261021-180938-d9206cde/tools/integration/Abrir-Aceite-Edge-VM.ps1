#requires -Version 5.1
# Run interactively INSIDE the lab VM from the read-only Builds share.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$computer = Get-CimInstance Win32_ComputerSystem
if ($env:COMPUTERNAME -ine 'TESTE' -or $computer.Model -notmatch 'VirtualBox') {
    throw 'Aceite de politicas Edge permitido somente na VM TESTE / VirtualBox.'
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    # Visible UAC approval belongs to the person performing the manual test.
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ArgumentList ('-NoLogo -NoProfile -ExecutionPolicy Bypass -File "'+$PSCommandPath+'"') | Out-Null
    return
}
$source = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$localRoot = 'C:\WinSlim\Aceite'
if ($source.StartsWith($localRoot+'\', [StringComparison]::OrdinalIgnoreCase)) {
    $local = $source
} else {
    $local = Join-Path $localRoot (Split-Path -Leaf $source)
    if (Test-Path -LiteralPath $local) { throw ('Copia local ja existe. Para reabrir sem sobrescrever, execute o script em '+$local+'\tools\integration') }
    [void][IO.Directory]::CreateDirectory($localRoot)
    Copy-Item -LiteralPath $source -Destination $local -Recurse
    if ((Get-FileHash -LiteralPath (Join-Path $local 'bin\WinSlim.UI.Native.R3.2.84.exe')).Hash -cne (Get-FileHash -LiteralPath (Join-Path $source 'bin\WinSlim.UI.Native.R3.2.84.exe')).Hash) { throw 'Binario local difere da candidata.' }
}
Write-Host ('Preset do lote: '+(Join-Path $local 'Teste-Lote-Edge-R3.2.84.json'))
Write-Host 'Conta elevada confirmada. Aplicacao e restauracao exigem os comandos explicitos na interface.'
Start-Process -FilePath (Join-Path $local 'bin\WinSlim.UI.Native.R3.2.84.exe') -ArgumentList ('--root "'+$local+'"') -WorkingDirectory $local | Out-Null
