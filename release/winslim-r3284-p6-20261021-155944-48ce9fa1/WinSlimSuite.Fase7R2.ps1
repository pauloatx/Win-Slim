#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R2 launcher
 Dashboard + hardware/contexto sobre a baseline FASE 6.5 R4.1.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function Test-WinSlimAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-WinSlimAdmin)) {
    if (-not $PSCommandPath) { throw 'Execute este launcher a partir do arquivo WinSlimSuite.Fase7.ps1.' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"") -Verb RunAs
    exit
}

$Root = Split-Path -Parent $PSCommandPath
if (-not $Root) { $Root = $PSScriptRoot }

# Backend aprovado: mesma ordem de carga usada no gate FASE 6.5 R4.1.
. (Join-Path $Root 'src\Core\Planner.ps1')
. (Join-Path $Root 'src\Core\Transaction.ps1')
. (Join-Path $Root 'src\Core\CatalogRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetResolver.ps1')
. (Join-Path $Root 'src\Core\PresetPolicyEngine.ps1')
. (Join-Path $Root 'src\Core\PresetRuntime.ps1')
. (Join-Path $Root 'src\Core\PresetPlannerValidator.ps1')
. (Join-Path $Root 'src\Core\PresetPreview.ps1')
. (Join-Path $Root 'src\Core\PlannerOptimized.ps1')
. (Join-Path $Root 'src\Core\TransactionOptimized.ps1')
. (Join-Path $Root 'src\Core\RuntimePromotion.ps1')
Enable-WinSlimRuntimePromotion -Planner -Transaction | Out-Null

# Monta exatamente o backend aprovado de 230 tweaks, sem executar qualquer tweak.
$catalogFiles = @(
    'catalog.json',
    'catalogs\Game-Workload.json',
    'catalogs\validated\Advanced-Catalog.json',
    'catalogs\validated\Expansion-R4.json',
    'catalogs\validated\Expansion-R4.1.json',
    'catalogs\validated\Expansion-R4.2.json'
)
$allTweaks = New-Object System.Collections.ArrayList
foreach ($relative in $catalogFiles) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) { throw "Catalogo obrigatorio ausente: $relative" }
    $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = if ($json.PSObject.Properties.Name -contains 'tweaks') { @($json.tweaks) } else { @($json) }
    foreach ($item in $items) { [void]$allTweaks.Add($item) }
}
$allTweaks = @($allTweaks.ToArray())
if ($allTweaks.Count -ne 230) { throw "Backend inesperado: $($allTweaks.Count) tweaks; esperado: 230." }
if (@($allTweaks.id | Select-Object -Unique).Count -ne 230) { throw 'Backend invalido: IDs duplicados detectados.' }

$presetCatalog = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ruleCatalog = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-PresetRules-R2.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$PresetRuntime = New-WinSlimPresetRuntime -CatalogTweaks $allTweaks -PresetCatalog $presetCatalog -RuleCatalog $ruleCatalog
$PromotionStatus = Get-WinSlimRuntimePromotionStatus

. (Join-Path $Root 'src\UI\Fase7\SystemContextView.R2.ps1')
. (Join-Path $Root 'src\UI\Fase7\WinSlimShell.R2.ps1')
Show-WinSlimFase7Shell -RootPath $Root -PresetRuntime $PresetRuntime -PromotionStatus $PromotionStatus
