<#
    Win-Slim Suite - Fase 2.1B Provider Conformance

    Objetivo:
      Validar o contrato real dos 8 Providers antes da Fase 3 (Transaction Manager).
      O harness usa recursos temporarios e restaura o estado original em finally.

    Providers cobertos:
      RegistryProvider, CommandProvider, ServiceProvider, BcdProvider,
      PowerCfgProvider, NetworkProvider, ScheduledTaskProvider, AppxProvider.

    Tambem valida:
      - Undo sem BackupData falha de forma explicita.
      - Invoke-NativeCommand preserva ExitCode mesmo com ErrorActionPreference=Stop.
      - Verify aplicavel com zero checks NAO pode retornar sucesso.
      - Cross-process: backup persistido em JSON e Undo em outro powershell.exe.
      - Registry inexistente -> Apply cria -> Undo remove.
      - Network rollback por InterfaceGuid e pelos 3 valores TCP.
      - ScheduledTask Unregister -> XML backup -> recriacao -> definicao equivalente.
      - AppX nao promete Undo sem fonte de reinstalacao.

    Requer:
      Windows 10/11, Windows PowerShell 5.1+, execucao como Administrador.

    Execucao:
      Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
      .\tests\Test-Fase2-ProviderConformance.ps1

    Opcoes de diagnostico:
      -SkipBcd       pula o teste BCD (resultado final fica PARCIAL)
      -SkipNetwork   pula o teste Network (resultado final fica PARCIAL)
      -SkipPowerCfg  pula o teste PowerCfg (resultado final fica PARCIAL)

    Nao use -KeepChanges: este harness SEMPRE tenta restaurar/limpar tudo.
#>
param(
    [switch]$SkipBcd,
    [switch]$SkipNetwork,
    [switch]$SkipPowerCfg,
    [switch]$CrossProcessChild,
    [string]$BackupFile
)

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

# ---------------------------------------------------------------------------
# Modo filho: usado apenas pelo teste cross-process do RegistryProvider.
# ---------------------------------------------------------------------------
if ($CrossProcessChild) {
    try {
        if (-not $BackupFile -or -not (Test-Path $BackupFile)) { throw 'BackupFile cross-process ausente.' }
        $data = Get-Content -Path $BackupFile -Raw | ConvertFrom-Json
        $ops = @([PSCustomObject]@{
            Path  = [string]$data.Path
            Name  = [string]$data.Name
            Value = 1
            Type  = 'DWord'
        })
        $undo = Invoke-RegistryProvider -Id 'CONF-REG-XPROC' -RegistryOps $ops -Action 'Undo' -BackupData @($data.BackupData)
        $after = Get-RegistryState -Path $data.Path -Name $data.Name
        if ($undo.Success -and $undo.Verification.Success -and -not $after.Exists) { exit 0 }
        exit 41
    } catch {
        Write-Host "[CHILD FAIL] $($_.Exception.Message)" -ForegroundColor Red
        exit 42
    }
}

# Demais Providers/Core so precisam ser carregados no processo principal.
. (Join-Path $root 'src/Providers/ServiceProvider.ps1')
. (Join-Path $root 'src/Providers/BcdProvider.ps1')
. (Join-Path $root 'src/Providers/PowerCfgProvider.ps1')
. (Join-Path $root 'src/Providers/NetworkProvider.ps1')
. (Join-Path $root 'src/Providers/ScheduledTaskProvider.ps1')
. (Join-Path $root 'src/Providers/AppxProvider.ps1')
. (Join-Path $root 'src/Core/Verify.ps1')

$logDir = Join-Path $root 'Logs'
$backupDir = Join-Path $root 'Backups\Conformance'
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $backupDir)) { New-Item -Path $backupDir -ItemType Directory -Force | Out-Null }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $logDir "provider-conformance-$stamp.log"
$reportPath = Join-Path $logDir "provider-conformance-$stamp.json"
$results = @()

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Check {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "  [OK] $Message" -ForegroundColor Green }
    else { Write-Host "  [FALHA] $Message" -ForegroundColor Red }
    return [bool]$Condition
}

