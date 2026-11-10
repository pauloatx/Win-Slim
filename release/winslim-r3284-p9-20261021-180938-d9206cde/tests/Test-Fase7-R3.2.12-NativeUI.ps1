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
Write-Host ' Win-Slim Suite - FASE 7 R3.2.12 / Dashboard / Read-only'
Write-Host '============================================================'
Write-Host 'R3.2.12: build com diagnostico preservado; validacao tecnica nao substitui abertura e aprovacao visual.'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$r4spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r4spec.files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "baseline R4.1 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01: FASE 7 R3.2.5 permanece byte-a-byte congelada ===" -ForegroundColor Yellow
$r325spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.5-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r325spec.r325Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.5 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01B: R3.2.6 permanece congelada ===" -ForegroundColor Yellow
$r326spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.6-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r326spec.r326Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.6 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01C: R3.2.7 permanece congelada ===" -ForegroundColor Yellow
$r327spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.7-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r327spec.r327Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.7 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01D: R3.2.8 permanece congelada ===" -ForegroundColor Yellow
$r328spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.8-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r328spec.r328Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.8 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01E: R3.2.9 permanece congelada ===" -ForegroundColor Yellow
$r329spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.9-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r329spec.r329Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.9 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01F: R3.2.10 permanece congelada ===" -ForegroundColor Yellow
$previousSpec=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.10-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec.r3210Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.10 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 01G: R3.2.11 permanece congelada ===" -ForegroundColor Yellow
$previousSpec11=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.11-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec11.r3211Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.11 congelada: $($p.Name)"
}

