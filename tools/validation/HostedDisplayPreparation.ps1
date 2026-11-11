#requires -Version 5.1
<#
  Win-Slim Suite - Hosted display preparation for the native WPF self-test.

  The native self-test asserts the window keeps the contracted 1180x760 size.
  When the interactive session has a smaller working area, the operating
  system constrains the window (observed 1180x760 -> 1044x760 on the hosted
  runner) and the exact-size contract cannot hold. This tool prepares a
  display mode whose working area fits the contracted window and fails closed
  when that is impossible, so an environment limitation is never reported as
  a product defect and a product defect is never masked.

  Modes:
    (default)   prepare the display; throws when no acceptable mode exists
    -ProbeOnly  never changes the display; only reports the current state
    -Diagnose   additionally probes the real window contract with the
                application XAML and records the observed sizes
#>
[CmdletBinding()]
param(
    [ValidateRange(320, 16384)][int]$MinimumWidth = 1200,
    [ValidateRange(240, 16384)][int]$MinimumHeight = 800,
    [string]$EvidencePath,
    [switch]$ProbeOnly,
    [switch]$Diagnose,
    [string]$Root
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
}

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-WinSlimPrimaryWorkingArea {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($null -eq $screen) { throw 'Sessao sem ecra primario disponivel.' }
    return $screen.WorkingArea
}

function Write-WinSlimReceipt {
    param([object]$Receipt)
    if ([string]::IsNullOrWhiteSpace($EvidencePath)) { return }
    $directory = Split-Path -Parent $EvidencePath
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($EvidencePath, ($Receipt | ConvertTo-Json -Depth 8), $Utf8NoBom)
}

function Get-WinSlimDisplayDevice {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    if ($null -eq $screen) { return $null }
    return [string]$screen.DeviceName
}

function Get-WinSlimDisplayModes {
    $mode = New-Object WinSlimDisplayMode+DEVMODE
    $mode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSlimDisplayMode+DEVMODE')
    $device = Get-WinSlimDisplayDevice
    $modes = @()
    foreach ($target in @($device, $null)) {
        if ($null -eq $target -and $device) { continue }
        for ($index = 0; $index -lt 512; $index++) {
            if (-not [WinSlimDisplayMode]::EnumDisplaySettings($target, $index, [ref]$mode)) { break }
            $modes += [pscustomobject]@{ Width = [int]$mode.dmPelsWidth; Height = [int]$mode.dmPelsHeight; BitsPerPel = [int]$mode.dmBitsPerPel }
        }
        if ($modes.Count -gt 0) { break }
    }
    return $modes
}

function Set-WinSlimDisplayMode {
    param([int]$Width, [int]$Height)
    $mode = New-Object WinSlimDisplayMode+DEVMODE
    $mode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type]'WinSlimDisplayMode+DEVMODE')
    $device = Get-WinSlimDisplayDevice
    if (-not [WinSlimDisplayMode]::EnumDisplaySettings($device, -1, [ref]$mode)) {
        if (-not [WinSlimDisplayMode]::EnumDisplaySettings($null, -1, [ref]$mode)) { return $false }
    }
    $mode.dmFields = 0x80000 -bor 0x100000 -bor 0x40000
    $mode.dmPelsWidth = $Width
    $mode.dmPelsHeight = $Height
    $mode.dmBitsPerPel = 32
    return ([WinSlimDisplayMode]::ChangeDisplaySettings([ref]$mode, 0x01) -eq 0)
}

function Measure-WinSlimWindowContract {
    param([string]$RootPath)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName System.Windows.Forms
    $stages = [ordered]@{}
    $shell = Join-Path $RootPath 'src\UI\Native\R3_2_84\WinSlimShell.xaml'
    $detail = Join-Path $RootPath 'src\UI\Native\R3_2_84\WinSlimTweakDetail.xaml'
    $window = $null
    try {
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $stream = [System.IO.File]::OpenRead($shell)
        try {
            $reader = [System.Xml.XmlReader]::Create($stream, $settings)
            try { $window = [System.Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Dispose() }
        } finally { $stream.Dispose() }
        $working = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $stages['afterXaml'] = [string]$window.Width + 'x' + [string]$window.Height
        $stages['workingArea'] = $working.ToString()
        $stages['workingAreaWidth'] = [int]$working.Width
        $stages['workingAreaHeight'] = [int]$working.Height
        $stages['contractFits'] = ($working.Width -ge 1180 -and $working.Height -ge 760)
        if (Test-Path -LiteralPath $detail) {
            $detailControl = $null
            $detailStream = [System.IO.File]::OpenRead($detail)
            try {
                $detailReader = [System.Xml.XmlReader]::Create($detailStream, $settings)
                try { $detailControl = [System.Windows.Markup.XamlReader]::Load($detailReader) } finally { $detailReader.Dispose() }
            } finally { $detailStream.Dispose() }
            $window.Content = $detailControl
            $detailControl.Measure([System.Windows.Size]::new(1178, 758))
            $detailControl.Arrange([System.Windows.Rect]::new(0, 0, 1178, 758))
            $detailControl.UpdateLayout()
            $stages['afterDetailLayout'] = [string]$window.Width + 'x' + [string]$window.Height
        }
        $window.Show()
        $window.UpdateLayout()
        $stages['afterShow'] = [string]$window.Width + 'x' + [string]$window.Height
        $stages['actualAfterShow'] = [string]$window.ActualWidth + 'x' + [string]$window.ActualHeight
        $stages['contractHeld'] = ($stages['afterShow'] -eq '1180x760')
    } finally {
        if ($null -ne $window) { try { $window.Close() } catch { } }
    }
    return $stages
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WinSlimDisplayMode {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Ansi)] public static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
}
'@