function Add-ConformanceResult {
    param([string]$Provider, [ValidateSet('PASS','FAIL','SKIP')] [string]$Status, [string]$Notes)
    $script:results += [PSCustomObject]@{ Provider = $Provider; Status = $Status; Notes = $Notes }
}

function Test-ProviderResultContract {
    param($Result)
    if ($null -eq $Result) { return $false }
    $required = @('Id','Action','Success','Changed','StateBefore','StateAfter','Verification','Restart','Warning','Error')
    foreach ($name in $required) {
        if (-not ($Result.PSObject.Properties.Name -contains $name)) { return $false }
    }
    return $true
}

function Test-NullableEqual {
    param($A, $B)
    if ($null -eq $A -and $null -eq $B) { return $true }
    if ($null -eq $A -or $null -eq $B) { return $false }
    return ([string]$A -eq [string]$B)
}

function Test-NicStateEqual {
    param($A, $B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    return ([string]$A.InterfaceGuid -eq [string]$B.InterfaceGuid) -and
           ([bool]$A.Exists -eq [bool]$B.Exists) -and
           (Test-NullableEqual $A.TcpNoDelay $B.TcpNoDelay) -and
           (Test-NullableEqual $A.TcpAckFrequency $B.TcpAckFrequency) -and
           (Test-NullableEqual $A.TcpDelAckTicks $B.TcpDelAckTicks)
}

function Get-TaskSemanticSignature {
    param([string]$XmlText)
    if ([string]::IsNullOrWhiteSpace($XmlText)) { return $null }
    try {
        [xml]$doc = $XmlText
        $cmd = $doc.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Command']")
        $args = $doc.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='Arguments']")
        $work = $doc.SelectSingleNode("//*[local-name()='Exec']/*[local-name()='WorkingDirectory']")
        $enabled = $doc.SelectSingleNode("//*[local-name()='Settings']/*[local-name()='Enabled']")
        $triggers = @($doc.SelectNodes("//*[local-name()='Triggers']/*"))
        $triggerNames = @($triggers | ForEach-Object { $_.LocalName }) -join ','
        return "Command=$($cmd.InnerText)|Arguments=$($args.InnerText)|WorkingDirectory=$($work.InnerText)|Enabled=$($enabled.InnerText)|Triggers=$triggerNames"
    } catch {
        return $null
    }
}

