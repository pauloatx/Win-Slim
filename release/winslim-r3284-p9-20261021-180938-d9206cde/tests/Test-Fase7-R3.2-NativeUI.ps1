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
Write-Host ' Win-Slim Suite - FASE 7 R3.2 / Native UI Foundation'
Write-Host '============================================================'
Write-Host 'R3.2: host C# WPF nativo + bridge PowerShell persistente read-only; backend aprovado protegido'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$r4spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r4spec.files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "baseline R4.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: FASE 7 R3.1.1 permanece congelada ===" -ForegroundColor Yellow
$r311spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.1.1-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r311spec.r311Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.1.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 02: backend 230 + presets 105/129/168 ===" -ForegroundColor Yellow
$files=@('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')
$all=New-Object System.Collections.ArrayList
foreach($rel in $files){
  $j=Get-Content -LiteralPath (Join-Path $Root $rel) -Raw -Encoding UTF8|ConvertFrom-Json
  $items=if($j.PSObject.Properties.Name -contains 'tweaks'){@($j.tweaks)}else{@($j)}
  foreach($x in $items){[void]$all.Add($x)}
}
$all=@($all.ToArray())
Assert ($all.Count -eq 230) 'backend permanece com exatamente 230 tweaks'
Assert ((@($all.id|Select-Object -Unique).Count) -eq 230) '230 IDs permanecem unicos'
$presetJson=Get-Content -LiteralPath (Join-Path $Root 'presets\WinSlim-Presets-R1.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ([int]$presetJson.presets.Balanceado.expectedSelectedCount -eq 105) 'preset Balanceado permanece 105'
Assert ([int]$presetJson.presets.Gamer.expectedSelectedCount -eq 129) 'preset Gamer permanece 129'
Assert ([int]$presetJson.presets.Extremo.expectedSelectedCount -eq 168) 'preset Extremo permanece 168'

Write-Host "`n=== TEST 03: XAML nativo segue contrato visual oficial ===" -ForegroundColor Yellow
$xamlPath=Join-Path $Root 'src\UI\Native\WinSlimShell.R3_2.xaml'
Assert (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.R3_2.xaml existe'
$x=Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk=$true; try{[xml]$null=$x}catch{$xmlOk=$false}; Assert $xmlOk 'XAML e XML bem-formado'
foreach($color in @('#080808','#111111','#151515','#FF7A00','#FF9A2E','#C85A00')){ Assert ($x -match [regex]::Escape($color)) "tema contem $color" }
Assert ($x -match 'Width="1180" Height="760"') 'janela compacta 1180x760'
Assert ($x -match '<RowDefinition Height="46"') 'title bar compacta de 46 px'
Assert ($x -match '<ColumnDefinition Width="164"') 'sidebar compacta de 164 px'
Assert ($x -match 'AllowsTransparency="False"') 'sem transparencia pesada; composicao WPF aceleravel preservada'
foreach($page in @('PageDashboard','PagePresets','PagePreview','PageApply','PageResult','PageBackup','PageCustom','PageTweakDetail','PageAnalysis','PageSettings','PageAbout')){ Assert ($x -match ('x:Name="'+$page+'"')) "pagina nativa presente: $page" }
foreach($control in @('CardPresetBalanced','CardPresetGamer','CardPresetExtreme','BtnPresetBalanced','BtnPresetGamer','BtnPresetExtreme','HighRiskBanner','BtnGrantHighRisk','BtnPreviewFromPreset')){ Assert ($x -match ('x:Name="'+$control+'"')) "controle Presets presente: $control" }
$overlayNames=@('OverlayHags','OverlayMsiGpu','OverlayCoreParking','OverlayGpuIrq','OverlayCs2PCores','OverlayValorant','OverlayCs2','OverlayApex','OverlayFortnite','OverlayGtav','OverlayFso','OverlayStreaming','OverlayVideo','OverlayDesign','OverlayProgramming','OverlayDefenderDev')
foreach($name in $overlayNames){ Assert ($x -match ('x:Name="'+$name+'"')) "overlay interativo presente: $name" }
Assert (($x | Select-String -Pattern 'Style="\{StaticResource OverlayChip\}"|Style="\{StaticResource HighRiskChip\}"' -AllMatches).Matches.Count -eq 16) 'exatamente 16 chips/toggles condicionais no layout'

Write-Host "`n=== TEST 04: Native UI moderna, leve e sem mutacao direta ===" -ForegroundColor Yellow
$nativeFiles=@('src\UI\Native\Program.cs','src\UI\Native\BridgeClient.cs','src\UI\Native\MainWindowController.cs','src\UI\Native\WinSlimShell.R3_2.xaml')
foreach($rel in $nativeFiles){ Assert (Test-Path -LiteralPath (Join-Path $Root $rel)) "arquivo Native UI existe: $rel" }
$nativeText=($nativeFiles | ForEach-Object { Get-Content -LiteralPath (Join-Path $Root $_) -Raw -Encoding UTF8 }) -join "`n"
$forbidden=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe','Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler','Invoke-WinSlimTransactionOptimized','New-WinSlimPresetPreview','Invoke-WinSlimPresetRuntimePlannerValidation')
foreach($token in $forbidden){ Assert ($nativeText -notmatch [regex]::Escape($token)) "Native UI nao executa: $token" }
Assert ($nativeText -match 'WindowChrome') 'WindowChrome nativo para resize/desktop ergonomics'
Assert ($nativeText -match 'DwmSetWindowAttribute') 'integra DWM para visual moderno quando suportado'
Assert ($nativeText -match 'DoubleAnimation') 'transicoes por animacao WPF nativa'
Assert ($nativeText -match 'TimeSpan\.FromMilliseconds\(160\)') 'transicao de pagina curta/leve (~160 ms)'
Assert ($nativeText -match 'DispatcherTimer') 'metricas usam DispatcherTimer controlado'
Assert ($nativeText -match 'TimeSpan\.FromSeconds\(3\)') 'metricas limitadas a intervalo de 3 segundos'
Assert ($nativeText -match 'WindowState == WindowState\.Minimized') 'coleta de metricas pausa quando minimizado'
Assert ($nativeText -match '_currentPage, "Dashboard"') 'coleta de metricas ocorre somente no Dashboard'
Assert ($nativeText -notmatch 'Thread\.Sleep') 'nenhum bloqueio Thread.Sleep na UI'

Write-Host "`n=== TEST 05: bridge persistente e somente leitura ===" -ForegroundColor Yellow
$bridgePath=Join-Path $Root 'src\UI\Native\WinSlim.UiBridge.R3_2.ps1'
Assert (Test-Path -LiteralPath $bridgePath) 'WinSlim.UiBridge.R3_2.ps1 existe'
$b=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8
Assert ($b -match '\[switch\]\$Server') 'bridge possui modo servidor persistente'
foreach($action in @('handshake','snapshot','performance','overlays','resolvepreset')){ Assert ($b -match ("'"+$action+"'")) "bridge expoe acao read-only: $action" }
Assert ($b -match 'Enable-WinSlimRuntimePromotion\s+-Planner\s+-Transaction') 'bridge carrega runtime promovido aprovado'
Assert ($b -match 'Resolve-WinSlimPresetRuntimeSelection') 'bridge usa resolver canonico de presets'
foreach($token in $forbidden){ Assert ($b -notmatch [regex]::Escape($token)) "bridge nao executa: $token" }
Assert ($b -notmatch 'Invoke-WinSlimPresetRuntimePlannerValidation') 'R3.2 nao antecipa Planner validation'
Assert ($b -notmatch 'New-WinSlimPresetPreview') 'R3.2 nao antecipa Preview transacional'
Assert ($b -notmatch 'Invoke-WinSlimTransactionOptimized') 'R3.2 nao inicia Transaction'

Write-Host "`n=== TEST 06: bridge real resolve preset/overlay sem Apply ===" -ForegroundColor Yellow
try{
  $handshakeRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action Handshake -RootPath $Root
  $handshake=$handshakeRaw|ConvertFrom-Json
  Assert ([int]$handshake.backendCount -eq 230) 'handshake real retorna backend 230'
  Assert ([bool]$handshake.readOnly) 'handshake declara bridge read-only'
  Assert ([bool]$handshake.plannerPromoted) 'Planner promovido no bridge real'
  Assert ([bool]$handshake.transactionPromoted) 'Transaction promovido no bridge real'

  $resolveRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["HW-HAGS-ON"]'
  $resolved=$resolveRaw|ConvertFrom-Json
  Assert ([int]$resolved.baseCount -eq 129) 'Gamer real preserva base 129'
  Assert ([int]$resolved.enabledOverlayCount -eq 1) 'HAGS real habilita exatamente 1 overlay'
  Assert ([int]$resolved.selectedCount -eq 130) 'Gamer + HAGS resulta 130 tweaks'
  Assert ([bool]$resolved.canResolve) 'Gamer + HAGS resolve sem bloqueio'

  $highRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["HW-GPU-IRQ-AFFINITY"]'
  $high=$highRaw|ConvertFrom-Json
  Assert (-not [bool]$high.canResolve) 'overlay Alto sem consentimento permanece bloqueado'
  Assert (@($high.blockedRequests|Where-Object{$_.code -eq 'HighRiskConsentRequired'}).Count -eq 1) 'bloqueio Alto usa contrato HighRiskConsentRequired'
}catch{
  Fail ("bridge real falhou: "+$_.Exception.Message)
}

Write-Host "`n=== TEST 07: build C# WPF nativo com toolchain do Windows ===" -ForegroundColor Yellow
$buildPath=Join-Path $Root 'Build-NativeUI-R3.2.ps1'
Assert (Test-Path -LiteralPath $buildPath) 'Build-NativeUI-R3.2.ps1 existe'
$buildProcess=$null
try{
  $buildProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',"`"$buildPath`"") -WorkingDirectory $Root -Wait -PassThru -WindowStyle Hidden
  Assert ($buildProcess.ExitCode -eq 0) 'compilacao Native UI retorna exit code 0'
}catch{ Fail ("falha ao executar build Native UI: "+$_.Exception.Message) }
$exe=Join-Path $Root 'bin\WinSlim.UI.Native.R3.2.exe'
Assert (Test-Path -LiteralPath $exe) 'WinSlim.UI.Native.R3.2.exe foi gerado'
Assert (Test-Path -LiteralPath ($exe+'.config')) 'config .NET Framework/DPI acompanha o executavel'

Write-Host "`n=== TEST 08: self-test do executavel compila XAML + conversa com bridge ===" -ForegroundColor Yellow
if(Test-Path -LiteralPath $exe){
  $self=Join-Path $env:TEMP ('winslim-native-selftest-'+[guid]::NewGuid().ToString('N')+'.json')
  try{
    $proc=Start-Process -FilePath $exe -ArgumentList @('--root',"`"$Root`"",'--self-test',"`"$self`"") -WorkingDirectory $Root -Wait -PassThru
    Assert ($proc.ExitCode -eq 0) 'executavel self-test retorna exit code 0'
    Assert (Test-Path -LiteralPath $self) 'executavel produz resultado do self-test'
    if(Test-Path -LiteralPath $self){
      $sj=Get-Content -LiteralPath $self -Raw -Encoding UTF8|ConvertFrom-Json
      Assert ([bool]$sj.ok) 'self-test do executavel reporta OK'
      Assert ([bool]$sj.xamlLoaded) 'XAML foi carregado pelo runtime WPF real'
      Assert ([int]$sj.backendCount -eq 230) 'executavel enxerga backend 230 pelo bridge'
      Assert ([string]$sj.bridgeVersion -eq '7.3.2') 'executavel conversa com bridge R3.2'
    }
  }catch{ Fail ("self-test executavel falhou: "+$_.Exception.Message) }
  finally{ Remove-Item -LiteralPath $self -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n=== TEST 09: arquivos R3.2 registrados ===" -ForegroundColor Yellow
$specPath=Join-Path $Root 'specs\FASE7-R3.2-baseline.json'
Assert (Test-Path -LiteralPath $specPath) 'spec R3.2 existe'
if(Test-Path -LiteralPath $specPath){
  $spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($q in $spec.r32Files.PSObject.Properties){
    $path=Join-Path $Root ([string]$q.Name)
    $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$q.Value).ToLowerInvariant())
    Assert $ok "R3.2 registrado: $($q.Name)"
  }
}

Write-Host "`n=== RESUMO FASE 7 R3.2 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
  Write-Host 'FASE 7 R3.2 APROVADA - Native UI C# WPF compilada; bridge read-only funcional; overlays interativos; backend R4.1/R3.1.1 preservados.' -ForegroundColor Green
  Write-Host 'Abra Executar-WinSlim-R3.2.bat e valide visualmente Presets, transicoes e os prototipos das demais telas.' -ForegroundColor Cyan
  exit 0
}
Write-Host "FASE 7 R3.2 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1