$before = Get-WinSlimPrimaryWorkingArea
$receipt = [ordered]@{
    schemaVersion = 1
    RequiredWorkingArea = "$MinimumWidth" + 'x' + "$MinimumHeight"
    ContractedWindow = '1180x760'
    Mode = if ($ProbeOnly) { 'ProbeOnly' } else { 'Prepare' }
    Before = $before.ToString()
    BeforeWidth = [int]$before.Width
    BeforeHeight = [int]$before.Height
    Applied = $null
    Tried = @()
    Final = $null
    FinalWidth = 0
    FinalHeight = 0
    SatisfiesRequirement = $false
    AvailableModes = @()
    Probe = $null
    Utc = [DateTime]::UtcNow.ToString('o')
}
$receipt['AvailableModes'] = @(Get-WinSlimDisplayModes | ForEach-Object { "$($_.Width)x$($_.Height)@$($_.BitsPerPel)" })

if ($Diagnose) {
    $receipt['Probe'] = Measure-WinSlimWindowContract -RootPath $Root
    Write-WinSlimReceipt -Receipt $receipt
}

if ($ProbeOnly) {
    $satisfies = ($before.Width -ge $MinimumWidth -and $before.Height -ge $MinimumHeight)
    $receipt['SatisfiesRequirement'] = $satisfies
    $receipt['Final'] = $before.ToString()
    $receipt['FinalWidth'] = [int]$before.Width
    $receipt['FinalHeight'] = [int]$before.Height
    Write-WinSlimReceipt -Receipt $receipt
    Write-Host ('Display probe only: working area ' + $before.ToString() + '; satisfies=' + $satisfies)
    if (-not $satisfies) {
        throw ('Area de trabalho ' + $before.ToString() + ' nao atinge o minimo ' + $receipt.RequiredWorkingArea + ' e o modo ProbeOnly nao altera o ecra.')
    }
    exit 0
}

$candidates = @(
    [pscustomobject]@{ Width = 1920; Height = 1080 },
    [pscustomobject]@{ Width = 1600; Height = 1200 },
    [pscustomobject]@{ Width = 1280; Height = 1024 }
)
$tried = @()
foreach ($candidate in $candidates) {
    $changed = Set-WinSlimDisplayMode -Width $candidate.Width -Height $candidate.Height
    $tried += [ordered]@{ Requested = "$($candidate.Width)x$($candidate.Height)"; Accepted = $changed }
    if ($changed) {
        Start-Sleep -Seconds 2
        $current = Get-WinSlimPrimaryWorkingArea
        if ($current.Width -ge $MinimumWidth -and $current.Height -ge $MinimumHeight) {
            $receipt['Applied'] = [ordered]@{ Requested = "$($candidate.Width)x$($candidate.Height)"; WorkingArea = $current.ToString() }
            break
        }
    }
}
$receipt['Tried'] = $tried
$final = Get-WinSlimPrimaryWorkingArea
$receipt['Final'] = $final.ToString()
$receipt['FinalWidth'] = [int]$final.Width
$receipt['FinalHeight'] = [int]$final.Height
$receipt['SatisfiesRequirement'] = ($final.Width -ge $MinimumWidth -and $final.Height -ge $MinimumHeight)
if ($Diagnose) { $receipt['Probe'] = Measure-WinSlimWindowContract -RootPath $Root }
Write-WinSlimReceipt -Receipt $receipt

if (-not $receipt['SatisfiesRequirement']) {
    throw ('Area de trabalho final ' + $final.ToString() + ' nao atinge o minimo ' + $receipt.RequiredWorkingArea + '. A janela contratada 1180x760 nao pode ser preservada nesta sessao; o gate nao pode ser considerado valido.')
}
Write-Host ('Display prepared: ' + $final.ToString())
exit 0