function Test-NegativeUndo {
    param([scriptblock]$Call, [string]$Label)
    try {
        $r = & $Call
        $ok = (-not $r.Success) -and -not [string]::IsNullOrWhiteSpace([string]$r.Error)
        Assert-Check $ok "${Label}: Undo sem BackupData falha explicitamente" | Out-Null
        return $ok
    } catch {
        Write-Host "  [FALHA] ${Label}: provider deixou excecao escapar: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Host 'ERRO: abra o Windows PowerShell como Administrador e rode novamente.' -ForegroundColor Red
    exit 3
}

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Win-Slim Suite - FASE 2.1B Provider Conformance' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "Root: $root"
Write-Host "Relatorio: $reportPath"

# ---------------------------------------------------------------------------
# CORE CONTRACT / VERIFY
# ---------------------------------------------------------------------------
Write-Host "`n=== CORE: ProviderContract + Verify vazio ===" -ForegroundColor Cyan
$coreOk = $true
$native = Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\cmd.exe" -Arguments @('/d','/c','exit 7')
$coreOk = (Assert-Check ($native.ExitCode -eq 7) 'Invoke-NativeCommand preserva ExitCode=7 sob ErrorActionPreference=Stop') -and $coreOk

$dummy = [PSCustomObject]@{
    id='CONF-EMPTY-VERIFY'; type='script'; rollbackClass=@('Registry');
    InvokeScript=@(); UndoScript=@(); registry=$null
}
$emptyVerify = Test-TweakVerify -Tweak $dummy
$coreOk = (Assert-Check ((-not $emptyVerify.Success) -and $emptyVerify.Applicable -and @($emptyVerify.Checks).Count -eq 0) 'Verify aplicavel com zero checks retorna Success=false') -and $coreOk
Add-ConformanceResult 'Core/Contract' $(if ($coreOk) { 'PASS' } else { 'FAIL' }) 'ExitCode nativo + empty-check guard'

# ---------------------------------------------------------------------------
# REGISTRY PROVIDER
# ---------------------------------------------------------------------------
Write-Host "`n=== RegistryProvider ===" -ForegroundColor Cyan
$regOk = $true
$regPath = 'HKCU:\Software\WinSlimSuite\_Fase21BConformance'
$regName = 'ProviderConformanceValue'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
$regOps = @([PSCustomObject]@{ Path=$regPath; Name=$regName; Value=1; Type='DWord' })
try {
    $regOk = (Test-NegativeUndo { Invoke-RegistryProvider -Id 'CONF-REG-NEG' -RegistryOps $regOps -Action 'Undo' } 'RegistryProvider') -and $regOk
    $apply = Invoke-RegistryProvider -Id 'CONF-REG' -RegistryOps $regOps -Action 'Apply'
    $regOk = (Assert-Check (Test-ProviderResultContract $apply) 'Contrato ProviderResult completo') -and $regOk
    $regOk = (Assert-Check ($apply.Success -and $apply.Verification.Success) 'Apply + Verify') -and $regOk
    $regOk = (Assert-Check (-not $apply.StateBefore[0].Exists) 'Backup preservou Exists=false') -and $regOk

    # Idempotencia: aplicar de novo nao pode destruir o primeiro snapshot usado no rollback.
    $second = Invoke-RegistryProvider -Id 'CONF-REG-IDEMP' -RegistryOps $regOps -Action 'Apply'
    $regOk = (Assert-Check ($second.Success -and $second.Verification.Success) 'Segundo Apply no mesmo estado continua verificavel') -and $regOk

    $undo = Invoke-RegistryProvider -Id 'CONF-REG' -RegistryOps $regOps -Action 'Undo' -BackupData $apply.StateBefore
    $afterUndo = Get-RegistryState -Path $regPath -Name $regName
    $regOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and -not $afterUndo.Exists) 'Undo com PRIMEIRO backup remove valor originalmente inexistente') -and $regOk

    # Cross-process real: Apply no processo pai, Undo em outro powershell.exe.
    $xName = 'CrossProcessValue'
    Remove-ItemProperty -Path $regPath -Name $xName -ErrorAction SilentlyContinue
    $xOps = @([PSCustomObject]@{ Path=$regPath; Name=$xName; Value=1; Type='DWord' })
    $xApply = Invoke-RegistryProvider -Id 'CONF-REG-XPROC' -RegistryOps $xOps -Action 'Apply'
    $xFile = Join-Path $backupDir "registry-crossprocess-$stamp.json"
    [PSCustomObject]@{ Path=$regPath; Name=$xName; BackupData=@($xApply.StateBefore) } | ConvertTo-Json -Depth 8 | Set-Content -Path $xFile -Encoding UTF8
    $psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -CrossProcessChild -BackupFile $xFile
    $childExit = $LASTEXITCODE
    $xAfter = Get-RegistryState -Path $regPath -Name $xName
    $regOk = (Assert-Check ($childExit -eq 0 -and -not $xAfter.Exists) 'Cross-process: novo PowerShell restaurou backup persistido') -and $regOk
} catch {
    Write-Host "  [FALHA] RegistryProvider: $($_.Exception.Message)" -ForegroundColor Red
    $regOk = $false
} finally {
    Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $regPath -Name 'CrossProcessValue' -ErrorAction SilentlyContinue
    Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
}
Add-ConformanceResult 'RegistryProvider' $(if ($regOk) { 'PASS' } else { 'FAIL' }) 'inclui idempotencia e cross-process'

