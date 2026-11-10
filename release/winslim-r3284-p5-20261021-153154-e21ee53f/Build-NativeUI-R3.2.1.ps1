#requires -Version 5.1
[CmdletBinding()]
param([switch]$IfNeeded)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSCommandPath
$SourceDir = Join-Path $Root 'src\UI\Native\R3_2_1'
$BinDir = Join-Path $Root 'bin'
$Exe = Join-Path $BinDir 'WinSlim.UI.Native.R3.2.1.exe'
$ConfigSource = Join-Path $SourceDir 'WinSlim.UI.Native.exe.config'
$ConfigDest = "$Exe.config"
$LogDir = Join-Path $Root 'logs'
$BuildLog = Join-Path $LogDir 'build-native-r3.2.1.log'

if (-not (Test-Path -LiteralPath $BinDir)) { New-Item -ItemType Directory -Path $BinDir -Force | Out-Null }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$requiredSources = @('Program.cs','BridgeClient.cs','MainWindowController.cs')
$sources = foreach ($name in $requiredSources) {
    $path = Join-Path $SourceDir $name
    if (-not (Test-Path -LiteralPath $path)) { throw "Fonte C# ausente: $name" }
    Get-Item -LiteralPath $path
}
foreach ($required in @('WinSlimShell.xaml','WinSlim.UiBridge.ps1','WinSlim.UI.Native.exe.config')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $required))) { throw "Arquivo Native UI ausente: $required" }
}

if ($IfNeeded -and (Test-Path -LiteralPath $Exe) -and (Test-Path -LiteralPath $ConfigDest)) {
    $exeTime = (Get-Item -LiteralPath $Exe).LastWriteTimeUtc
    $inputs = @($sources) + @(
        Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlimShell.xaml'),
        Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlim.UiBridge.ps1'),
        Get-Item -LiteralPath $ConfigSource
    )
    $newest = ($inputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if ($exeTime -ge $newest) {
        Write-Host '[OK] Native UI R3.2.1 já compilada e atualizada.' -ForegroundColor Green
        exit 0
    }
}

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe do .NET Framework 4.x não foi encontrado.' }

# Load only the framework assemblies required by this native WPF host.
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
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

# Use a response file instead of PowerShell native-argument expansion. This avoids
# quoting differences between Windows PowerShell 5.1 builds and paths with spaces.
$rsp = Join-Path $env:TEMP ('winslim-native-r321-' + [guid]::NewGuid().ToString('N') + '.rsp')
try {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('/nologo')
    $lines.Add('/target:winexe')
    $lines.Add('/platform:anycpu')
    $lines.Add('/optimize+')
    $lines.Add('/debug-')
    $lines.Add('/warn:4')
    $lines.Add('/langversion:5')
    $lines.Add('/codepage:65001')
    $lines.Add('/utf8output')
    $lines.Add('/out:"' + $Exe + '"')
    foreach ($ref in $refs) { $lines.Add('/reference:"' + $ref + '"') }
    foreach ($src in $sources) { $lines.Add('"' + $src.FullName + '"') }
    [System.IO.File]::WriteAllLines($rsp, $lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))

    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' Win-Slim Suite - Build Native UI R3.2.1' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ("Compiler: {0}" -f $csc) -ForegroundColor DarkGray

    $compilerOutput = @(& $csc ("@" + $rsp) 2>&1)
    $exitCode = $LASTEXITCODE
    $compilerOutput | ForEach-Object { [string]$_ } | Set-Content -LiteralPath $BuildLog -Encoding UTF8

    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $Exe)) {
        Write-Host '[ERRO] Compilação C# falhou. Diagnóstico do compilador:' -ForegroundColor Red
        foreach ($line in @($compilerOutput | Select-Object -Last 60)) { Write-Host ('  ' + [string]$line) -ForegroundColor Red }
        throw "Falha na compilação da Native UI (csc exit code $exitCode). Log: $BuildLog"
    }

    Copy-Item -LiteralPath $ConfigSource -Destination $ConfigDest -Force
    $hash = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
    Write-Host '[OK] WinSlim.UI.Native.R3.2.1.exe compilado.' -ForegroundColor Green
    Write-Host ("SHA-256: {0}" -f $hash) -ForegroundColor DarkGray
    Write-Host ("Log: {0}" -f $BuildLog) -ForegroundColor DarkGray
    exit 0
}
finally {
    Remove-Item -LiteralPath $rsp -Force -ErrorAction SilentlyContinue
}
