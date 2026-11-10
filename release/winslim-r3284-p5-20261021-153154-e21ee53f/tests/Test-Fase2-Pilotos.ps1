<#
    Validação real dos 3 tweaks-piloto da Fase 2 (PILOT-001/002/003), chamando
    DIRETAMENTE os Providers novos (Invoke-RegistryProvider, Invoke-
    FsutilOddEvenProvider) - nunca Invoke-TweakEngine (motor legado). Isso é
    a prova de que Detect -> Backup -> Apply -> Verify -> Undo -> Verify
    funciona de ponta a ponta na arquitetura nova.

    Correções Fase 2.1 (achadas em execução real no Windows):
      - Console/saída forçados para UTF-8 (sem isso, acentos saem como
        mojibake no PowerShell 5.1 - "repetição" virava "repetiÃ§Ã£o").
      - $results agora é array simples, não Generic.List (mesmo padrão de
        risco corrigido em todos os Providers).
      - Novo cenário: PILOT-001 também é testado numa chave que NÃO existe
        de antemão, pra confirmar que o Undo remove (em vez de restaurar um
        valor incorreto) quando Exists=false no backup.

    Requer: Windows 10/11, PowerShell 5.1+, admin (grava em HKLM para
    PILOT-002/parte do contexto). Rode manualmente:
        powershell -File .\tests\Test-Fase2-Pilotos.ps1

    Este script foi corrigido com base em execução real reportada pelo time,
    mas a bateria completa ainda precisa ser re-executada numa máquina
    Windows real para confirmar os ajustes desta revisão.
#>
param([switch]$KeepChanges)

$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

$root = Split-Path -Parent $PSScriptRoot
$ScriptRoot = $root

. (Join-Path $root 'src/Core/Logging.ps1')
. (Join-Path $root 'src/Core/ProviderContract.ps1')
. (Join-Path $root 'src/Providers/RegistryProvider.ps1')
. (Join-Path $root 'src/Providers/CommandProvider.ps1')

$LogPath = Join-Path $root 'Logs/test-fase2-pilotos.log'
if (-not (Test-Path (Join-Path $root 'Logs'))) { New-Item -Path (Join-Path $root 'Logs') -ItemType Directory -Force | Out-Null }

$results = @()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "  [OK] $Message" -ForegroundColor Green }
    else { Write-Host "  [FALHA] $Message" -ForegroundColor Red }
    return $Condition
}

Write-Host "=== PILOT-001: Atraso de repeticao do teclado (RegistryProvider) ===" -ForegroundColor Cyan
$p1RegOps = @([PSCustomObject]@{ Path = 'HKCU:\Control Panel\Keyboard'; Name = 'KeyboardDelay'; Value = '0'; Type = 'String' })
$p1Before = Get-RegistryState -Path $p1RegOps[0].Path -Name $p1RegOps[0].Name
Write-Host "  Detect (antes): Exists=$($p1Before.Exists) Value=$($p1Before.Value)"
$p1Apply = Invoke-RegistryProvider -Id 'PILOT-001' -RegistryOps $p1RegOps -Action 'Apply'
$ok1 = Assert-True $p1Apply.Success "Apply retornou Success=true"
$ok2 = Assert-True $p1Apply.Verification.Success "Verify pos-apply confirma KeyboardDelay=0"
if (-not $KeepChanges) {
    $p1Undo = Invoke-RegistryProvider -Id 'PILOT-001' -RegistryOps $p1RegOps -Action 'Undo' -BackupData $p1Apply.StateBefore
    $ok3 = Assert-True $p1Undo.Success "Undo restaurou o valor original ($($p1Before.Value))"
    $ok4 = Assert-True $p1Undo.Verification.Success "Verify pos-undo confirma restauracao"
} else { $ok3 = $true; $ok4 = $true }
$results += [PSCustomObject]@{ Pilot = 'PILOT-001'; Apply = $ok1 -and $ok2; Undo = $ok3 -and $ok4 }

