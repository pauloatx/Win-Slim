#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Root = Split-Path -Parent $PSScriptRoot

$Failures = New-Object System.Collections.ArrayList
function Ok7R2([string]$Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Fail7R2([string]$Message) { Write-Host "  [FAIL] $Message" -ForegroundColor Red; [void]$Failures.Add($Message) }
function Assert7R2([bool]$Condition,[string]$Message) { if ($Condition) { Ok7R2 $Message } else { Fail7R2 $Message } }

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 7 R2 / Dashboard + Hardware Context'
Write-Host '============================================================'
Write-Host 'R2: dashboard real + diagnostico read-only; backend R4.1 e R1 protegidos'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$baseline = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $baseline.files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R2 $ok "baseline R4.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: FASE 7 R1 permanece byte-a-byte congelada ===" -ForegroundColor Yellow
$r1spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R1-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($p in $r1spec.r1Files.PSObject.Properties) {
    $path = Join-Path $Root ([string]$p.Name)
    $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
    Assert7R2 $ok "R1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 02: backend 230 + presets 105/129/168 ===" -ForegroundColor Yellow
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
Assert7R2 ($all.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert7R2 ((@($all.id | Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$presets = Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Assert7R2 ([int]$presets.presets.Balanceado.expectedSelectedCount -eq 105) 'preset Balanceado permanece 105'
Assert7R2 ([int]$presets.presets.Gamer.expectedSelectedCount -eq 129) 'preset Gamer permanece 129'
Assert7R2 ([int]$presets.presets.Extremo.expectedSelectedCount -eq 168) 'preset Extremo permanece 168'

Write-Host "`n=== TEST 03: coletor R2 existe e e somente leitura ===" -ForegroundColor Yellow
$contextPath = Join-Path $Root 'src\UI\Fase7\SystemContextView.R2.ps1'
Assert7R2 (Test-Path -LiteralPath $contextPath) 'SystemContextView.R2.ps1 existe'
$contextRaw = Get-Content -LiteralPath $contextPath -Raw -Encoding UTF8
foreach ($functionName in @('Get-WinSlimUiSystemSnapshot','Get-WinSlimUiPerformanceSnapshot','Get-WinSlimStorageDescriptor','Get-WinSlimDeviceType')) {
    Assert7R2 ($contextRaw -match ('function\s+' + [regex]::Escape($functionName))) "coletor implementa $functionName"
}
foreach ($probe in @('Win32_OperatingSystem','Win32_Processor','Win32_VideoController','Win32_ComputerSystem','MSFT_PhysicalDisk','Confirm-SecureBootUEFI','Get-Tpm','Win32_DeviceGuard','Get-BitLockerVolume','Get-NetAdapter')) {
    Assert7R2 ($contextRaw -match [regex]::Escape($probe)) "coletor possui leitura: $probe"
}
$forbidden = @(
    'Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe',
    'Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh',
    'Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler'
)
foreach ($token in $forbidden) {
    Assert7R2 ($contextRaw -notmatch [regex]::Escape($token)) "coletor nao executa: $token"
}

Write-Host "`n=== TEST 04: XAML R2 valido + Dashboard conectado ===" -ForegroundColor Yellow
$xamlPath = Join-Path $Root 'src\UI\Fase7\WinSlimShell.R2.xaml'
Assert7R2 (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.R2.xaml existe'
$xamlRaw = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk = $true
try { [xml]$null = $xamlRaw } catch { $xmlOk = $false }
Assert7R2 $xmlOk 'XAML R2 e XML bem-formado'
foreach ($color in @('#080808','#111111','#151515','#FF7A00','#FF9A2E','#C85A00')) {
    Assert7R2 ($xamlRaw -match [regex]::Escape($color)) "tema R2 contem $color"
}
foreach ($control in @(
    'TxtSystemPrimary','TxtSystemSecondary','TxtSystemHardware','TxtDeviceType','TxtCompatibilityBadge','TxtAdminBadge',
    'TxtPendingReboot','TxtMetricCpu','TxtMetricGpu','TxtMetricRam','TxtMetricDisk','TxtMetricTimestamp',
    'BtnAnalyzeSystem','BtnRefreshDashboard','BtnRefreshSystem',
    'TxtAnalysisWindows','TxtAnalysisArch','TxtAnalysisCpu','TxtAnalysisGpu','TxtAnalysisGpuDriver','TxtAnalysisRam',
    'TxtAnalysisStorage','TxtAnalysisDevice','TxtAnalysisAdmin','TxtAnalysisSecureBoot','TxtAnalysisTpm','TxtAnalysisVbs',
    'TxtAnalysisHvci','TxtAnalysisBitLocker','TxtAnalysisReboot','TxtAnalysisNetwork','TxtAnalysisPower','TxtAnalysisSummary','TxtAnalysisTime'
)) {
    Assert7R2 ($xamlRaw -match ('x:Name="' + [regex]::Escape($control) + '"')) "controle R2 presente: $control"
}
Assert7R2 ($xamlRaw -match '7 R2 · Dashboard') 'Dashboard identifica FASE 7 R2'
Assert7R2 ($xamlRaw -match 'somente leitura') 'Analise explicita modo somente leitura'

Write-Host "`n=== TEST 05: shell R2 liga snapshot + metricas sem Apply ===" -ForegroundColor Yellow
$shellPath = Join-Path $Root 'src\UI\Fase7\WinSlimShell.R2.ps1'
Assert7R2 (Test-Path -LiteralPath $shellPath) 'WinSlimShell.R2.ps1 existe'
$shellRaw = Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
Assert7R2 ($shellRaw -match 'Get-WinSlimUiSystemSnapshot') 'shell R2 consome snapshot real'
Assert7R2 ($shellRaw -match 'Get-WinSlimUiPerformanceSnapshot') 'shell R2 consome metricas reais'
Assert7R2 ($shellRaw -match 'DispatcherTimer') 'shell R2 possui atualizacao periodica'
Assert7R2 ($shellRaw -match 'FromSeconds\(3\)') 'intervalo de metricas permanece 3 segundos'
Assert7R2 ($shellRaw -match 'BtnRefreshSystem' -and $shellRaw -match 'BtnRefreshDashboard') 'refresh manual conectado'
foreach ($token in $forbidden) {
    Assert7R2 ($shellRaw -notmatch [regex]::Escape($token)) "shell R2 nao executa: $token"
}

Write-Host "`n=== TEST 06: launcher R2 usa runtime promovido + UI R2 ===" -ForegroundColor Yellow
$launcherPath = Join-Path $Root 'WinSlimSuite.Fase7R2.ps1'
Assert7R2 (Test-Path -LiteralPath $launcherPath) 'WinSlimSuite.Fase7R2.ps1 existe'
$launcher = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
foreach ($module in @('Planner.ps1','Transaction.ps1','CatalogRuntime.ps1','PresetResolver.ps1','PresetPolicyEngine.ps1','PresetRuntime.ps1','PresetPlannerValidator.ps1','PresetPreview.ps1','PlannerOptimized.ps1','TransactionOptimized.ps1','RuntimePromotion.ps1')) {
    Assert7R2 ($launcher -match [regex]::Escape($module)) "launcher R2 carrega $module"
}
Assert7R2 ($launcher -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'launcher R2 habilita Planner/Transaction promovidos'
Assert7R2 ($launcher -match 'SystemContextView\.R2\.ps1') 'launcher R2 carrega leitor de contexto'
Assert7R2 ($launcher -match 'WinSlimShell\.R2\.ps1') 'launcher R2 carrega shell R2'

Write-Host "`n=== TEST 07: entrypoint R2 separado preserva R1 ===" -ForegroundColor Yellow
$r2batPath = Join-Path $Root 'Executar-WinSlim-R2.bat'
Assert7R2 (Test-Path -LiteralPath $r2batPath) 'Executar-WinSlim-R2.bat existe'
$r2bat = Get-Content -LiteralPath $r2batPath -Raw
Assert7R2 ($r2bat -match 'WinSlimSuite\.Fase7R2\.ps1') 'entrypoint R2 abre launcher R2'
$r1bat = Get-Content -LiteralPath (Join-Path $Root 'Executar-WinSlim.bat') -Raw
Assert7R2 ($r1bat -match 'WinSlimSuite\.Fase7\.ps1') 'entrypoint R1 original permanece intacto'

Write-Host "`n=== TEST 08: arquivos R2 registrados ===" -ForegroundColor Yellow
$r2specPath = Join-Path $Root 'specs\FASE7-R2-baseline.json'
Assert7R2 (Test-Path -LiteralPath $r2specPath) 'spec FASE7-R2-baseline.json existe'
if (Test-Path -LiteralPath $r2specPath) {
    $r2spec = Get-Content -LiteralPath $r2specPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($p in $r2spec.r2Files.PSObject.Properties) {
        $path = Join-Path $Root ([string]$p.Name)
        $ok = (Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
        Assert7R2 $ok "R2 registrado: $($p.Name)"
    }
}

Write-Host "`n=== RESUMO FASE 7 R2 ===" -ForegroundColor Yellow
if ($Failures.Count -eq 0) {
    Write-Host 'FASE 7 R2 APROVADA - Dashboard e Analise usam hardware/contexto real em modo read-only; R1 e backend R4.1 preservados.' -ForegroundColor Green
    Write-Host 'Proximo subgate: FASE 7 R3 - Presets + overlays condicionais.' -ForegroundColor Cyan
    exit 0
}
Write-Host "FASE 7 R2 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach ($f in $Failures) { Write-Host " - $f" -ForegroundColor Red }
exit 1
