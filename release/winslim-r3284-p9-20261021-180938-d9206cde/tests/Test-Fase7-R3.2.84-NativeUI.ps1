#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[switch]$IntegratedMode)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
. (Join-Path $Root 'tests\regression\NativeDelegation.ps1')
$Failures = New-Object System.Collections.ArrayList
function Normalize-ThemeTokens([string]$text){
 $text=[regex]::Replace($text,'\{DynamicResource Theme(?:Brush|Color)_([A-Fa-f0-9]{6,8})\}',{param($m) '#'+$m.Groups[1].Value})
 return $text.Replace('{DynamicResource ThemeAccent}','#FF7A00')
}
function Ok([string]$m){ Write-Host "  [OK] $m" -ForegroundColor Green }
function Fail([string]$m){ Write-Host "  [FAIL] $m" -ForegroundColor Red; [void]$Failures.Add($m) }
function Assert([bool]$c,[string]$m){ if($c){Ok $m}else{Fail $m} }

Write-Host '============================================================'
Write-Host ' Win-Slim Suite - FASE 7 R3.2.84 / Dashboard / Read-only'
Write-Host '============================================================'
Write-Host 'R3.2.84: build com diagnostico preservado; validacao tecnica nao substitui abertura e aprovacao visual.'

Write-Host "`n=== TEST 00: baseline FASE 6.5 R4.1 preservada ===" -ForegroundColor Yellow
$r4spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE6.5-R4-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r4spec.files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "baseline R4.1 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01: FASE 7 R3.2.5 permanece byte-a-byte normalizada ===" -ForegroundColor Yellow
$r325spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.5-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r325spec.r325Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.5 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01B: R3.2.6 permanece normalizada ===" -ForegroundColor Yellow
$r326spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.6-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r326spec.r326Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.6 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01C: R3.2.7 permanece normalizada ===" -ForegroundColor Yellow
$r327spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.7-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r327spec.r327Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.7 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01D: R3.2.8 permanece normalizada ===" -ForegroundColor Yellow
$r328spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.8-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r328spec.r328Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.8 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01E: R3.2.9 permanece normalizada ===" -ForegroundColor Yellow
$r329spec = Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.9-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $r329spec.r329Files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())
  Assert $ok "R3.2.9 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01F: R3.2.10 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.10-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec.r3210Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.10 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01G: R3.2.11 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec11=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.11-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec11.r3211Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.11 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01H: R3.2.12 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec12=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.12-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec12.r3212Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.12 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01I: R3.2.13 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec13=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.13-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec13.r3213Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.13 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01J: R3.2.14 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec14=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.14-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec14.r3214Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.14 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01K: R3.2.15 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec15=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.15-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec15.r3215Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.15 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01L: R3.2.16 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec16=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.16-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec16.r3216Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.16 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01M: R3.2.17 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec17=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.17-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec17.r3217Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.17 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01N: R3.2.18 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec18=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.18-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec18.r3218Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.18 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01O: R3.2.19 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec19=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.19-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec19.r3219Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.19 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01P: R3.2.20 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec20=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.20-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec20.r3220Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.20 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01Q: R3.2.21 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec21=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.21-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec21.r3221Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.21 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01R: R3.2.22 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec22=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.22-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec22.r3222Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.22 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01S: R3.2.23 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec23=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.23-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec23.r3223Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.23 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01T: R3.2.24 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec24=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.24-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec24.r3224Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.24 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01U: R3.2.25 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec25=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.25-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec25.r3225Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.25 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01V: R3.2.26 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec26=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.26-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec26.r3226Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.26 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01W: R3.2.27 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec27=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.27-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec27.r3227Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.27 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01X: R3.2.28 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec28=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.28-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec28.r3228Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.28 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01Y: R3.2.29 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec29=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.29-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec29.r3229Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.29 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01Z: R3.2.30 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec30=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.30-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec30.r3230Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.30 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AA: R3.2.31 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec31=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.31-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec31.r3231Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.31 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AB: R3.2.32 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec32=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.32-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec32.r3232Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.32 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AC: R3.2.33 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec33=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.33-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec33.r3233Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.33 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AD: R3.2.34 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec34=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.34-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec34.r3234Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.34 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AE: R3.2.35 permanece normalizada ===" -ForegroundColor Yellow
$previousSpec35=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.35-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec35.r3235Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.35 normalizada: $($p.Name)"
}

Write-Host "`n=== TEST 01AF: Integridade R3.2.36 apos padronizacao ===" -ForegroundColor Yellow
$previousSpec36=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.36-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec36.r3236Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "Integridade: $($p.Name)"
}

