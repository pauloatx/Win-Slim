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
Write-Host ' Win-Slim Suite - FASE 7 R3.1.1 / WPF Runtime Scope Hotfix'
Write-Host '============================================================'
Write-Host 'R3.1.1: corrige escopo de helpers WPF; layout R3.1 e backend permanecem congelados'

Write-Host "`n=== TEST 00: FASE 7 R3.1 permanece byte-a-byte congelada ===" -ForegroundColor Yellow
$r31spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.1-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r31spec.r31Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: backend e presets continuam aprovados ===" -ForegroundColor Yellow
$files=@('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')
$all=New-Object System.Collections.ArrayList
foreach($rel in $files){
  $j=Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8|ConvertFrom-Json
  $items=if($j.PSObject.Properties.Name -contains 'tweaks'){@($j.tweaks)}else{@($j)}
  foreach($x in $items){[void]$all.Add($x)}
}
$all=@($all.ToArray())
Assert ($all.Count -eq 230) 'backend permanece 230'
Assert ((@($all.id|Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$p=Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ([int]$p.presets.Balanceado.expectedSelectedCount -eq 105) 'Balanceado permanece 105'
Assert ([int]$p.presets.Gamer.expectedSelectedCount -eq 129) 'Gamer permanece 129'
Assert ([int]$p.presets.Extremo.expectedSelectedCount -eq 168) 'Extremo permanece 168'

Write-Host "`n=== TEST 02: layout R3.1 permanece exatamente igual ===" -ForegroundColor Yellow
$xamlPath=Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3_1.xaml'
Assert (Test-Path -LiteralPath $xamlPath) 'XAML R3.1 preservado'
$x=Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk=$true; try{[xml]$null=$x}catch{$xmlOk=$false}; Assert $xmlOk 'XAML permanece XML bem-formado'
Assert ($x -match 'Width="1080" Height="700"') 'janela compacta 1080x700 preservada'
Assert ($x -match '<RowDefinition Height="38"') 'title bar compacta preservada'
Assert ($x -match '<ColumnDefinition Width="148"') 'sidebar compacta preservada'

Write-Host "`n=== TEST 03: hotfix elimina helpers locais invisiveis aos eventos WPF ===" -ForegroundColor Yellow
$shellPath=Join-Path $Root 'src\UI\Fase7\WinSlimShell.R3_1_1.ps1'
Assert (Test-Path -LiteralPath $shellPath) 'WinSlimShell.R3_1_1.ps1 existe'
$s=Get-Content -LiteralPath $shellPath -Raw -Encoding UTF8

$requiredHelpers=@(
 'Set-WinSlimR311ControlText',
 'Set-WinSlimR311View',
 'Format-WinSlimR311Metric',
 'Get-WinSlimR311ShortText',
 'Get-WinSlimR311SelectedConditionalProfiles',
 'Set-WinSlimR311PresetCardState',
 'Update-WinSlimR311OverlayEligibility',
 'Update-WinSlimR311PresetSelection',
 'Select-WinSlimR311PresetUi',
 'Show-WinSlimFase7ShellR311'
)
foreach($name in $requiredHelpers){ Assert ($s -match ('(?m)^function\s+'+[regex]::Escape($name)+'\s*\{')) "helper top-level presente: $name" }

# O bug da R3.1 era de dynamic scope: Set-WinSlimControlText existia somente dentro de Show-WinSlimFase7Shell.
# Agora nenhum helper R311 pode estar aninhado dentro do corpo de Show-WinSlimFase7ShellR311.
$showIndex=$s.IndexOf('function Show-WinSlimFase7ShellR311')
$showText=if($showIndex -ge 0){$s.Substring($showIndex)}else{''}
Assert ($showText -notmatch '(?m)^\s+function\s+(Set|Get|Update|Select|Format)-WinSlimR311') 'nenhum helper R311 esta aninhado no Show'
Assert ($s -notmatch '(?m)\bSet-WinSlimControlText\b') 'helper antigo de escopo local nao e usado'
Assert ($s -match 'Add_ContentRendered\(\(\{[^}]*Update-WinSlimR311OverlayEligibility' -or $s -match 'Add_ContentRendered') 'ContentRendered usa caminho R311'
Assert ($s -match '\$script:WinSlimFase7PresetRuntime\s*=\s*\$PresetRuntime') 'PresetRuntime fica acessivel aos callbacks'
Assert ($s -match '\$script:WinSlimFase7OverlayControlMap\s*=\s*\$overlayControlMap') 'mapa de overlays fica acessivel aos callbacks'

Write-Host "`n=== TEST 04: helpers sao comandos visiveis apos dot-source ===" -ForegroundColor Yellow
. $shellPath
foreach($name in $requiredHelpers){
  $cmd=Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
  Assert ($null -ne $cmd) "Get-Command encontra: $name"
}

Write-Host "`n=== TEST 05: shell continua sem primitivas de mutacao ===" -ForegroundColor Yellow
$forbidden=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe','Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler')
foreach($token in $forbidden){ Assert ($s -notmatch [regex]::Escape($token)) "shell nao executa: $token" }
Assert ($s -match 'Resolve-WinSlimPresetRuntimeSelection') 'resolver canonico de presets preservado'
Assert ($s -match 'Get-WinSlimUiSystemSnapshot') 'coletor R2 permanece conectado'
Assert ($s -match 'Get-WinSlimUiPerformanceSnapshot') 'metricas R2 permanecem conectadas'

Write-Host "`n=== TEST 06: launcher/entrypoint R3.1.1 usam o shell corrigido ===" -ForegroundColor Yellow
$lpath=Join-Path $Root 'WinSlimSuite.Fase7R3_1_1.ps1'
Assert (Test-Path -LiteralPath $lpath) 'launcher R3.1.1 existe'
$l=Get-Content -LiteralPath $lpath -Raw -Encoding UTF8
Assert ($l -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'runtime promovido preservado'
Assert ($l -match 'SystemContextView\.R2\.ps1') 'coletor R2 preservado'
Assert ($l -match 'PresetOverlayView\.R3\.ps1') 'view-model R3 preservado'
Assert ($l -match 'WinSlimShell\.R3_1_1\.ps1') 'launcher carrega shell hotfix'
Assert ($l -match 'Show-WinSlimFase7ShellR311') 'launcher chama funcao hotfix'
$bat=Get-Content -LiteralPath (Join-Path $Root 'Executar-WinSlim-R3.1.1.bat') -Raw
Assert ($bat -match 'WinSlimSuite\.Fase7R3_1_1\.ps1') 'entrypoint R3.1.1 correto'

Write-Host "`n=== TEST 07: arquivos R3.1.1 registrados ===" -ForegroundColor Yellow
$specPath=Join-Path $Root 'specs\FASE7-R3.1.1-baseline.json'
Assert (Test-Path -LiteralPath $specPath) 'spec R3.1.1 existe'
if(Test-Path -LiteralPath $specPath){
  $spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($q in $spec.r311Files.PSObject.Properties){
    $path=Join-Path $Root ([string]$q.Name)
    $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$q.Value).ToLowerInvariant())
    Assert $ok "R3.1.1 registrado: $($q.Name)"
  }
}

Write-Host "`n=== RESUMO FASE 7 R3.1.1 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
  Write-Host 'FASE 7 R3.1.1 APROVADA - hotfix de escopo WPF aplicado; layout R3.1, R3 e backend preservados.' -ForegroundColor Green
  Write-Host 'Abra Executar-WinSlim-R3.1.1.bat e valide visualmente a janela.' -ForegroundColor Cyan
  exit 0
}
Write-Host "FASE 7 R3.1.1 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1
