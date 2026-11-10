#requires -Version 5.1
[CmdletBinding()]
param([switch]$IfNeeded)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSCommandPath
$SourceDir = Join-Path $Root 'src\UI\Native\R3_2_5'
$BinDir = Join-Path $Root 'bin'
$Exe = Join-Path $BinDir 'WinSlim.UI.Native.R3.2.5.exe'
$ConfigSource = Join-Path $SourceDir 'WinSlim.UI.Native.exe.config'
$ConfigDest = "$Exe.config"
$LogDir = Join-Path $Root 'logs'
$BuildLog = Join-Path $LogDir 'build-native-r3.2.5.log'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$NewLine = [Environment]::NewLine

function Write-BuildLog {
    param([Parameter(Mandatory=$true)][string[]]$Lines)
    $text = ($Lines -join $NewLine) + $NewLine
    [System.IO.File]::WriteAllText($BuildLog, $text, $Utf8NoBom)
}
function Add-BuildLog {
    param([Parameter(Mandatory=$true)][string[]]$Lines)
    if ($Lines.Count -eq 0) { return }
    $text = ($Lines -join $NewLine) + $NewLine
    [System.IO.File]::AppendAllText($BuildLog, $text, $Utf8NoBom)
}

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
        Write-BuildLog -Lines @(
            'Win-Slim Native UI build R3.2.5',
            ('UTC: ' + [DateTime]::UtcNow.ToString('o')),
            'Mode: IfNeeded / up-to-date',
            ('Executable: ' + $Exe),
            'ExitCode: 0'
        )
        Write-Host '[OK] Native UI R3.2.5 ja compilada e atualizada.' -ForegroundColor Green
        exit 0
    }
}

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe do .NET Framework 4.x nao foi encontrado.' }

# Referencias explicitas e deterministicas. /noconfig vai diretamente ao csc.exe,
# nunca dentro do response file, evitando duplicacao via csc.rsp/GAC.
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

$rsp = Join-Path $env:TEMP ('winslim-native-r325-' + [guid]::NewGuid().ToString('N') + '.rsp')
try {
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('/nologo')
    [void]$lines.Add('/target:winexe')
    [void]$lines.Add('/platform:anycpu')
    [void]$lines.Add('/optimize+')
    [void]$lines.Add('/debug-')
    [void]$lines.Add('/warn:4')
    [void]$lines.Add('/langversion:5')
    [void]$lines.Add('/codepage:65001')
    [void]$lines.Add('/utf8output')
    [void]$lines.Add('/out:"' + $Exe + '"')
    foreach ($ref in $refs) { [void]$lines.Add('/reference:"' + $ref + '"') }
    foreach ($src in $sources) { [void]$lines.Add('"' + $src.FullName + '"') }
    [System.IO.File]::WriteAllLines($rsp, [string[]]$lines.ToArray(), $Utf8NoBom)

    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ' Win-Slim Suite - Build Native UI R3.2.5' -ForegroundColor White
    Write-Host '============================================================' -ForegroundColor DarkGray
    Write-Host ("Compiler: {0}" -f $csc) -ForegroundColor DarkGray
    Write-Host 'Compiler config: direct /noconfig argument + explicit framework references' -ForegroundColor DarkGray

    $compilerArgs = @('/noconfig', ("@" + $rsp))

    Write-BuildLog -Lines @(
        'Win-Slim Native UI build R3.2.5',
        ('UTC: ' + [DateTime]::UtcNow.ToString('o')),
        ('Compiler: ' + $csc),
        'Invocation: csc.exe /noconfig @response-file',
        ('ResponseFile: ' + $rsp),
        ('ReferenceCount: ' + $refs.Count),
        ('SourceCount: ' + $sources.Count),
        '--- compiler output ---'
    )

    $compilerOutput = @(& $csc @compilerArgs 2>&1)
    $exitCode = $LASTEXITCODE

    if ($compilerOutput.Count -gt 0) {
        $outputLines = [string[]]@($compilerOutput | ForEach-Object { [string]$_ })
        Add-BuildLog -Lines $outputLines
    }
    Add-BuildLog -Lines @('--- result ---', ('ExitCode: ' + [string]$exitCode))

    if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $Exe)) {
        Write-Host '[ERRO] Compilacao C# falhou. Diagnostico do compilador:' -ForegroundColor Red
        foreach ($line in @($compilerOutput | Select-Object -Last 80)) { Write-Host ('  ' + [string]$line) -ForegroundColor Red }
        throw "Falha na compilacao da Native UI (csc exit code $exitCode). Log: $BuildLog"
    }

    Copy-Item -LiteralPath $ConfigSource -Destination $ConfigDest -Force
    if (-not (Test-Path -LiteralPath $ConfigDest)) { throw "Falha ao copiar config .NET Framework: $ConfigDest" }

    $hash = (Get-FileHash -LiteralPath $Exe -Algorithm SHA256).Hash
    Write-Host '[OK] WinSlim.UI.Native.R3.2.5.exe compilado.' -ForegroundColor Green
    Write-Host ("SHA-256: {0}" -f $hash) -ForegroundColor DarkGray
    Write-Host ("Log: {0}" -f $BuildLog) -ForegroundColor DarkGray
    exit 0
}
finally {
    Remove-Item -LiteralPath $rsp -Force -ErrorAction SilentlyContinue
}