Write-Host "`n=== TEST 01AG: R3.2.37 permanece preservada ===" -ForegroundColor Yellow
$previousSpec37=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.37-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec37.r3237Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.37 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AH: R3.2.38 permanece preservada ===" -ForegroundColor Yellow
$previousSpec38=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.38-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec38.r3238Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.38 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AI: R3.2.39 permanece preservada ===" -ForegroundColor Yellow
$previousSpec39=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.39-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec39.r3239Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.39 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AJ: R3.2.40 permanece preservada ===" -ForegroundColor Yellow
$previousSpec40=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.40-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec40.r3240Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.40 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AK: R3.2.41 permanece preservada ===" -ForegroundColor Yellow
$previousSpec41=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.41-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec41.r3241Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.41 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AL: R3.2.42 permanece preservada ===" -ForegroundColor Yellow
$previousSpec42=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.42-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec42.r3242Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.42 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AM: R3.2.43 permanece preservada ===" -ForegroundColor Yellow
$previousSpec43=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.43-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec43.r3243Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.43 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AN: R3.2.44 permanece preservada ===" -ForegroundColor Yellow
$previousSpec44=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.44-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec44.r3244Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.44 preservada: $($p.Name)"
}

Write-Host "`n=== TEST 01AO: R3.2.45 permanece preservada ===" -ForegroundColor Yellow
$previousSpec45=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.45-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec45.r3245Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.45 preservada: $($p.Name)"
}

$previousSpec46=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.46-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec46.r3246Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.46 preservada: $($p.Name)"
}

$previousSpec47=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.47-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec47.r3247Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.47 preservada: $($p.Name)"
}

$previousSpec48=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.48-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec48.r3248Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.48 preservada: $($p.Name)"
}

$previousSpec49=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.49-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec49.r3249Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.49 preservada: $($p.Name)"
}

$previousSpec50=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.50-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec50.r3250Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.50 preservada: $($p.Name)"
}

$previousSpec51=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.51-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec51.r3251Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.51 preservada: $($p.Name)"
}

$previousSpec52=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.52-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec52.r3252Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.52 preservada: $($p.Name)"
}

$previousSpec53=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.53-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec53.r3253Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.53 preservada: $($p.Name)"
}

$previousSpec54=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.54-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec54.r3254Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.54 preservada: $($p.Name)"
}

$previousSpec55=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.55-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec55.r3255Files.PSObject.Properties){
 $path=Join-Path $Root ([string]$p.Name)
 Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) "R3.2.55 preservada: $($p.Name)"
}

