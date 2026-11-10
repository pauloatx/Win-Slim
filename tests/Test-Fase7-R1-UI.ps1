#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Root = Split-Path -Parent $PSScriptRoot

$Failures = New-Object System.Collections.ArrayList
function Ok7R1([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Fail7R1([string]$Message) { Write-Host "  [FAIL] $Message" -ForegroundColor Red; [void]$Failures.Add($Message) }
function Assert7R1([bool]$Condition,[string]$Message) { if ($Condition) { Ok7R1 $Message } else { Fail7R1 $Message } }

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 7 R1 / UI Shell & Navigation'
Write-Host '============================================================'
Write-Host 'R1: nova UI, shell principal, navegacao e tema; backend R4.1 protegido'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$baseline = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $baseline.files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R1 $ok "baseline R4.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: backend 230 + presets 105/129/168 ===" -ForegroundColor Yellow
$catalogFiles = @(
    'catalog.json',
    'catalogs\Game-Workload.json',
    'catalogs\validated\Advanced-Catalog.json',
    'catalogs\validated\Expansion-R4.json',
    'catalogs\validated\Expansion-R4.1.json',
    'catalogs\validated\Expansion-R4.2.json'
)
$all = New-Object System.Collections.ArrayList
foreach ($rel in $catalogFiles) {
    $j = Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = if ($j.PSObject.Properties.Name -contains 'tweaks') { @($j.tweaks) } else { @($j) }
    foreach ($x in $items) { [void]$all.Add($x) }
}
$all = @($all.ToArray())
Assert7R1 ($all.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert7R1 ((@($all.id | Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$presets = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert7R1 ([int]$presets.presets.Balanceado.expectedSelectedCount -eq 105) 'preset Balanceado permanece 105'
Assert7R1 ([int]$presets.presets.Gamer.expectedSelectedCount -eq 129) 'preset Gamer permanece 129'
Assert7R1 ([int]$presets.presets.Extremo.expectedSelectedCount -eq 168) 'preset Extremo permanece 168'

Write-Host "`n=== TEST 02: shell XAML valido + tema aprovado ===" -ForegroundColor Yellow
$xamlPath = Join-Path $Root 'src\UI\Fase7\WinSlimShell.xaml'
Assert7R1 (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.xaml existe'
$xamlRaw = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk = $true
try { [xml]$null = $xamlRaw } catch { $xmlOk = $false }
Assert7R1 $xmlOk 'XAML e XML bem-formado'
foreach ($color in @('#080808','#111111','#151515','#FF7A00','#FF9A2E','#C85A00')) {
    Assert7R1 ($xamlRaw -match [regex]::Escape($color)) "tema contem $color"
}
Assert7R1 ($xamlRaw -match 'WindowStyle="None"') 'shell usa janela customizada/borderless'
Assert7R1 ($xamlRaw -match 'Win-Slim Suite' -and $xamlRaw -match 'Windows Optimization Suite') 'branding principal presente'

Write-Host "`n=== TEST 03: navegacao e rotas da nova UI ===" -ForegroundColor Yellow
foreach ($name in @('NavInicio','NavPresets','NavPersonalizado','NavBackup','NavAnalise','NavConfiguracoes','NavSobre')) {
    Assert7R1 ($xamlRaw -match ('x:Name="' + [regex]::Escape($name) + '"')) "navegacao presente: $name"
}
foreach ($page in @('PageInicio','PagePresets','PagePersonalizado','PageBackup','PageAnalise','PageConfiguracoes','PageSobre')) {
    Assert7R1 ($xamlRaw -match ('x:Name="' + [regex]::Escape($page) + '"')) "pagina presente: $page"
}
foreach ($future in @('PagePreview','PageApply','PageResult','PageTweakDetail')) {
    Assert7R1 ($xamlRaw -match ('x:Name="' + [regex]::Escape($future) + '"')) "rota futura reservada: $future"
}

Write-Host "`n=== TEST 04: UI nao possui primitivas de mutacao do Windows ===" -ForegroundColor Yellow
$uiFiles = @(
    (Join-Path $Root 'src\UI\Fase7\WinSlimShell.ps1'),
    (Join-Path $Root 'src\UI\Fase7\WinSlimShell.xaml')
)
$uiRaw = ($uiFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw -Encoding UTF8 }) -join "`n"
$forbidden = @(
    'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe',
    'Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan',
    'Invoke-WinSlimProvider','ApplyHandler','UndoHandler'
)
foreach ($token in $forbidden) {
    Assert7R1 ($uiRaw -notmatch [regex]::Escape($token)) "UI nao executa: $token"
}

Write-Host "`n=== TEST 05: launcher FASE 7 usa runtime promovido ===" -ForegroundColor Yellow
$launcherPath = Join-Path $Root 'WinSlimSuite.Fase7.ps1'
Assert7R1 (Test-Path -LiteralPath $launcherPath) 'WinSlimSuite.Fase7.ps1 existe'
$launcher = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
foreach ($module in @('Planner.ps1','Transaction.ps1','CatalogRuntime.ps1','PresetResolver.ps1','PresetPolicyEngine.ps1','PresetRuntime.ps1','PresetPlannerValidator.ps1','PresetPreview.ps1','PlannerOptimized.ps1','TransactionOptimized.ps1','RuntimePromotion.ps1')) {
    Assert7R1 ($launcher -match [regex]::Escape($module)) "launcher carrega $module"
}
Assert7R1 ($launcher -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'launcher habilita Planner/Transaction promovidos'
Assert7R1 ($launcher -match 'Show-WinSlimFase7Shell') 'launcher entrega controle ao novo shell'

Write-Host "`n=== TEST 06: launcher padrao aponta para a FASE 7 ===" -ForegroundColor Yellow
$bat = Get-Content -LiteralPath (Join-Path $Root 'Executar-WinSlim.bat') -Raw
Assert7R1 ($bat -match 'WinSlimSuite\.Fase7\.ps1') 'Executar-WinSlim.bat abre a nova UI'
Assert7R1 (Test-Path -LiteralPath (Join-Path $Root 'Executar-WinSlim-Legado.bat')) 'launcher legado foi preservado separadamente'

Write-Host "`n=== TEST 07: arquivos R1 registrados ===" -ForegroundColor Yellow
$r1specPath = Join-Path $Root 'specs\FASE7-R1-baseline.json'
Assert7R1 (Test-Path -LiteralPath $r1specPath) 'spec FASE7-R1-baseline.json existe'
if (Test-Path -LiteralPath $r1specPath) {
    $r1spec = Get-Content -LiteralPath $r1specPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $r1spec.r1Files.PSObject.Properties) {
        $path = Join-Path $Root ([string]$p.Name)
        $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
        Assert7R1 $ok "R1 registrado: $($p.Name)"
    }
}

Write-Host "`n=== RESUMO FASE 7 R1 ===" -ForegroundColor Yellow
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 7 R1 APROVADA - nova UI base criada; tema/navegacao ativos; backend R4.1 preservado e sem mutacao direta pela UI.' -ForegroundColor Green
    Write-Host 'Proximo subgate: FASE 7 R2 - Dashboard + hardware/contexto.' -ForegroundColor Cyan
    exit 0
}
Write-Host "FASE 7 R1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1