# ---------------------------------------------------------------------------
# COMMAND PROVIDER / FSUTIL
# ---------------------------------------------------------------------------
Write-Host "`n=== CommandProvider / fsutil ===" -ForegroundColor Cyan
$cmdOk = $true
try {
    $cmdOk = (Test-NegativeUndo { Invoke-FsutilOddEvenProvider -Id 'CONF-CMD-NEG' -Setting 'disablelastaccess' -Action 'Undo' } 'CommandProvider') -and $cmdOk
    $before = Get-FsutilBehaviorState -Setting 'disablelastaccess'
    $cmdOk = (Assert-Check $before.Queryable 'Detect fsutil queryable') -and $cmdOk
    if ($before.Queryable) {
        $apply = Invoke-FsutilOddEvenProvider -Id 'CONF-CMD' -Setting 'disablelastaccess' -TargetValue $before.Value -Action 'Apply'
        $cmdOk = (Assert-Check ($apply.Success -and $apply.Verification.Success) 'Apply/Verify usando o valor atual (teste sem mudanca semantica)') -and $cmdOk
        $undo = Invoke-FsutilOddEvenProvider -Id 'CONF-CMD' -Setting 'disablelastaccess' -Action 'Undo' -BackupData $apply.StateBefore
        $after = Get-FsutilBehaviorState -Setting 'disablelastaccess'
        $cmdOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $after.Value -eq $before.Value) 'Undo restaurou valor EXATO') -and $cmdOk
        $cmdOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $cmdOk
    }
} catch {
    Write-Host "  [FALHA] CommandProvider: $($_.Exception.Message)" -ForegroundColor Red
    $cmdOk = $false
}
Add-ConformanceResult 'CommandProvider' $(if ($cmdOk) { 'PASS' } else { 'FAIL' }) 'fsutil + ExitCode nativo'

# ---------------------------------------------------------------------------
# SERVICE PROVIDER - usa servico TEMPORARIO, nunca um servico real do usuario.
# ---------------------------------------------------------------------------
Write-Host "`n=== ServiceProvider ===" -ForegroundColor Cyan
$svcOk = $true
$svcName = "WinSlimConformance_$PID"
$svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$svcName"
try {
    $old = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($old) { Invoke-NativeCommand -FilePath 'sc.exe' -Arguments @('delete',$svcName) | Out-Null; Start-Sleep -Milliseconds 300 }
    New-Service -Name $svcName -BinaryPathName "$env:SystemRoot\System32\cmd.exe /c exit 0" -DisplayName $svcName -StartupType Manual | Out-Null
    New-ItemProperty -Path $svcReg -Name 'DelayedAutostart' -PropertyType DWord -Value 1 -Force | Out-Null
    $svcOps = @([PSCustomObject]@{ Name=$svcName; StartupType='Disabled' })
    $original = Get-ServiceState -Name $svcName
    $svcOk = (Assert-Check ($original.Exists -and $original.StartupType -eq 'Manual' -and $original.DelayedAutoStart) 'Pre-condicao: temporario Manual + DelayedAutoStart=True') -and $svcOk
    $svcOk = (Test-NegativeUndo { Invoke-ServiceProvider -Id 'CONF-SVC-NEG' -ServiceOps $svcOps -Action 'Undo' } 'ServiceProvider') -and $svcOk

    $apply = Invoke-ServiceProvider -Id 'CONF-SVC' -ServiceOps $svcOps -Action 'Apply'
    $svcOk = (Assert-Check ($apply.Success -and $apply.Verification.Success) 'Apply Disabled + Verify Startup/Delayed/Status') -and $svcOk
    $undo = Invoke-ServiceProvider -Id 'CONF-SVC' -ServiceOps $svcOps -Action 'Undo' -BackupData $apply.StateBefore
    $restored = Get-ServiceState -Name $svcName
    $exact = $restored.Exists -and $restored.StartupType -eq $original.StartupType -and
             ([bool]$restored.DelayedAutoStart -eq [bool]$original.DelayedAutoStart) -and
             $restored.Status -eq $original.Status
    $svcOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $exact) 'Undo restaurou StartupType + DelayedAutoStart + Status') -and $svcOk
    $svcOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $svcOk
} catch {
    Write-Host "  [FALHA] ServiceProvider: $($_.Exception.Message)" -ForegroundColor Red
    $svcOk = $false
} finally {
    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
    $del = Invoke-NativeCommand -FilePath 'sc.exe' -Arguments @('delete',$svcName)
    Start-Sleep -Milliseconds 200
}
Add-ConformanceResult 'ServiceProvider' $(if ($svcOk) { 'PASS' } else { 'FAIL' }) 'servico temporario; rollback de 3 dimensoes'