foreach($rev in @('56','57','58','59','60','61','62','63','64','65','66','67','68','69')){
 $previous=Get-Content -LiteralPath (Join-Path $Root ('specs\FASE7-R3.2.'+$rev+'-baseline.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
 $files=$previous.('r32'+$rev+'Files')
 foreach($p in $files.PSObject.Properties){
  $path=Join-Path $Root ([string]$p.Name)
  Assert ((Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$p.Value).ToLowerInvariant())) ('R3.2.'+$rev+' preservada: '+$p.Name)
 }
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

Write-Host "`n=== TEST 03: XAML R3.2.84 segue contrato visual + exatamente 16 overlays ===" -ForegroundColor Yellow
$nativeDir=Join-Path $Root 'src\UI\Native\R3_2_84'
$xamlPath=Join-Path $nativeDir 'WinSlimShell.xaml'
Assert (Test-Path -LiteralPath $xamlPath) 'WinSlimShell.xaml R3.2.84 existe'
$x=Normalize-ThemeTokens (Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8)
$xmlOk=$true; try{[xml]$null=$x}catch{$xmlOk=$false}; Assert $xmlOk 'XAML R3.2.84 e XML bem-formado'
foreach($color in @('#080808','#111111','#151515','#FF7A00','#FF9A2E','#C85A00')){ Assert ($x -match [regex]::Escape($color)) "tema contem $color" }
Assert ($x -match 'Width="1180" Height="760"') 'janela compacta 1180x760'
Assert ($x -match '<RowDefinition Height="46"') 'title bar compacta de 46 px'
Assert ($x -match '<ColumnDefinition Width="164"') 'sidebar compacta de 164 px'
Assert ($x -match 'AllowsTransparency="False"') 'sem transparencia pesada'
foreach($page in @('PageDashboard','PagePresets','PagePreview','PageRegistryApply','PageApply','PageResult','PageBackup','PageCustom','PageTweakDetail','PageAnalysis','PageSettings','PageAbout')){ Assert ($x -match ('x:Name="'+$page+'"')) "pagina nativa presente: $page" }
$overlayNames=@('OverlayHags','OverlayMsiGpu','OverlayCoreParking','OverlayGpuIrq','OverlayCs2PCores','OverlayValorant','OverlayCs2','OverlayApex','OverlayFortnite','OverlayGtav','OverlayFso','OverlayStreaming','OverlayVideo','OverlayDesign','OverlayProgramming','OverlayDefenderDev')
foreach($name in $overlayNames){ Assert ($x -match ('x:Name="'+$name+'"')) "overlay interativo presente: $name" }
# Count actual overlay controls independently of visual style names.
[xml]$layoutXml=$x
$overlayNodes=@($layoutXml.SelectNodes('//*[local-name()="ToggleButton"]') | Where-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') -like 'Overlay*' })
$chipCount=$overlayNodes.Count
Assert ($chipCount -eq 16) 'exatamente 16 chips/toggles condicionais no layout'
Assert (@($overlayNodes | ForEach-Object {$_.GetAttribute('Tag')} | Select-Object -Unique).Count -eq 16) 'overlays preservam 16 perfis canonicos unicos'
Assert ($x -match 'Property="Foreground" Value="\{DynamicResource ThemeTintText\}"') 'Texto dos overlays selecionados acompanha o tema'
Assert ($x -match 'Property="Foreground" Value="\{DynamicResource ThemeTintText\}"') 'Texto dos overlays e fechar acompanha o tema'
Assert ($x -match 'x:Key="SettingsSwitch"') 'toggle de Configuracoes usa estilo separado dos overlays'
$developerNodes=@($layoutXml.SelectNodes('//*[local-name()="ToggleButton"]') | Where-Object { $_.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml') -eq 'OptDeveloper' })
Assert (($developerNodes.Count -eq 1) -and ($developerNodes[0].GetAttribute('Style') -eq '{StaticResource PresetDeveloperSwitch}') -and ($overlayNames -notcontains 'OptDeveloper')) 'Modo desenvolvedor usa controle separado dos overlays'

foreach($name in @('ListBackups','ListBackupTweaks','BtnBackupTabBackups','BtnBackupTabTweaks','BtnBackupDetails','BtnBackupRestore','BtnBackupRestoreAll','BtnBackupDelete','BackupSuccessNotice','BtnViewCreatedBackup','TxtBackupState','TxtBackupEmpty')){ Assert ($x -match ('x:Name="'+$name+'"')) "Backup: controle presente $name" }

Write-Host "`n=== TEST 04: Native UI leve e sem mutacao direta ===" -ForegroundColor Yellow
foreach($required in @('WinSlim.UI.Native.exe.config','WinSlim.NativeUI.manifest','WinSlim.UiBridge.ps1','WinSlimPerformance.ps1','WinSlimLivePreview.ps1','WinSlimBackup.ps1','WinSlimRegistryApply.ps1','WinSlim.ico','WinSlimCustom.xaml','WinSlimScrollbars.xaml','WinSlimTweakDetail.xaml')){ Assert (Test-Path -LiteralPath (Join-Path $nativeDir $required)) "dependencia Native UI presente: $required" }
$nativeFiles=@('Program.cs','BridgeClient.cs','MainWindowController.cs','UiLanguage.cs','UiTheme.cs','ApplicationReport.cs','PresentMonBenchmark.cs','WinSlimShell.xaml')
foreach($rel in $nativeFiles){ Assert (Test-Path -LiteralPath (Join-Path $nativeDir $rel)) "arquivo Native UI existe: $rel" }
$nativeText=($nativeFiles | ForEach-Object { Get-Content -LiteralPath (Join-Path $nativeDir $_) -Raw -Encoding UTF8 }) -join "`n"
$nativeText=Normalize-ThemeTokens $nativeText
# Windows PowerShell 5.1 ConvertFrom-Json cannot read case-distinct translation keys.
Add-Type -AssemblyName System.Web.Extensions
$languageParser=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$languageParser.MaxJsonLength=4194304
$languageResource=$languageParser.DeserializeObject([System.IO.File]::ReadAllText((Join-Path $nativeDir 'Strings.en.json'),[System.Text.Encoding]::UTF8))
Assert ($languageResource.schemaVersion -eq 1 -and @($languageResource.tweakIds | Select-Object -Unique).Count -eq 230) 'Idioma cobre os 230 IDs do catalogo'
Assert ($nativeText.Contains('UnifiedFrame') -and $nativeText.Contains('CornerRadius="12"') -and $nativeText.Contains('BtnLanguageAuto') -and $nativeText.Contains('BtnLanguagePt') -and $nativeText.Contains('BtnLanguageEn')) 'Moldura unica e seletor de idioma presentes'

$forbidden=@('Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','reg.exe','bcdedit','powercfg','sc.exe','Set-Service','Stop-Service','Disable-ScheduledTask','Remove-AppxPackage','dism.exe','netsh','Invoke-TransactionPlan','Invoke-WinSlimProvider','ApplyHandler','UndoHandler','Invoke-WinSlimTransactionOptimized')
foreach($token in $forbidden){ Assert ($nativeText -notmatch [regex]::Escape($token)) "Native UI nao executa: $token" }
Assert ($nativeText -match 'WindowChrome') 'WindowChrome nativo preservado'
Assert ($nativeText -match 'DwmSetWindowAttribute') 'DWM moderno quando suportado'
Assert ($nativeText -match 'SetProcessDpiAwarenessContext') 'DPI Per-Monitor V2 configurado programaticamente'
Assert ($nativeText -match 'Tween\(0, 1, duration\)') 'telas usam fade de zero a opacidade total'
Assert ($nativeText -notmatch 'Tween\(18, 0, duration\)') 'telas nao deslocam durante esmaecimento'
Assert ($nativeText -notmatch 'private static void Scale\(') 'interacoes usam esmaecimento em vez de escala'
Assert ($nativeText -match 'ValidateFadeCurve') 'self-test verifica curva monotona sem overshoot'
Assert ($nativeText -match 'DoubleAnimation') 'transicoes WPF nativas preservadas'
Assert ($nativeText -match 'UiMotion.Enter\(target, 320\)') 'esmaecimento de telas em 320 ms'
Assert ($nativeText -match 'Tween\(previous, transform.X, 260\)') 'chaves deslizam em 260 ms'
Assert ($nativeText -match 'UserEnabled && !SystemParameters.HighContrast') 'animacoes controladas no aplicativo'
Assert ($x -match 'x:Name="OptAnimations"[^>]*IsChecked="True"') 'animacoes ativadas por padrao'
Assert ($x -match 'x:Name="MotionGlow"') 'camada de realce visual presente'
Assert ($x -notmatch 'TargetName="SwitchThumb" Property="RenderTransform"') 'trigger nao substitui movimento da chave' 
Assert ($nativeText -match 'DispatcherTimer') 'metricas usam DispatcherTimer'
Assert ($nativeText -match 'TimeSpan\.FromSeconds\(3\)') 'metricas limitadas a 3 segundos'
Assert ($nativeText -match 'WindowState == WindowState\.Minimized') 'metricas pausam quando minimizado'
Assert ($nativeText -match '_currentPage, "Dashboard"') 'metricas somente no Dashboard'
Assert ($nativeText -notmatch 'Thread\.Sleep') 'nenhum Thread.Sleep bloqueia UI'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-Performance.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Performance: formulas, filtros e falhas isoladas preservados'

& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-LivePreview.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'LivePreview: estados, falhas e observacao sem alteracoes'

& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-Backup.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'Backup real: captura tipada, cobertura, persistencia e integridade'

Write-Host "`n=== TEST 05: bridge R3.2.84 persistente, consulta e backup explicito ===" -ForegroundColor Yellow
$bridgePath=Join-Path $nativeDir 'WinSlim.UiBridge.ps1'
Assert (Test-Path -LiteralPath $bridgePath) 'WinSlim.UiBridge.ps1 R3.2.84 existe'
$b=Get-Content -LiteralPath $bridgePath -Raw -Encoding UTF8
Assert ($b -match '\[switch\]\$Server') 'bridge possui modo servidor persistente'
foreach($action in @('handshake','snapshot','performance','overlays','resolvepreset')){ Assert ($b -match ("'"+$action+"'")) "bridge expoe acao read-only: $action" }
Assert ($b -match 'Resolve-WinSlimHardwarePreset') 'bridge usa PresetRuntime canonico'
Assert ($b -match 'ConvertFrom-WinSlimProfilesArgument') 'one-shot possui parser tolerante a argv do PowerShell 5.1'
foreach($token in $forbidden){ Assert ($b -notmatch [regex]::Escape($token)) "bridge nao executa: $token" }

Write-Host "`n=== TEST 06: bridge real resolve preset/overlay sem Apply ===" -ForegroundColor Yellow
try{
  $handshakeRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action Handshake -RootPath $Root
  $handshake=$handshakeRaw|ConvertFrom-Json
  Assert ([int]$handshake.backendCount -eq 230) 'handshake real retorna backend 230'
  Assert (-not [bool]$handshake.readOnly -and -not [bool]$handshake.systemReadOnly -and [bool]$handshake.backupCreation -and [bool]$handshake.backupRestoration -and [bool]$handshake.gpuServiceActions) 'bridge declara backup e acoes GPU explicitas'
  Assert ([bool]$handshake.plannerPromoted) 'Planner promovido no bridge real'
  Assert ([bool]$handshake.transactionPromoted) 'Transaction promovido no bridge real'
  Assert ([string]$handshake.bridgeVersion -eq '7.3.2.84') 'bridge reporta versao 7.3.2.84'

  # JSON de um elemento e deliberadamente testado atraves de processo externo.
  # O parser R3.2.84 tolera a remocao de aspas que pode ocorrer no argv do PS5.1.
  $catalogRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action Catalog -RootPath $Root
  $customCatalog=$catalogRaw|ConvertFrom-Json
  Assert ([bool]$customCatalog.readOnly -and @($customCatalog.tweaks).Count -eq 230) 'Personalizado recebe 230 ajustes reais em modo consulta'
  Assert (@($customCatalog.tweaks.id | Select-Object -Unique).Count -eq 230) 'Personalizado preserva 230 IDs unicos'

  $resolveRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["WL-CS2"]'
  $resolved=$resolveRaw|ConvertFrom-Json
  Assert ([int]$resolved.baseCount -gt 0 -and [int]$resolved.baseCount -le 129) 'Gamer adapta a base ao hardware'
  Assert ([int]$resolved.enabledOverlayCount -eq 1) 'CS2 universal habilita exatamente 1 overlay'
  Assert ([int]$resolved.selectedCount -ge [int]$resolved.baseCount) 'Gamer inclui apenas overlays elegiveis'
  Assert ([bool]$resolved.canResolve) 'Gamer + CS2 resolve sem bloqueio'
  Assert (@($resolved.selectedTweaks).Count -eq [int]$resolved.selectedCount) 'metadados correspondem aos IDs selecionados'
  Assert (@($resolved.selectedTweaks.id | Select-Object -Unique).Count -eq [int]$resolved.selectedCount) 'metadados possuem IDs unicos'

  $previewRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action Preview -RootPath $Root -PresetName Balanceado
  Assert ($LASTEXITCODE -eq 0) 'preview real retorna exit code 0'
  $pv=$previewRaw|ConvertFrom-Json
  Assert ([bool]$pv.readOnly) 'preview permanece read-only'
  Assert ([int]$pv.preview.Summary.Selected -gt 0 -and [int]$pv.preview.Summary.Selected -le 105) 'preview Equilibrado respeita filtro hardware'
  $total=0;foreach($category in @($pv.categories)){$total += [int]$category.count}
  Assert ($total -eq [int]$pv.preview.Summary.Executable) 'categorias somam exatamente os ajustes aptos'
  Assert (@($pv.preview.Items | Where-Object {$_.RequiresRestart}).Count -eq [int]$pv.restartCount) 'contagem de reinicio deriva do plano real'
  Assert (-not [string]::IsNullOrWhiteSpace([string]$pv.preview.PreviewFingerprint)) 'preview possui fingerprint'

  $fallbackRaw=& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson 'WL-CS2'
  $fallback=$fallbackRaw|ConvertFrom-Json
  Assert ([int]$fallback.enabledOverlayCount -eq 1) 'parser fallback aceita profile escalar sem JSON'

  # PS5.1 converte stderr nativo em ErrorRecord. Esta chamada deve falhar;
  # capture a recusa sem interromper o teste e restaure a politica imediatamente.
  $blockedPreference=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    $blockedRaw=@(& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bridgePath -Action ResolvePreset -RootPath $Root -PresetName Gamer -ProfilesJson '["HW-GPU-IRQ-AFFINITY"]' 2>&1)
    $blockedExitCode=$LASTEXITCODE
  } finally {
    $ErrorActionPreference=$blockedPreference
  }
  $blockedMessage=($blockedRaw | Out-String)
  Assert ($blockedExitCode -eq 1) 'hardware sem contrato seguro rejeitado no backend com exit code 1'
  Assert ($blockedMessage -match 'Overlay indispon.vel neste hardware: HW-GPU-IRQ-AFFINITY') 'recusa identifica o overlay de afinidade; erros inesperados continuam reprovando'
}catch{
  Fail ("bridge real falhou: "+$_.Exception.Message)
}

& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-Restore.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'restauracao: contratos, verificacao e recuperacao de falhas'

& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-RegistryApply.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'aplicacao de registro: contratos, backup, tokens, falhas e recuperacao'
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-RegistryApplyWindows.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'aplicacao de registro: IO real somente em chave HKCU descartavel'


Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-Edge.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Edge: contratos, compatibilidade, elevacao, backup e restauracao'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-EndTask.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'EndTask: contrato, compatibilidade e ciclo completo com IO simulado'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-SearchIcon.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'SearchIcon: contrato, conflitos, compatibilidade e restauracao'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-UiBatch.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'UI/QoL: lote multioperacao, compatibilidade, backup e recuperacao'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-Report.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Relatorio: agrupamento, contadores conservadores, HTML e categoria unificada'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-QolBatch.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'QoL: contratos revisados, compatibilidade, backup multivalor e recuperacao'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-EdgeBatch.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Edge lote: quatro contratos, limites de versao e Apply Verify Undo'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-EdgeNext.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Edge interface: quatro contratos, DWORD enumerado e ciclo completo'

Invoke-WinSlimNativePrerequisite -Root $Root -Script 'tests/Test-Fase7-R3.2.84-EdgePrivacy.ps1' -IntegratedMode:$IntegratedMode -AssertResult ${function:Assert} -Message 'Edge preferencias: quatro contratos exatos e ciclo completo'

Write-Host "`n=== TEST 07: build C# WPF nativo com diagnostico visivel ===" -ForegroundColor Yellow
$buildPath=Join-Path $Root 'Build-NativeUI-R3.2.84.ps1'
Assert (Test-Path -LiteralPath $buildPath) 'Build-NativeUI-R3.2.84.ps1 existe'
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
Assert ($buildText.Contains('$cached.inputs -eq $InputFingerprint') -and $buildText.Contains('$cached.exeHash -eq') -and $buildText.Contains('$cached.configHash -eq')) 'IfNeeded verifica conteudo das entradas, executavel e config'
Assert ($buildText -match '\$inputLines = New-Object System\.Collections\.ArrayList' -and $buildText.Contains('[void]$inputLines.Add(')) 'Assinatura usa colecao explicita compativel com PS5.1'
Assert ($buildText -notmatch "Get-Item -LiteralPath \(Join-Path \$SourceDir 'WinSlimShell\.xaml'\),") 'IfNeeded nao separa comandos Get-Item por virgula'
function Invoke-BuildForGate([switch]$IfNeeded) {
  $mode=if($IfNeeded){'ifneeded'}else{'forced'}
  $outPath=Join-Path $Root ("logs\gate-build-r3.2.84-$mode.stdout.log")
  $errPath=Join-Path $Root ("logs\gate-build-r3.2.84-$mode.stderr.log")
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
  $diagnostic=Join-Path $Root 'logs\build-native-r3.2.84.log'
  if(Test-Path -LiteralPath $diagnostic){Get-Content -LiteralPath $diagnostic -Tail 80 | ForEach-Object {Write-Host $_}}
  Write-Host 'Feche o Win-Slim antes de repetir. Envie gate-native-r3.2.84.log e build-native-r3.2.84.log se continuar falhando.' -ForegroundColor Yellow
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

$exe=Join-Path $Root 'bin\WinSlim.UI.Native.R3.2.84.exe'
Assert (Test-Path -LiteralPath $exe) 'WinSlim.UI.Native.R3.2.84.exe foi gerado'
Assert (Test-Path -LiteralPath ($exe+'.config')) 'config .NET Framework acompanha executavel'
Assert (Test-Path -LiteralPath (Join-Path $Root 'logs\build-native-r3.2.84.log')) 'build gera log diagnostico persistente'
$buildLogPath=Join-Path $Root 'logs\build-native-r3.2.84.log'
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
$launcherPath=Join-Path $Root 'Executar-WinSlim-R3.2.84.bat'
Assert (Test-Path -LiteralPath $launcherPath) 'launcher R3.2.84 existe'
if(Test-Path -LiteralPath $launcherPath){
  $launcherText=Get-Content -LiteralPath $launcherPath -Raw -Encoding Default
  Assert ($launcherText -match [regex]::Escape('Build-NativeUI-R3.2.84.ps1" -IfNeeded')) 'launcher usa build R3.2.84 com -IfNeeded'
}
$buildLogBeforeHash=(Get-FileHash -LiteralPath $buildLogPath -Algorithm SHA256).Hash
$cachePath=Join-Path $Root 'logs\build-inputs-r3.2.84.json'
Assert (Test-Path -LiteralPath $cachePath) 'Build publica cache de conteudo para reaproveitamento'
if(Test-Path -LiteralPath $cachePath){
 $cacheData=Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
 Assert ($cacheData.schemaVersion -eq 1 -and $cacheData.inputs -match '^[A-Fa-f0-9]{64}$') 'Cache registra assinatura SHA-256 valida das entradas'
 Assert ($cacheData.exeHash -eq (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash) 'Cache corresponde ao executavel publicado'
 Assert ($cacheData.configHash -eq (Get-FileHash -LiteralPath ($exe+'.config') -Algorithm SHA256).Hash) 'Cache corresponde a configuracao publicada'
}

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
$ifNeededLogPath=Join-Path $Root 'logs\build-native-r3.2.84-ifneeded.log'
Assert (Test-Path -LiteralPath $ifNeededLogPath) 'IfNeeded possui log separado'
if(Test-Path -LiteralPath $ifNeededLogPath){
  $ifNeededLog=Get-Content -LiteralPath $ifNeededLogPath -Raw -Encoding UTF8
  Assert ($ifNeededLog -match 'Mode: IfNeeded / up-to-date') 'log confirma caminho IfNeeded/up-to-date'
  Assert ($ifNeededLog -match 'ExitCode: 0') 'log IfNeeded registra sucesso'
}

Write-Host "`n=== TEST 09: self-test do executavel carrega XAML + conversa com bridge ===" -ForegroundColor Yellow
if(Test-Path -LiteralPath $exe){
  $self=Join-Path $env:TEMP ('winslim-native-selftest-r3284-'+[guid]::NewGuid().ToString('N')+'.json')
  try{
    $proc=Start-Process -FilePath $exe -ArgumentList @('--root',"`"$Root`"",'--self-test',"`"$self`"") -WorkingDirectory $Root -Wait -PassThru
    Assert ($proc.ExitCode -eq 0) 'executavel self-test retorna exit code 0'
    Assert (Test-Path -LiteralPath $self) 'executavel produz resultado do self-test'
    if(Test-Path -LiteralPath $self){
      $sj=Get-Content -LiteralPath $self -Raw -Encoding UTF8|ConvertFrom-Json
      Assert ([bool]$sj.ok) 'self-test reporta OK'
      Assert ([bool]$sj.logsDispatcherValidated) 'Logs: sucesso e falha sem SynchronizationContext atualizam no Dispatcher'
      Assert ([bool]$sj.xamlLoaded) 'XAML foi carregado pelo runtime WPF real'
      Assert ([bool]$sj.controllerInitialized) 'controller inicializado: eventos e nomes resolvidos no WPF real'
      Assert ([bool]$sj.sidebarLabelsFit) 'legendas longas cabem no menu no viewport minimo'
      Assert ([int]$sj.presetControlsValidated -eq 16) '16 controles da tela Presets carregados pelo WPF real'
      Assert ([bool]$sj.presetLayoutFits) 'selo RECOMENDADO e cinco beneficios cabem nos cards WPF'
      Assert ($sj.presetAdvancedPanelsFit -eq $true) 'paineis Avancado visiveis lado a lado sem sobreposicao'
      Assert ([bool]$sj.registryApplyLayoutValidated) 'Aplicacao real: revisao, lista longa e botoes sem sobreposicao nos dois temas/idiomas'
      Assert ([bool]$sj.previewBackupNoticeLayoutValidated) 'Preview: aviso completo, botao visivel e rodape sem sobreposicao nos dois temas/idiomas'
      Assert ([bool]$sj.backupLayoutValidated -and [bool]$sj.backupRestoreDisabled -and [bool]$sj.backupRestoreEnabledForVerifiedOnly -and [bool]$sj.backupInventoryReaderValidated) 'Backup: layout, abas, selecao e leitor de metadados validados; restauracao/exclusao bloqueadas na demonstracao'
      Assert (([int]$sj.uiEfficiencyStatistics.newRowsOnIdenticalRefresh -eq 0) -and ([int]$sj.uiEfficiencyStatistics.indexedTweaks -eq 230)) 'UI: atualizacao identica cria zero linhas, catalogo indexado 230'
      Assert ([bool]$sj.themeValidated) 'Tema automatico/manual, contraste, pinceis e selecao preservados'
      Assert ([bool]$sj.languageValidated) 'Idioma automatico/manual reversivel preserva selecao e dados tecnicos'
      Assert ([bool]$sj.unifiedFrameValidated) 'Moldura laranja compartilhada com cantos arredondados'
      Assert ([bool]$sj.brandIconValidated) 'Pena vetorial consistente e icone incorporado da janela decodificado'
      Assert ([bool]$sj.customWarmNavigationValidated) 'Personalizado preparado reabre sem esperar bridge, criar controles ou perder contexto'
      Assert ([bool]$sj.uiEfficiencyValidated) 'UI: pinceis congelados, indice 230 e reutilizacao de linhas sem perda de selecao'
      Assert ([bool]$sj.interactionMotionValidated) 'Chaves alternam repetidamente e preservam posicao/cor final'
      Assert ([bool]$sj.settingsMigrationValidated) 'Avancado e Logs pertencem a Configuracoes, fora de Presets'
      Assert ([bool]$sj.benchmarkPageValidated) 'Benchmark: controles, estado inicial inativo e navegacao na mesma janela'
      Assert ([bool]$sj.benchmarkCancelPreservesCompleteResultValidated) 'Benchmark: iniciar, cancelar e reiniciar preserva resultado completo e referencia, com processo fixo'
      Assert ([bool]$sj.benchmarkOverlaySettingsCaptureStateValidated) 'Overlay: previa de configuracoes e fechar preservam tarefa pendente, alvo, cancelamento, valores, resultado e referencia'
      Assert ([bool]$sj.benchmarkSettingsAllStatesAndSingletonValidated) 'Overlay: configuracao unica e nao modal abre sem jogo e nos estados desligado/ligado/gravando/concluido/cancelado/transicao; Salvar/Cancelar preservam alvo, tarefa, dados e referencia'
      Assert ([bool]$sj.analysisLayoutValidated) 'Analise: 12 verificacoes, demonstracao identificada, botao de relatorio e Voltar na mesma janela'
      Assert ([bool]$sj.singleWindowNavigationValidated) 'Personalizado, detalhes e relatorios navegam na janela principal, preservam contexto e nao criam outra Window'
      Assert ([bool]$sj.tweakDetailValidated) 'Detalhes: janela, metadados reais, estado, desfazer selecao e rejeicao de ID desconhecido'
      Assert ([bool]$sj.customPresetIntegrationValidated) 'Personalizado: IDs dos tres presets, edicao sem perda e restauracao do preset base'
      Assert ([bool]$sj.customPortableRoundtripValidated) 'Preset portavel: JSON preserva IDs/niveis e rejeita entradas invalidas'
      Assert ([bool]$sj.customPreviewReadOnlyValidated) 'Selecao customizada passa pelo Planner e preview read-only'
      Assert ([int]$sj.customTweakTooltipsValidated -eq 230) 'Personalizado: 230 dicas didaticas presentes nas linhas e chaves com o mesmo modelo dos overlays'
      Assert ([bool]$sj.customCategoryBatchValidated) 'Personalizado: ativacao de toda categoria, filtro, preservacao de outras selecoes, reset e cor verde validados'
      Assert ([bool]$sj.customWindowValidated -and [int]$sj.customCatalogCount -eq 230) 'Personalizado: pagina integrada, categorias, busca, chaves e selecao persistente na sessao validadas'
      Assert ([bool]$sj.uniformWindowSize) 'Todas as paginas preservam 1180x760 e o tamanho manual; detalhes padronizados'
      Assert ([int]$sj.applyControlsValidated -eq 23 -and [bool]$sj.applyDemoCancellation) 'Aplicacao carregada: 5 etapas, progresso e cancelamento de demonstracao'
      Assert ([int]$sj.resultControlsValidated -eq 12 -and [bool]$sj.resultDemoSafe) 'Conclusao carregada, demonstracao identificada e reinicio bloqueado'
      Assert ([int]$sj.overlayTooltipsValidated -eq 16) '16 dicas de overlays presentes e com quebra de linha no WPF real'
      Assert ([int]$sj.previewControlsValidated -eq 11) 'controles da pre-visualizacao encontrados no WPF real'
      Assert ([int]$sj.presetTabsValidated -eq 10) 'Configurações: abas Geral/Avancado/Logs e navegacao WPF validadas'
      Assert ([int]$sj.dashboardControlsValidated -eq 25) '25 controles do Dashboard encontrados pelo WPF real'
      Assert ([int]$sj.backendCount -eq 230) 'executavel enxerga backend 230 pelo bridge'
      Assert ([string]$sj.bridgeVersion -eq '7.3.2.84') 'executavel conversa com bridge R3.2.84'
    }
  }catch{ Fail ("self-test executavel falhou: "+$_.Exception.Message) }
  finally{ Remove-Item -LiteralPath $self -Force -ErrorAction SilentlyContinue }
}

$previousSpec56=Get-Content -LiteralPath (Join-Path $Root 'specs\FASE7-R3.2.56-baseline.json') -Raw -Encoding UTF8 | ConvertFrom-Json
foreach($p in $previousSpec56.r3256Files.PSObject.Properties){
 Assert ((Get-FileHash -LiteralPath (Join-Path $Root $p.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -eq $p.Value) ("R56 preservada: "+$p.Name)
}
& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root 'tests\Test-Fase7-R3.2.84-Gpu.ps1') -Root $Root
Assert ($LASTEXITCODE -eq 0) 'contratos GPU com fixtures: sem alterar o Windows'

Write-Host "`n=== TEST 10: arquivos R3.2.84 registrados ===" -ForegroundColor Yellow
$specPath=Join-Path $Root 'specs\FASE7-R3.2.84-baseline.json'
Assert (Test-Path -LiteralPath $specPath) 'spec R3.2.84 existe'
if(Test-Path -LiteralPath $specPath){
  $spec=Get-Content -LiteralPath $specPath -Raw -Encoding UTF8|ConvertFrom-Json
  foreach($q in $spec.r3284Files.PSObject.Properties){
    $path=Join-Path $Root ([string]$q.Name)
    $ok=(Test-Path -LiteralPath $path) -and ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq ([string]$q.Value).ToLowerInvariant())
    Assert $ok "R3.2.84 registrado: $($q.Name)"
  }
}

Write-Host "`n=== RESUMO FASE 7 R3.2.84 ===" -ForegroundColor Yellow
if($Failures.Count -eq 0){
  Write-Host 'GATE TECNICO R3.2.84 APROVADO - Native UI compilada/self-test aprovado; launcher -IfNeeded validado no PS5.1, config preservado e backend protegido.' -ForegroundColor Green
  Write-Host 'Abra Executar-WinSlim-R3.2.84.bat; o launcher deve reutilizar o build sem recompilar e iniciar a Native UI normalmente.' -ForegroundColor Cyan
  Write-Host 'Abertura real e comparacao visual ainda precisam de aprovacao.' -ForegroundColor Yellow
  exit 0
}
Write-Host "FASE 7 R3.2.84 REPROVADA - $($Failures.Count) falha(s):" -ForegroundColor Red
foreach($f in $Failures){Write-Host " - $f" -ForegroundColor Red}
exit 1

