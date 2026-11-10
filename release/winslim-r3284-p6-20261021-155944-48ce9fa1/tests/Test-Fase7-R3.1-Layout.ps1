#requires -Version 5.1
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$Root = Split-Path -Parent $PSScriptRoot
$Failures = New-Object System.Collections.ArrayList
function Ok([string]$m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail([string]$m){ Write-Host "  [FAIL] $m" -ForegroundColor Red; [void]$Failures.Add($m) }
function Assert([bool]$c,[string]$m){ if($c){Ok $m}else{Fail $m} }

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 7 R3.1 / Layout Reference Correction'
Write-Host '============================================================'
Write-Host 'R3.1: correcao visual; R3/backend preservados; nenhuma mutacao nova'

Write-Host "`n=== TEST 00: FASE 7 R3 permanece byte-a-byte congelada ===" -ForegroundColor Yellow
$r3spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r3spec.r3Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: backend e presets continuam aprovados ===" -ForegroundColor Yellow
$files=@('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')
$all=New-Object System.Collections.ArrayList
foreach($rel in $files){ $j=Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8|ConvertFrom-Json; $items=if($j.PSObject.Properties.Name -contains 'tweaks'){@($j.tweaks)}else{@($j)}; foreach($x in $items){[void]$all.Add($x)} }
$all=@($all.ToArray())
Assert ($all.Count -eq 230) 'backend permanece 230'
Assert ((@($all.id|Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$p=Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ([int]$p.presets.Balanceado.expectedSelectedCount -eq 105) 'Balanceado permanece 105'
Assert ([int]$p.presets.Gamer.expectedSelectedCount -eq 129) 'Gamer permanece 129'
Assert ([int]$p.presets.Extremo.expectedSelectedCount -eq 168) 'Extremo permanece 168'

Write-Host "`n=== TEST 02: layout compacto corresponde a referencia ===" -ForegroundColor Yellow
$xamlPath=Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3_1.xaml'
Assert (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.R3_1.xaml existe'
$x=Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk=$true; try{[xml]$null=$x}catch{$xmlOk=$false}; Assert $xmlOk 'XAML R3.1 e XML bem-formado'
Assert ($x -match 'Width="1080" Height="700"') 'janela usa proporcao compacta da referencia'
Assert ($x -match '<RowDefinition Height="38"') 'title bar compacta de 38 px'
Assert ($x -match '<ColumnDefinition Width="148"') 'sidebar compacta de 148 px'
Assert ($x -notmatch 'Mais desempenho\.') 'banner promocional externo nao foi incorporado ao app'
Assert ($x -notmatch 'Backup automático') 'selos da prancha externa nao ocupam a title bar'
Assert ($x -match 'Dashboard') 'layout Dashboard presente'
Assert ($x -match 'Status do Win-Slim') 'painel Status do Win-Slim presente'
Assert ($x -match 'Desempenho atual') 'painel Desempenho atual presente'
Assert ($x -match 'CardPresetBalanced' -and $x -match 'CardPresetGamer' -and $x -match 'CardPresetExtreme') 'tres cards de presets presentes'
Assert ($x -match 'PanelOverlaysHost' -and $x -match 'Visibility="Collapsed"') 'overlays ficam em gaveta para nao deformar layout principal'
foreach($page in @('PageInicio','PagePresets','PagePreview','PageApply','PageResult','PageBackup','PagePersonalizado','PageTweakDetail','PageAnalise','PageConfiguracoes')){ Assert ($x -match ('x:Name="'+[regex]::Escape($page)+'"')) "tela de referencia presente: $page" }

Write-Host "`n=== TEST 03: controles funcionais R2/R3 continuam presentes ===" -ForegroundColor Yellow
$required=@('TxtSystemPrimary','TxtSystemSecondary','TxtSystemHardware','TxtDeviceType','TxtCompatibilityBadge','TxtAdminBadge','TxtPendingReboot','TxtMetricCpu','TxtMetricGpu','TxtMetricRam','TxtMetricDisk','TxtMetricTimestamp','BtnAnalyzeSystem','BtnRefreshDashboard','BtnRefreshSystem','TxtAnalysisWindows','TxtAnalysisArch','TxtAnalysisCpu','TxtAnalysisGpu','TxtAnalysisGpuDriver','TxtAnalysisRam','TxtAnalysisStorage','TxtAnalysisDevice','TxtAnalysisAdmin','TxtAnalysisSecureBoot','TxtAnalysisTpm','TxtAnalysisVbs','TxtAnalysisHvci','TxtAnalysisBitLocker','TxtAnalysisReboot','TxtAnalysisNetwork','TxtAnalysisPower','TxtAnalysisSummary','TxtAnalysisTime','PanelOverlays','ChkOverlayHags','ChkOverlayMsiGpu','ChkOverlayCoreParking','ChkOverlayCs2PCores','ChkOverlayGpuIrq','ChkOverlayValorant','ChkOverlayCs2','ChkOverlayApex','ChkOverlayFortnite','ChkOverlayGtav','ChkOverlayFso','ChkOverlayDefenderDev','ChkOverlayStreaming','ChkOverlayVideo','ChkOverlayDesign','ChkOverlayProgramming','ChkAllowHighRiskConditional','TxtPresetSelectionStatus','TxtPresetSelectionDetail','TxtPresetSelectionFingerprint','BtnClearOverlays','BtnPresetNext')
foreach($name in $required){ Assert ($x -match ('x:Name="'+[regex]::Escape($name)+'"')) "controle preservado: $name" }

Write-Host "`n=== TEST 04: shell R3.1 preserva arquitetura sem mutacao ===" -ForegroundColor Yellow
$shellPath=Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3_1.ps1'; Assert (Test-Path -LiteralPath $shellPath) 'WinSlimShell.R3_1.ps1 existe'
$s=Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8
Assert ($s -match 'Resolve-WinSlimPresetRuntimeSelection') 'resolver canonico de presets preservado'
Assert ($s -match 'PanelOverlaysHost') 'gaveta de overlays ligada pelo shell'
$forbidden=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe','Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler')
foreach($token in $forbidden){ Assert ($s -notmatch [regex]::Escape($token)) "shell nao executa: $token" }

Write-Host "`n=== TEST 05: launcher R3.1 usa backend promovido ===" -ForegroundColor Yellow
$lpath=Join-Path $Root 'WinSlimSuite.Fase7R3_1.ps1'; Assert (Test-Path -LiteralPath $lpath) 'launcher R3.1 existe'
$l=Get-Content -LiteralPath $lpath -Raw -Encoding UTF8
Assert ($l -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'runtime promovido preservado'
Assert ($l -match 'SystemContextView\.R2\.ps1') 'coletor R2 preservado'
Assert ($l -match 'PresetOverlayView\.R3\.ps1') 'view-model R3 preservado'
Assert ($l -match 'WinSlimShell\.R3_1\.ps1') 'launcher usa shell visual R3.1'
$bat=Get-Content -LiteralPath (Join-Path $Root 'Executar-WinSlim-R3.1.bat') -Raw
Assert ($bat -match 'WinSlimSuite\.Fase7R3_1\.ps1') 'entrypoint R3.1 correto'

Write-Host "`n=== TEST 06: arquivos R3.1 registrados ===" -ForegroundColor Yellow
$specPath=Join-Path $Root 'specs\FASE7-R3.1-baseline.json'; Assert (Test-Path -LiteralPath $specPath) 'spec R3.1 existe'
if(Test-Path -LiteralPath $specPath){ $spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json; foreach($q in $spec.r31Files.PSObject.Properties){ $path=Join-Path $Root ([string]$q.Name); $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$q.Value).ToLowerInvariant()); Assert $ok "R3.1 registrado: $($q.Name)" } }

Write-Host "`n=== RESUMO FASE 7 R3.1 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){ Write-Host 'FASE 7 R3.1 APROVADA - layout corrigido para reproduzir as telas internas da referencia; R3/backend preservados.' -ForegroundColor Green; Write-Host 'Depois da validacao visual, seguir para FASE 7 R4 - Catalogo Personalizado.' -ForegroundColor Cyan; exit 0 }
Write-Host "FASE 7 R3.1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}; exit 1