# ---------------------------------------------------------------------------
# BCD PROVIDER - bootlog e um booleano de diagnostico de baixo risco.
# Backup completo da BCD e feito antes do Apply.
# ---------------------------------------------------------------------------
Write-Host "`n=== BcdProvider ===" -ForegroundColor Cyan
if ($SkipBcd) {
    Write-Host '  [SKIP] solicitado por -SkipBcd' -ForegroundColor Yellow
    Add-ConformanceResult 'BcdProvider' 'SKIP' 'usuario solicitou skip'
} else {
    $bcdOk = $true
    $element = 'bootlog'
    $baseline = $null
    $apply = $null
    try {
        $neg = Invoke-BcdProvider -Id 'CONF-BCD-NEG' -Element $element -TargetValue 'true' -Action 'Undo'
        $bcdOk = (Assert-Check ((-not $neg.Success) -and -not [string]::IsNullOrWhiteSpace([string]$neg.Error)) 'Undo sem BackupData falha explicitamente') -and $bcdOk

        $baseline = Get-BcdElementState -Element $element
        $bcdOk = (Assert-Check $baseline.Queryable 'Detect BCD {current} queryable') -and $bcdOk
        if ($baseline.Queryable) {
            $baseNorm = Normalize-BcdComparableValue -Value $baseline.Value
            $target = if ($baseline.Exists -and $baseNorm -eq 'true') { 'false' } else { 'true' }
            $apply = Invoke-BcdProvider -Id 'CONF-BCD' -Element $element -TargetValue $target -Action 'Apply'
            $exportOk = (($apply.StateBefore.PSObject.Properties.Name -contains 'BcdExportPath') -and (Test-Path $apply.StateBefore.BcdExportPath))
            $bcdOk = (Assert-Check $exportOk 'Backup completo BCD exportado antes do Apply') -and $bcdOk
            $bcdOk = (Assert-Check ($apply.Success -and $apply.Verification.Success) 'Apply bootlog + Verify') -and $bcdOk

            $undo = Invoke-BcdProvider -Id 'CONF-BCD' -Element $element -Action 'Undo' -BackupData $apply.StateBefore
            $exact = Test-BcdElementValue -Element $element -ExpectedValue $baseline.Value -ExpectedExists $baseline.Exists
            $bcdOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $exact.Pass) 'Undo restaurou existencia/valor original exatos') -and $bcdOk
            $bcdOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $bcdOk
        }
    } catch {
        Write-Host "  [FALHA] BcdProvider: $($_.Exception.Message)" -ForegroundColor Red
        $bcdOk = $false
    } finally {
        if ($baseline -and $baseline.Queryable) {
            try { Restore-BcdElementState -StateBefore $baseline } catch { Write-Host "  [WARN] restauracao de emergencia BCD falhou: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    Add-ConformanceResult 'BcdProvider' $(if ($bcdOk) { 'PASS' } else { 'FAIL' }) 'bootlog temporario + export BCD + rollback exato'
}

# ---------------------------------------------------------------------------
# POWERCFG PROVIDER - usa timeout de video e restaura AC/DC exatos.
# ---------------------------------------------------------------------------
Write-Host "`n=== PowerCfgProvider ===" -ForegroundColor Cyan
if ($SkipPowerCfg) {
    Write-Host '  [SKIP] solicitado por -SkipPowerCfg' -ForegroundColor Yellow
    Add-ConformanceResult 'PowerCfgProvider' 'SKIP' 'usuario solicitou skip'
} else {
    $pwrOk = $true
    $subVideo = '7516b95f-f776-4464-8c53-06167f40cc99'
    $videoIdle = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
    $baseline = $null
    try {
        $neg = Invoke-PowerCfgProvider -Id 'CONF-PWR-NEG' -Mode 'SettingIndex' -SubgroupGuid $subVideo -SettingGuid $videoIdle -Action 'Undo'
        $pwrOk = (Assert-Check ((-not $neg.Success) -and -not [string]::IsNullOrWhiteSpace([string]$neg.Error)) 'Undo sem BackupData falha explicitamente') -and $pwrOk

        $baseline = Get-PowerSettingIndex -SubgroupGuid $subVideo -SettingGuid $videoIdle
        $pwrOk = (Assert-Check $baseline.Queryable 'Detect AC/DC funciona sem depender do idioma do powercfg') -and $pwrOk
        if ($baseline.Queryable) {
            $targetAc = if ($baseline.AC -eq 60) { 120 } else { 60 }
            $targetDc = if ($baseline.DC -eq 60) { 120 } else { 60 }
            $apply = Invoke-PowerCfgProvider -Id 'CONF-PWR' -Mode 'SettingIndex' -SubgroupGuid $subVideo -SettingGuid $videoIdle -TargetAc $targetAc -TargetDc $targetDc -Action 'Apply'
            $pwrOk = (Assert-Check ($apply.Success -and $apply.Verification.Success -and @($apply.Verification.Checks).Count -gt 0) 'Apply + Verify AC e DC com check nao vazio') -and $pwrOk
            $undo = Invoke-PowerCfgProvider -Id 'CONF-PWR' -Mode 'SettingIndex' -SubgroupGuid $subVideo -SettingGuid $videoIdle -Action 'Undo' -BackupData $apply.StateBefore
            $after = Get-PowerSettingIndex -SubgroupGuid $subVideo -SettingGuid $videoIdle
            $exact = $after.Queryable -and $after.AC -eq $baseline.AC -and $after.DC -eq $baseline.DC
            $pwrOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $exact) 'Undo restaurou indices AC/DC exatos') -and $pwrOk
            $pwrOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $pwrOk
        }
    } catch {
        Write-Host "  [FALHA] PowerCfgProvider: $($_.Exception.Message)" -ForegroundColor Red
        $pwrOk = $false
    } finally {
        if ($baseline -and $baseline.Queryable) {
            try { Set-PowerSettingIndex -SubgroupGuid $subVideo -SettingGuid $videoIdle -AcValue $baseline.AC -DcValue $baseline.DC } catch { Write-Host "  [WARN] restauracao de emergencia PowerCfg falhou: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    Add-ConformanceResult 'PowerCfgProvider' $(if ($pwrOk) { 'PASS' } else { 'FAIL' }) 'VIDEOIDLE temporario; AC/DC exatos; parser locale-neutral'
}

# ---------------------------------------------------------------------------
# NETWORK PROVIDER - Nagle por InterfaceGuid, com rollback de todos os valores.
# ---------------------------------------------------------------------------
Write-Host "`n=== NetworkProvider ===" -ForegroundColor Cyan
if ($SkipNetwork) {
    Write-Host '  [SKIP] solicitado por -SkipNetwork' -ForegroundColor Yellow
    Add-ConformanceResult 'NetworkProvider' 'SKIP' 'usuario solicitou skip'
} else {
    $netOk = $true
    $baseline = @()
    try {
        $adapters = @(Get-ActivePhysicalAdapters)
        if ($adapters.Count -eq 0) {
            Write-Host '  [FALHA] nenhum adaptador fisico ativo; provider nao pode ser validado nesta maquina.' -ForegroundColor Red
            $netOk = $false
        } else {
            foreach ($a in $adapters) { $baseline += (Get-NicTcpState -InterfaceGuid $a.InterfaceGuid) }
            $baseline | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $backupDir "network-before-$stamp.json") -Encoding UTF8
            $neg = Invoke-NetworkNagleProvider -Id 'CONF-NET-NEG' -Action 'Undo'
            $netOk = (Assert-Check ((-not $neg.Success) -and -not [string]::IsNullOrWhiteSpace([string]$neg.Error)) 'Undo sem BackupData falha explicitamente') -and $netOk

            $apply = Invoke-NetworkNagleProvider -Id 'CONF-NET' -Action 'Apply'
            $netOk = (Assert-Check ($apply.Success -and $apply.Verification.Success -and @($apply.Verification.Checks).Count -eq $adapters.Count) 'Apply/Verify gerou um check por InterfaceGuid') -and $netOk
            $undo = Invoke-NetworkNagleProvider -Id 'CONF-NET' -Action 'Undo' -BackupData $apply.StateBefore
            $allExact = $true
            foreach ($ref in $baseline) {
                $now = Get-NicTcpState -InterfaceGuid $ref.InterfaceGuid
                if (-not (Test-NicStateEqual $ref $now)) { $allExact = $false }
            }
            $netOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $allExact) 'Undo restaurou TcpNoDelay/TcpAckFrequency/TcpDelAckTicks por GUID') -and $netOk
            if ($adapters.Count -ge 2) {
                $unique = @($baseline | Select-Object -ExpandProperty InterfaceGuid -Unique).Count -eq $baseline.Count
                $netOk = (Assert-Check $unique 'Subteste multi-adapter: snapshots independentes por GUID') -and $netOk
            } else {
                Write-Host '  [INFO] somente 1 adaptador fisico ativo; subteste multi-adapter nao se aplica.' -ForegroundColor DarkGray
            }
            $netOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $netOk
        }
    } catch {
        Write-Host "  [FALHA] NetworkProvider: $($_.Exception.Message)" -ForegroundColor Red
        $netOk = $false
    } finally {
        foreach ($ref in @($baseline)) {
            try { Restore-NicTcpState -StateBefore $ref } catch { Write-Host "  [WARN] restauracao de emergencia da interface $($ref.InterfaceGuid) falhou." -ForegroundColor Yellow }
        }
    }
    Add-ConformanceResult 'NetworkProvider' $(if ($netOk) { 'PASS' } else { 'FAIL' }) 'rollback completo por InterfaceGuid'
}

