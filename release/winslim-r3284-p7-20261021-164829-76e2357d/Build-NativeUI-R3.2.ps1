#requires -Version 5.1
[CmdletBinding()]
param([switch]$IfNeeded)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSCommandPath
$SourceDir = Join-Path $Root 'src\UI\Native'
$BinDir = Join-Path $Root 'bin'
$Exe = Join-Path $BinDir 'WinSlim.UI.Native.R3.2.exe'
$ConfigSource = Join-Path $SourceDir 'WinSlim.UI.Native.R3_2.exe.config'
$ConfigDest = "$Exe.config"
$Manifest = Join-Path $SourceDir 'WinSlim.NativeUI.R3_2.manifest'

if (-not (Test-Path -LiteralPath $BinDir)) { New-Item -ItemType Directory -Path $BinDir -Force | Out-Null }

$sources = @(Get-ChildItem -LiteralPath $SourceDir -Filter '*.cs' -File | Sort-Object Name)
if ($sources.Count -lt 3) { throw 'Fontes C# da Native UI incompletas.' }
foreach ($required in @('WinSlimShell.R3_2.xaml','WinSlim.UiBridge.R3_2.ps1','WinSlim.NativeUI.R3_2.manifest','WinSlim.UI.Native.R3_2.exe.config')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $required))) { throw "Arquivo Native UI ausente: $required" }
}

if ($IfNeeded -and (Test-Path -LiteralPath $Exe)) {
    $exeTime = (Get-Item -LiteralPath $Exe).LastWriteTimeUtc
    $inputs = @($sources) + @(
        Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlimShell.R3_2.xaml'),
        Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlim.UiBridge.R3_2.ps1'),
        Get-Item -LiteralPath $Manifest,
        Get-Item -LiteralPath $ConfigSource
    )
    $newest = ($inputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if ($exeTime -ge $newest) {
        Write-Host '[OK] Native UI já compilada e atualizada.' -ForegroundColor Green
        exit 0
    }
}

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe do .NET Framework 4.x não foi encontrado. Windows 10/11 deve fornecer este compilador.' }

# Resolve reference assemblies through the framework/GAC already present in Windows.
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Web.Extensions

$refs = @(
    [System.Windows.Window].Assembly.Location,
    [System.Windows.Media.Brush].Assembly.Location,
    [System.Windows.DependencyObject].Assembly.Location,
    [System.Xaml.XamlServices].Assembly.Location,
    [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,
    [System.Xml.XmlReader].Assembly.Location,
    [System.Diagnostics.Process].Assembly.Location,
    [System.Linq.Enumerable].Assembly.Location
) | Where-Object { $_ } | Select-Object -Unique

$args = New-Object System.Collections.ArrayList
[void]$args.Add('/nologo')
[void]$args.Add('/target:winexe')
[void]$args.Add('/platform:anycpu')
[void]$args.Add('/optimize+')
[void]$args.Add('/debug:pdbonly')
[void]$args.Add('/warn:4')
[void]$args.Add('/utf8output')
[void]$args.Add("/out:$Exe")
[void]$args.Add("/win32manifest:$Manifest")
foreach ($ref in $refs) { [void]$args.Add("/reference:$ref") }
foreach ($src in $sources) { [void]$args.Add($src.FullName) }

Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ' Win-Slim Suite - Build Native UI R3.2' -ForegroundColor White
Write-Host '============================================================' -ForegroundColor DarkGray
Write-Host ("Compiler: {0}" -f $csc) -ForegroundColor DarkGray

& $csc @($args.ToArray())
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Exe)) {
    throw "Falha na compilação da Native UI (csc exit code $LASTEXITCODE)."
}
Copy-Item -LiteralPath $ConfigSource -Destination $ConfigDest -Force

$hash = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
Write-Host '[OK] WinSlim.UI.Native.R3.2.exe compilado.' -ForegroundColor Green
Write-Host ("SHA-256: {0}" -f $hash) -ForegroundColor DarkGray
exit 0