Write-Host "`n=== TEST 02: backend 230 + presets 105/129/168 ===" -ForegroundColor Yellow
$catalogFiles=@('catalog.json','catalogs\Game-Workload.json','catalogs\validated\Advanced-Catalog.json','catalogs\validated\Expansion-R4.json','catalogs\validated\Expansion-R4.1.json','catalogs\validated\Expansion-R4.2.json')
$all=New-Object System.Collections.ArrayList
foreach($rel in $catalogFiles){
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

Write-Host "`n=== TEST 03: XAML R3.2.12 segue contrato visual + exatamente 16 overlays ===" -ForegroundColor Yellow
$nativeDir=Join-Path $Root 'src\UI\Native\R3_2_12'
$xamlPath=Join-Path $nativeDir 'WinSlimShell.xaml'
Assert (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.xaml R3.2.12 existe'
$x=Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
$xmlOk=$true; try{[xml]$null=$x}catch{$xmlOk=$false}; Assert $xmlOk 'XAML R3.2.12 e XML bem-formado'
foreach($color in @('#080808','#111111','#151515','#FF7A00','#FF9A2E','#C85A00')){ Assert ($x -match [regex]::Escape($color)) "tema contem $color" }
Assert ($x -match 'Width="1180" Height="760"') 'janela compacta 1180x760'
Assert ($x -match '<RowDefinition Height="46"') 'title bar compacta de 46 px'
Assert ($x -match '<ColumnDefinition Width="164"') 'sidebar compacta de 164 px'
Assert ($x -match 'AllowsTransparency="False"') 'sem transparencia pesada'
foreach($page in @('PageDashboard','PagePresets','PagePreview','PageApply','PageResult','PageBackup','PageCustom','PageTweakDetail','PageAnalysis','PageSettings','PageAbout')){ Assert ($x -match ('x:Name="'+$page+'"')) "pagina nativa presente: $page" }
$overlayNames=@('OverlayHags','OverlayMsiGpu','OverlayCoreParking','OverlayGpuIrq','OverlayCs2PCores','OverlayValorant','OverlayCs2','OverlayApex','OverlayFortnite','OverlayGtav','OverlayFso','OverlayStreaming','OverlayVideo','OverlayDesign','OverlayProgramming','OverlayDefenderDev')
foreach($name in $overlayNames){ Assert ($x -match ('x:Name="'+$name+'"')) "overlay interativo presente: $name" }
# Count actual overlay controls independently of visual style names.
[xml]$layoutXml=$x
$overlayNodes=@($layoutXml.SelectNodes('//*[local-name()="ToggleButton"]') | Where-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') -like 'Overlay*' })
$chipCount=$overlayNodes.Count
Assert ($chipCount -eq 16) 'exatamente 16 chips/toggles condicionais no layout'
Assert (@($overlayNodes | ForEach-Object {$_.GetAttribute('Tag')} | Select-Object -Unique).Count -eq 16) 'overlays preservam 16 perfis canonicos unicos'
Assert ($x -match 'x:Key="SettingsSwitch"') 'toggle de Configuracoes usa estilo separado dos overlays'
Assert ($x -match 'Style="\{StaticResource SettingsSwitch\}" Content="ATIVO"') 'Modo desenvolvedor nao contamina contagem de overlays'

Write-Host "`n=== TEST 04: Native UI leve e sem mutacao direta ===" -ForegroundColor Yellow
$nativeFiles=@('Program.cs','BridgeClient.cs','MainWindowController.cs','WinSlimShell.xaml')
foreach($rel in $nativeFiles){ Assert (Test-Path -LiteralPath (Join-Path $nativeDir $rel)) "arquivo Native UI existe: $rel" }
$nativeText=($nativeFiles | ForEach-Object { Get-Content -LiteralPath (Join-Path $nativeDir $_) -Raw -Encoding UTF8 }) -join "`n"
$forbidden=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe','Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler','Invoke-WinSlimTransactionOptimized','New-WinSlimPresetPreview','Invoke-WinSlimPresetRuntimePlannerValidation')
foreach($token in $forbidden){ Assert ($nativeText -notmatch [regex]::Escape($token)) "Native UI nao executa: $token" }
Assert ($nativeText -match 'WindowChrome') 'WindowChrome nativo preservado'
Assert ($nativeText -match 'DwmSetWindowAttribute') 'DWM moderno quando suportado'
Assert ($nativeText -match 'SetProcessDpiAwarenessContext') 'DPI Per-Monitor V2 configurado programaticamente'
Assert ($nativeText -match 'DoubleAnimation') 'transicoes WPF nativas preservadas'
Assert ($nativeText -match 'TimeSpan\.FromMilliseconds\(160\)') 'transicao curta ~160 ms'
Assert ($nativeText -match 'DispatcherTimer') 'metricas usam DispatcherTimer'
Assert ($nativeText -match 'TimeSpan\.FromSeconds\(3\)') 'metricas limitadas a 3 segundos'
Assert ($nativeText -match 'WindowState == WindowState\.Minimized') 'metricas pausam quando minimizado'
Assert ($nativeText -match '_currentPage, "Dashboard"') 'metricas somente no Dashboard'
Assert ($nativeText -notmatch 'Thread\.Sleep') 'nenhum Thread.Sleep bloqueia UI'

Write-Host "`n=== TEST 05: bridge R3.2.12 persistente, read-only e parser robusto ===" -ForegroundColor Yellow
$bridgePath=Join-Path $nativeDir 'WinSlim.UiBridge.ps1'
Assert (Test-Path -LiteralPath $bridgePath) 'WinSlim.UiBridge.ps1 R3.2.12 existe'
$b=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8
Assert ($b -match '\[switch\]\$Server') 'bridge possui modo servidor persistente'
foreach($action in @('handshake','snapshot','performance','overlays','resolvepreset')){ Assert ($b -match ("'"+$action+"'")) "bridge expoe acao read-only: $action" }
Assert ($b -match 'Resolve-WinSlimPresetRuntimeSelection') 'bridge usa PresetRuntime canonico'
Assert ($b -match 'ConvertFrom-WinSlimProfilesArgument') 'one-shot possui parser tolerante a argv do PowerShell 5.1'
foreach($token in $forbidden){ Assert ($b -notmatch [regex]::Escape($token)) "bridge nao executa: $token" }

Write-Host "`n=== TEST 06: bridge real resolve preset/overlay sem Apply ===" -ForegroundColor Yellow
try{
  $handshakeRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action Handshake -RootPath $Root
  $handshake=$handshakeRaw|ConvertFrom-Json
  Assert ([int]$handshake.backendCount -eq 230) 'handshake real retorna backend 230'
  Assert ([bool]$handshake.readOnly) 'handshake declara bridge read-only'
  Assert ([bool]$handshake.plannerPromoted) 'Planner promovido no bridge real'
  Assert ([bool]$handshake.transactionPromoted) 'Transaction promovido no bridge real'
  Assert ([string]$handshake.bridgeVersion -eq '7.3.2.12') 'bridge reporta versao 7.3.2.12'

  # JSON de um elemento e deliberadamente testado atraves de processo externo.
  # O parser R3.2.12 tolera a remocao de aspas que pode ocorrer no argv do PS5.1.
  $resolveRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["HW-HAGS-ON"]'
  $resolved=$resolveRaw|ConvertFrom-Json
  Assert ([int]$resolved.baseCount -eq 129) 'Gamer real preserva base 129'
  Assert ([int]$resolved.enabledOverlayCount -eq 1) 'HAGS real habilita exatamente 1 overlay'
  Assert ([int]$resolved.selectedCount -eq 130) 'Gamer + HAGS resulta 130 tweaks'
  Assert ([bool]$resolved.canResolve) 'Gamer + HAGS resolve sem bloqueio'

  $fallbackRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson 'HW-HAGS-ON'
  $fallback=$fallbackRaw|ConvertFrom-Json
  Assert ([int]$fallback.enabledOverlayCount -eq 1) 'parser fallback aceita profile escalar sem JSON'

  $highRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["HW-GPU-IRQ-AFFINITY"]'
  $high=$highRaw|ConvertFrom-Json
  Assert (-not [bool]$high.canResolve) 'overlay Alto sem consentimento permanece bloqueado'
  Assert (@($high.blockedRequests|Where-Object{$_.code -eq 'HighRiskConsentRequired'}).Count -eq 1) 'bloqueio Alto usa contrato HighRiskConsentRequired'
}catch{
  Fail ("bridge real falhou: "+$_.Exception.Message)
}

Write-Host "`n=== TEST 07: build C# WPF nativo com diagnostico visivel ===" -ForegroundColor Yellow
$buildPath=Join-Path $Root 'Build-NativeUI-R3.2.12.ps1'
Assert (Test-Path -LiteralPath $buildPath) 'Build-NativeUI-R3.2.12.ps1 existe'
$buildText=Get-Content -LiteralPath $buildPath -Raw -Encoding UTF8
Assert ($buildText -notmatch [regex]::Escape("`$lines.Add('/noconfig')")) '/noconfig nao esta dentro do response file'
Assert ($buildText -match [regex]::Escape("`$compilerArgs = @('/noconfig', (`"@`" + `$rsp))")) '/noconfig e argumento direto do csc.exe'
Assert ($buildText.Contains('& $csc @compilerArgs 2>&1')) 'csc.exe recebe argumentos via array splatting direto'
Assert ($buildText -match 'explicit framework references') 'build documenta referencias explicitas/deterministicas'
Assert ($buildText -match 'Write-BuildLog -Lines') 'build cria log antes da compilacao'
Assert ($buildText -match 'ExitCode:') 'build registra exit code no log persistente'
Assert ($buildText -match 'AppendAllText') 'logger usa AppendAllText com assinatura nao ambigua no PS5.1'
Assert ($buildText -notmatch 'AppendAllLines\(') 'build nao usa AppendAllLines ambiguo no caminho de log'
Assert ($buildText -match 'Copy-Item -LiteralPath \$ConfigSource -Destination \$ConfigDest -Force') 'config e copiado somente apos compilacao valida'
Assert ($buildText -match 'PowerShell 5\.1-safe') 'build documenta o hotfix do caminho IfNeeded'
Assert ($buildText -match '\$inputs = New-Object System\.Collections\.ArrayList') 'IfNeeded usa colecao explicita PS5.1-safe'
Assert ($buildText -notmatch "Get-Item -LiteralPath \(Join-Path \$SourceDir 'WinSlimShell\.xaml'\),") 'IfNeeded nao separa comandos Get-Item por virgula'
function Invoke-BuildForGate([switch]$IfNeeded) {
  $mode=if($IfNeeded){'ifneeded'}else{'forced'}
  $outPath=Join-Path $Root ("logs\gate-build-r3.2.12-$mode.stdout.log")
  $errPath=Join-Path $Root ("logs\gate-build-r3.2.12-$mode.stderr.log")
  $psExe=Join-Path $PSHOME 'powershell.exe'
  $argsText='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $buildPath + '"'
  if($IfNeeded){$argsText+=' -IfNeeded'}
  $process=Start-Process -FilePath $psExe -ArgumentList $argsText -WorkingDirectory $Root -RedirectStandardOutput $outPath -RedirectStandardError $errPath -Wait -PassThru
  $lines=@()
  if(Test-Path -LiteralPath $outPath){$lines+=@(Get-Content -LiteralPath $outPath)}
  if(Test-Path -LiteralPath $errPath){$lines+=@(Get-Content -LiteralPath $errPath)}
  return [pscustomobject]@{ExitCode=$process.ExitCode;Output=$lines}
}
if(-not (Test-Path -LiteralPath (Join-Path $Root 'logs'))){New-Item -ItemType Directory -Path (Join-Path $Root 'logs') -Force|Out-Null}
$buildOutput=@()
$buildExit=-1
try{
  $buildResult=Invoke-BuildForGate
  $buildOutput=@($buildResult.Output)
  $buildExit=[int]$buildResult.ExitCode
  if($buildExit -ne 0){
    Write-Host '  Diagnostico do build:' -ForegroundColor DarkYellow
    foreach($line in @($buildOutput|Select-Object -Last 60)){Write-Host ('    '+[string]$line) -ForegroundColor DarkYellow}
  }
  Assert ($buildExit -eq 0) 'compilacao Native UI retorna exit code 0'
}catch{ Fail ("falha ao executar build Native UI: "+$_.Exception.Message) }
if($buildExit -ne 0){
  Write-Host "`nBUILD REPROVADO: gate interrompido; executavel anterior nao sera usado no self-test." -ForegroundColor Red
  $diagnostic=Join-Path $Root 'logs\build-native-r3.2.12.log'
  if(Test-Path -LiteralPath $diagnostic){Get-Content -LiteralPath $diagnostic -Tail 80 | ForEach-Object {Write-Host $_}}
  Write-Host 'Feche o Win-Slim antes de repetir. Envie gate-native-r3.2.12.log e build-native-r3.2.12.log se continuar falhando.' -ForegroundColor Yellow
  exit 1
}
Write-Host "`n=== TEST 07B: recompilar com executavel de destino existente ===" -ForegroundColor Yellow
try {
  $secondBuild=Invoke-BuildForGate
  Assert ([int]$secondBuild.ExitCode -eq 0) 'segunda compilacao publica sobre executavel existente (File.Replace)'
  if([int]$secondBuild.ExitCode -ne 0){
    foreach($line in $secondBuild.Output){Write-Host ([string]$line)}
    Write-Host 'Gate interrompido: falha na substituicao do executavel.' -ForegroundColor Red
    exit 1
  }
} catch { Fail ("recompilacao falhou: " + $_.Exception.Message); exit 1 }

$exe=Join-Path $Root 'bin\WinSlim.UI.Native.R3.2.12.exe'
Assert (Test-Path -LiteralPath $exe) 'WinSlim.UI.Native.R3.2.12.exe foi gerado'
Assert (Test-Path -LiteralPath ($exe+'.config')) 'config .NET Framework acompanha executavel'
Assert (Test-Path -LiteralPath (Join-Path $Root 'logs\build-native-r3.2.12.log')) 'build gera log diagnostico persistente'
$buildLogPath=Join-Path $Root 'logs\build-native-r3.2.12.log'
if(Test-Path -LiteralPath $buildLogPath){
  $buildLogText=Get-Content -LiteralPath $buildLogPath -Raw -Encoding UTF8
  Assert (-not [string]::IsNullOrWhiteSpace($buildLogText)) 'log de build permanece nao vazio mesmo sem warnings'
  Assert ($buildLogText -match 'Invocation: csc.exe /noconfig @response-file|Mode: IfNeeded / up-to-date') 'log registra modo/invocacao do build'
  Assert ($buildLogText -match 'ExitCode: 0') 'log registra sucesso do compilador'
  Assert ($buildLogText -match 'BuildPublished: true') 'executavel foi publicado pelo build desta execucao'
  Assert ($buildLogText -notmatch 'CS2023') 'build nao ignora /noconfig'
  Assert ($buildLogText -notmatch 'CS1703') 'build nao possui referencias de assembly duplicadas'
}

Write-Host "`n=== TEST 08: regressao launcher / -IfNeeded no PowerShell 5.1 ===" -ForegroundColor Yellow
$launcherPath=Join-Path $Root 'Executar-WinSlim-R3.2.12.bat'
Assert (Test-Path -LiteralPath $launcherPath) 'launcher R3.2.12 existe'
if(Test-Path -LiteralPath $launcherPath){
  $launcherText=Get-Content -LiteralPath $launcherPath -Raw -Encoding Default
  Assert ($launcherText -match [regex]::Escape('Build-NativeUI-R3.2.12.ps1" -IfNeeded')) 'launcher usa build R3.2.12 com -IfNeeded'
}
$buildLogBeforeHash=(Get-FileHash -LiteralPath $buildLogPath -Algorithm SHA256).Hash
$exeBeforeHash=$null
if(Test-Path -LiteralPath $exe){ $exeBeforeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash }
$ifNeededOutput=@()
$ifNeededExit=-1
try{
  $ifNeededResult=Invoke-BuildForGate -IfNeeded
  $ifNeededOutput=@($ifNeededResult.Output)
  $ifNeededExit=[int]$ifNeededResult.ExitCode
  if($ifNeededExit -ne 0){
    Write-Host '  Diagnostico do -IfNeeded:' -ForegroundColor DarkYellow
    foreach($line in @($ifNeededOutput|Select-Object -Last 60)){Write-Host ('    '+[string]$line) -ForegroundColor DarkYellow}
  }
  Assert ($ifNeededExit -eq 0) 'segunda execucao -IfNeeded retorna exit code 0'
}catch{ Fail ("caminho -IfNeeded falhou: "+$_.Exception.Message) }
Assert (Test-Path -LiteralPath $exe) 'executavel permanece presente apos -IfNeeded'
Assert (Test-Path -LiteralPath ($exe+'.config')) 'config permanece presente apos -IfNeeded'
if($exeBeforeHash -and (Test-Path -LiteralPath $exe)){
  $exeAfterHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
  Assert ($exeAfterHash -eq $exeBeforeHash) 'IfNeeded nao recompila executavel atualizado'
}
Assert ((Get-FileHash -LiteralPath $buildLogPath -Algorithm SHA256).Hash -eq $buildLogBeforeHash) 'IfNeeded preserva byte-a-byte o log do compilador'
$ifNeededLogPath=Join-Path $Root 'logs\build-native-r3.2.12-ifneeded.log'
Assert (Test-Path -LiteralPath $ifNeededLogPath) 'IfNeeded possui log separado'
if(Test-Path -LiteralPath $ifNeededLogPath){
  $ifNeededLog=Get-Content -LiteralPath $ifNeededLogPath -Raw -Encoding UTF8
  Assert ($ifNeededLog -match 'Mode: IfNeeded / up-to-date') 'log confirma caminho IfNeeded/up-to-date'
  Assert ($ifNeededLog -match 'ExitCode: 0') 'log IfNeeded registra sucesso'
}

Write-Host "`n=== TEST 09: self-test do executavel carrega XAML + conversa com bridge ===" -ForegroundColor Yellow
if(Test-Path -LiteralPath $exe){
  $self=Join-Path $env:TEMP ('winslim-native-selftest-r3212-'+[guid]::NewGuid().ToString('N')+'.json')
  try{
    $proc=Start-Process -FilePath $exe -ArgumentList @('--root',"`"$Root`"",'--self-test',"`"$self`"") -WorkingDirectory $Root -Wait -PassThru
    Assert ($proc.ExitCode -eq 0) 'executavel self-test retorna exit code 0'
    Assert (Test-Path -LiteralPath $self) 'executavel produz resultado do self-test'
    if(Test-Path -LiteralPath $self){
      $sj=Get-Content -LiteralPath $self -Raw -Encoding UTF8|ConvertFrom-Json
      Assert ([bool]$sj.ok) 'self-test reporta OK'
      Assert ([bool]$sj.xamlLoaded) 'XAML foi carregado pelo runtime WPF real'
      Assert ([bool]$sj.controllerInitialized) 'controller inicializado: eventos e nomes resolvidos no WPF real'
      Assert ([bool]$sj.sidebarLabelsFit) 'legendas longas cabem no menu no viewport minimo'
      Assert ([int]$sj.presetControlsValidated -eq 16) '16 controles da tela Presets carregados pelo WPF real'
      Assert ([bool]$sj.presetLayoutFits) 'selo RECOMENDADO e cinco beneficios cabem nos cards WPF'
      Assert ([int]$sj.dashboardControlsValidated -eq 25) '25 controles do Dashboard encontrados pelo WPF real'
      Assert ([int]$sj.backendCount -eq 230) 'executavel enxerga backend 230 pelo bridge'
      Assert ([string]$sj.bridgeVersion -eq '7.3.2.12') 'executavel conversa com bridge R3.2.12'
    }
  }catch{ Fail ("self-test executavel falhou: "+$_.Exception.Message) }
  finally{ Remove-Item -LiteralPath $self -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n=== TEST 10: arquivos R3.2.12 registrados ===" -ForegroundColor Yellow
$specPath=Join-Path $Root 'specs\FASE7-R3.2.12-baseline.json'
Assert (Test-Path -LiteralPath $specPath) 'spec R3.2.12 existe'
if(Test-Path -LiteralPath $specPath){
  $spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($q in $spec.r3212Files.PSObject.Properties){
    $path=Join-Path $Root ([string]$q.Name)
    $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$q.Value).ToLowerInvariant())
    Assert $ok "R3.2.12 registrado: $($q.Name)"
  }
}

Write-Host "`n=== RESUMO FASE 7 R3.2.12 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
  Write-Host 'GATE TECNICO R3.2.12 APROVADO - Native UI compilada/self-test aprovado; launcher -IfNeeded validado no PS5.1, config preservado e backend protegido.' -ForegroundColor Green
  Write-Host 'Abra Executar-WinSlim-R3.2.12.bat; o launcher deve reutilizar o build sem recompilar e iniciar a Native UI normalmente.' -ForegroundColor Cyan
  Write-Host 'Abertura real e comparacao visual ainda precisam de aprovacao.' -ForegroundColor Yellow
  exit 0
}
Write-Host "FASE 7 R3.2.12 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1