# ---------------------------------------------------------------------------
# SCHEDULED TASK PROVIDER - cria tarefa TEMPORARIA e testa Unregister + XML Undo.
# ---------------------------------------------------------------------------
Write-Host "`n=== ScheduledTaskProvider ===" -ForegroundColor Cyan
$taskOk = $true
$taskName = "WinSlim_Conformance_$PID"
$taskPath = '\'
try {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\cmd.exe" -Argument '/d /c exit 0'
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Description 'Win-Slim Fase 2.1B temporary conformance task' -Force | Out-Null
    $original = Get-ScheduledTaskState -TaskName $taskName -TaskPath $taskPath
    $sigBefore = Get-TaskSemanticSignature -XmlText $original.Xml
    $taskOk = (Assert-Check ($original.Exists -and -not [string]::IsNullOrWhiteSpace($original.Xml) -and $sigBefore) 'Pre-condicao: tarefa temporaria exporta XML') -and $taskOk

    $neg = Invoke-ScheduledTaskProvider -Id 'CONF-TASK-NEG' -TaskName $taskName -TaskPath $taskPath -ApplyMode Unregister -Action Undo
    $taskOk = (Assert-Check ((-not $neg.Success) -and -not [string]::IsNullOrWhiteSpace([string]$neg.Error)) 'Undo sem BackupData falha explicitamente') -and $taskOk

    $apply = Invoke-ScheduledTaskProvider -Id 'CONF-TASK' -TaskName $taskName -TaskPath $taskPath -ApplyMode Unregister -Action Apply
    $taskOk = (Assert-Check ($apply.Success -and $apply.Verification.Success -and -not (Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue)) 'Apply Unregister + Verify ausencia') -and $taskOk
    $undo = Invoke-ScheduledTaskProvider -Id 'CONF-TASK' -TaskName $taskName -TaskPath $taskPath -ApplyMode Unregister -Action Undo -BackupData $apply.StateBefore
    $restored = Get-ScheduledTaskState -TaskName $taskName -TaskPath $taskPath
    $sigAfter = Get-TaskSemanticSignature -XmlText $restored.Xml
    $sameDef = $sigBefore -and $sigAfter -and ($sigBefore -eq $sigAfter)
    $sameEnabled = ($restored.State -ne 'Disabled') -eq ($original.State -ne 'Disabled')
    $taskOk = (Assert-Check ($undo.Success -and $undo.Verification.Success -and $restored.Exists -and $sameDef -and $sameEnabled) 'Undo recriou XML semanticamente equivalente + estado Enabled/Disabled') -and $taskOk
    $taskOk = (Assert-Check (@($undo.Verification.Checks).Count -gt 0) 'Verify do provider nao retorna checks vazios') -and $taskOk
    $taskOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $taskOk
} catch {
    Write-Host "  [FALHA] ScheduledTaskProvider: $($_.Exception.Message)" -ForegroundColor Red
    $taskOk = $false
} finally {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue
}
Add-ConformanceResult 'ScheduledTaskProvider' $(if ($taskOk) { 'PASS' } else { 'FAIL' }) 'tarefa temporaria; XML backup/recreate'