Write-Host "`n=== PILOT-001b: RegistryProvider numa chave que NAO existe de antemao ===" -ForegroundColor Cyan
Write-Host "  (valida que Undo REMOVE a chave, em vez de inventar um valor, quando Exists=false no backup)"
$p1bPath = 'HKCU:\Software\WinSlimSuite\_Fase2TesteTemporario'
$p1bRegOps = @([PSCustomObject]@{ Path = $p1bPath; Name = 'ChaveDeTeste'; Value = '1'; Type = 'DWord' })
if (Test-Path $p1bPath) { Remove-Item -Path $p1bPath -Recurse -Force -ErrorAction SilentlyContinue }
if (-not (Test-Path $p1bPath)) { New-Item -Path $p1bPath -Force | Out-Null }
$p1bBefore = Get-RegistryState -Path $p1bRegOps[0].Path -Name $p1bRegOps[0].Name
$ok1bPre = Assert-True (-not $p1bBefore.Exists) "Pre-condicao: a chave de teste realmente nao existe ainda"
$p1bApply = Invoke-RegistryProvider -Id 'PILOT-001b' -RegistryOps $p1bRegOps -Action 'Apply'
$ok1b1 = Assert-True $p1bApply.Success "Apply criou a chave com sucesso"
$ok1b2 = Assert-True (-not $p1bApply.StateBefore[0].Exists) "Backup registrou corretamente Exists=false (nao existia antes)"
if (-not $KeepChanges) {
    $p1bUndo = Invoke-RegistryProvider -Id 'PILOT-001b' -RegistryOps $p1bRegOps -Action 'Undo' -BackupData $p1bApply.StateBefore
    $p1bAfterUndo = Get-RegistryState -Path $p1bRegOps[0].Path -Name $p1bRegOps[0].Name
    $ok1b3 = Assert-True (-not $p1bAfterUndo.Exists) "Undo REMOVEU a chave (em vez de restaurar um valor '0' inventado)"
    Remove-Item -Path $p1bPath -Recurse -Force -ErrorAction SilentlyContinue
} else { $ok1b3 = $true }
$results += [PSCustomObject]@{ Pilot = 'PILOT-001b'; Apply = $ok1bPre -and $ok1b1 -and $ok1b2; Undo = $ok1b3 }

Write-Host "`n=== PILOT-003: Game Mode (RegistryProvider) ===" -ForegroundColor Cyan
$p3RegOps = @([PSCustomObject]@{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Value = 1; Type = 'DWord' })
$p3Before = Get-RegistryState -Path $p3RegOps[0].Path -Name $p3RegOps[0].Name
Write-Host "  Detect (antes): Exists=$($p3Before.Exists) Value=$($p3Before.Value)"
$p3Apply = Invoke-RegistryProvider -Id 'PILOT-003' -RegistryOps $p3RegOps -Action 'Apply'
$ok5 = Assert-True $p3Apply.Success "Apply retornou Success=true"
$ok6 = Assert-True $p3Apply.Verification.Success "Verify pos-apply confirma AutoGameModeEnabled=1"
if (-not $KeepChanges) {
    $p3Undo = Invoke-RegistryProvider -Id 'PILOT-003' -RegistryOps $p3RegOps -Action 'Undo' -BackupData $p3Apply.StateBefore
    $ok7 = Assert-True $p3Undo.Success "Undo restaurou o valor original"
    $ok8 = Assert-True $p3Undo.Verification.Success "Verify pos-undo confirma restauracao"
} else { $ok7 = $true; $ok8 = $true }
$results += [PSCustomObject]@{ Pilot = 'PILOT-003'; Apply = $ok5 -and $ok6; Undo = $ok7 -and $ok8 }

Write-Host "`n=== PILOT-002: NTFS Last Access (CommandProvider / fsutil) ===" -ForegroundColor Cyan
$p2Before = Get-FsutilBehaviorState -Setting 'disablelastaccess'
Write-Host "  Detect (antes): Value=$($p2Before.Value) (0/2=habilitado, 1/3=desabilitado)"
$p2Apply = Invoke-FsutilOddEvenProvider -Id 'PILOT-002' -Setting 'disablelastaccess' -TargetValue 1 -Action 'Apply'
$ok9 = Assert-True $p2Apply.Success "Apply retornou Success=true"
$ok10 = Assert-True $p2Apply.Verification.Success "Verify pos-apply confirma valor IMPAR (desabilitado) - nao compara com '1' fixo"
if (-not $KeepChanges) {
    $p2Undo = Invoke-FsutilOddEvenProvider -Id 'PILOT-002' -Setting 'disablelastaccess' -Action 'Undo' -BackupData $p2Apply.StateBefore
    $ok11 = Assert-True $p2Undo.Success "Undo restaurou o valor EXATO capturado ($($p2Apply.StateBefore.Value)), nao um '0' hardcoded"
    $ok12 = Assert-True $p2Undo.Verification.Success "Verify pos-undo confirma restauracao"
} else { $ok11 = $true; $ok12 = $true }
$results += [PSCustomObject]@{ Pilot = 'PILOT-002'; Apply = $ok9 -and $ok10; Undo = $ok11 -and $ok12 }

Write-Host "`n=== RESUMO ===" -ForegroundColor Yellow
$results | Format-Table -AutoSize
$allOk = -not (@($results) | Where-Object { -not $_.Apply -or -not $_.Undo })
if ($allOk) { Write-Host "TODOS OS PILOTOS PASSARAM - arquitetura Fase 2.1 validada de ponta a ponta." -ForegroundColor Green }
else { Write-Host "AO MENOS UM PILOTO FALHOU - ver detalhes acima antes de migrar mais tweaks." -ForegroundColor Red }
exit $(if ($allOk) { 0 } else { 1 })