# ---------------------------------------------------------------------------
# APPX PROVIDER - sem remover nenhum AppX real.
# Testa no-op idempotente e politica de Undo honesta.
# ---------------------------------------------------------------------------
Write-Host "`n=== AppxProvider ===" -ForegroundColor Cyan
$appxOk = $true
try {
    $fakePackage = 'WinSlim.Conformance.Package.That.Does.Not.Exist'
    $before = Get-AppxState -PackageName $fakePackage
    $appxOk = (Assert-Check ((-not $before.Installed) -and (-not $before.Provisioned)) 'Pacote ficticio realmente ausente; nenhum AppX real sera removido') -and $appxOk
    $apply = Invoke-AppxProvider -Id 'CONF-APPX' -PackageName $fakePackage -Action Apply
    $appxOk = (Assert-Check ($apply.Success -and -not $apply.Changed -and $apply.Verification.Success) 'Apply idempotente: estado desejado ja existe => Success=true, Changed=false') -and $appxOk
    $undo = Invoke-AppxProvider -Id 'CONF-APPX' -PackageName $fakePackage -Action Undo
    $honest = (-not $undo.Success) -and (-not $undo.Changed) -and (-not $undo.Verification.Success) -and -not [string]::IsNullOrWhiteSpace([string]$undo.Warning)
    $appxOk = (Assert-Check $honest 'Undo sem fonte de reinstalacao falha honestamente com Warning') -and $appxOk
    $appxOk = (Assert-Check (@($undo.Verification.Checks).Count -gt 0) 'Undo AppX inclui check explicito Pass=false') -and $appxOk
    $appxOk = (Assert-Check (Test-ProviderResultContract $undo) 'Contrato ProviderResult completo') -and $appxOk
} catch {
    Write-Host "  [FALHA] AppxProvider: $($_.Exception.Message)" -ForegroundColor Red
    $appxOk = $false
}
Add-ConformanceResult 'AppxProvider' $(if ($appxOk) { 'PASS' } else { 'FAIL' }) 'teste seguro; nenhum pacote real removido'

# ---------------------------------------------------------------------------
# RESUMO / RELATORIO
# ---------------------------------------------------------------------------
Write-Host "`n=== RESUMO FASE 2.1B ===" -ForegroundColor Yellow
$results | Format-Table -AutoSize
$results | ConvertTo-Json -Depth 8 | Set-Content -Path $reportPath -Encoding UTF8

$failures = @($results | Where-Object { $_.Status -eq 'FAIL' })
$skips = @($results | Where-Object { $_.Status -eq 'SKIP' })

if ($failures.Count -eq 0 -and $skips.Count -eq 0) {
    Write-Host 'FASE 2.1B APROVADA - todos os Providers passaram no gate de conformidade.' -ForegroundColor Green
    Write-Host 'Proximo gate: FASE 3 - Transaction Manager.' -ForegroundColor Green
    Write-Host "Relatorio JSON: $reportPath"
    exit 0
}
elseif ($failures.Count -eq 0) {
    Write-Host 'FASE 2.1B PARCIAL - nenhum FAIL, mas houve SKIP. Rode novamente sem skips antes da Fase 3.' -ForegroundColor Yellow
    Write-Host "Relatorio JSON: $reportPath"
    exit 2
}
else {
    Write-Host "FASE 2.1B REPROVADA - $($failures.Count) grupo(s) falharam. Nao iniciar Fase 3 ainda." -ForegroundColor Red
    Write-Host "Relatorio JSON: $reportPath"
    exit 1
}
