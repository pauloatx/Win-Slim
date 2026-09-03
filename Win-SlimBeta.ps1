# ======================================================================
#  Win-Slim.ps1 - Win-Slim by Paulo999x
# ======================================================================
# Requires -RunAsAdministrator

# ----------------------------------------------------------------------
# 0. AUTO-ELEVACAO DE PRIVILEGIOS DE ADMINISTRADOR
# ----------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($PSCommandPath) {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        Write-Host "[!] Erro: Execute o PowerShell como Administrador para abrir a interface." -ForegroundColor Red
    }
    return
}

# Configuracao de DPI e Assemblies para WinForms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----------------------------------------------------------------------
# 1. FUNCOES DE MANIPULACAO DE REGISTRO E SERVICOS
# ----------------------------------------------------------------------
function Set-RegProp {
    param(
        [string]$Path,
        [string]$Name,
        [PSObject]$Value,
        [string]$Type = "DWord"
    )
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction SilentlyContinue
    } catch {}
}

function Remove-RegProp {
    param([string]$Path, [string]$Name)
    try {
        if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue }
    } catch {}
}

function Set-ServiceState {
    param([string]$SvcName, [string]$StartupType, [bool]$Stop = $true)
    if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
        if ($Stop) { Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $SvcName -StartupType $StartupType -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------
# 2. CONSTRUCAO DA INTERFACE GRAFICA (UI)
# ----------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Win-Slim"
$form.Size = New-Object System.Drawing.Size(760, 750)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 8000
$toolTip.InitialDelay = 300

# Titulo
$lblHeader = New-Object System.Windows.Forms.Label
$lblHeader.Text = "Win-Slim"
$lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblHeader.Location = New-Object System.Drawing.Point(20, 12)
$lblHeader.AutoSize = $true
$lblHeader.ForeColor = [System.Drawing.Color]::FromArgb(0, 162, 255)
$form.Controls.Add($lblHeader)

# Container de Abas
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 48)
$tabControl.Size = New-Object System.Drawing.Size(705, 332)
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

$tabOptimization = New-Object System.Windows.Forms.TabPage
$tabOptimization.Text = " Otimizacao Geral "
$tabOptimization.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

$tabComponents = New-Object System.Windows.Forms.TabPage
$tabComponents.Text = " Ativar/Desativar Componentes "
$tabComponents.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

$tabControl.Controls.Add($tabOptimization)
$tabControl.Controls.Add($tabComponents)
$form.Controls.Add($tabControl)

# --- ABA 1: OTIMIZACAO GERAL ---
function New-OptCheckBox {
    param([string]$Text, [int]$X, [int]$Y, [string]$Tip, $Parent)
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $Text
    $cb.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point($X, $Y)
    $cb.Checked = $true
    $cb.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $toolTip.SetToolTip($cb, $Tip)
    $Parent.Controls.Add($cb)
    return $cb
}

$chkRestorePoint = New-OptCheckBox "Criar Ponto de Restauracao" 20 15 "Cria um ponto de restauracao no disco C: por seguranca." $tabOptimization
$chkRemoveAI     = New-OptCheckBox "Eliminar Recursos de IA (Copilot/Recall)" 20 48 "Remove o Copilot, Recall, Windows AI e desativa atalhos nativos." $tabOptimization
$chkTelemetry    = New-OptCheckBox "Zerar Telemetria e Keylogging" 20 81 "Desativa envio de dados, rastreamento de digitacao e historico." $tabOptimization
$chkBloatware    = New-OptCheckBox "Remover Bloatware / Apps UWP" 20 114 "Desinstala apps desnecessarios de fabrica (Noticias, Xbox, Clima, etc.)." $tabOptimization
$chkServices     = New-OptCheckBox "Desativar Servicos Redundantes" 20 147 "Desabilita servicos nao essenciais (SysMain, Telemetria, Maps Broker) com seguranca." $tabOptimization

$chkLatency      = New-OptCheckBox "Ajustar Latencia da CPU, RAM e GPU" 340 15 "Ajusta Win32PrioritySeparation, prioridade de jogos e fixa Kernel na RAM." $tabOptimization
$chkVisuals      = New-OptCheckBox "Ajustar Efeitos Visuais" 340 48 "Remove animacoes lentas mantendo fontes limpas e legiveis." $tabOptimization
$chkNetworkPower = New-OptCheckBox "Otimizar Rede e Energia" 340 81 "Desativa Network Throttling e ativa o plano Ultimate Performance." $tabOptimization
$chkCleanup      = New-OptCheckBox "Limpeza de Cache e DISM" 340 114 "Limpa pastas Temp e compacta base do Windows via DISM." $tabOptimization
$chkAutoReboot   = New-OptCheckBox "Reiniciar Automatico ao Finalizar" 340 147 "Reinicia o computador automaticamente assim que o script terminar." $tabOptimization
$chkAutoReboot.Checked = $false
$chkAutoReboot.ForeColor = [System.Drawing.Color]::FromArgb(255, 185, 0)

$btnSelectAll = New-Object System.Windows.Forms.Button
$btnSelectAll.Text = "Marcar Todos"
$btnSelectAll.Location = New-Object System.Drawing.Point(20, 250)
$btnSelectAll.Size = New-Object System.Drawing.Size(110, 28)
$btnSelectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSelectAll.ForeColor = [System.Drawing.Color]::LightGray
$tabOptimization.Controls.Add($btnSelectAll)

$btnUnselectAll = New-Object System.Windows.Forms.Button
$btnUnselectAll.Text = "Desmarcar Todos"
$btnUnselectAll.Location = New-Object System.Drawing.Point(140, 250)
$btnUnselectAll.Size = New-Object System.Drawing.Size(120, 28)
$btnUnselectAll.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnUnselectAll.ForeColor = [System.Drawing.Color]::LightGray
$tabOptimization.Controls.Add($btnUnselectAll)

# --- ABA 2: GERENCIAMENTO DE COMPONENTES ---
function New-ComponentRow {
    param([string]$Title, [int]$Y, $Parent, [scriptblock]$DisableAction, [scriptblock]$EnableAction)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Title
    $lbl.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point(20, $Y)
    $lbl.AutoSize = $true
    $lbl.ForeColor = [System.Drawing.Color]::White
    $Parent.Controls.Add($lbl)

    $btnDis = New-Object System.Windows.Forms.Button
    $btnDis.Text = "DESATIVAR"
    $btnDis.Location = New-Object System.Drawing.Point(380, ($Y - 4))
    $btnDis.Size = New-Object System.Drawing.Size(130, 30)
    $btnDis.BackColor = [System.Drawing.Color]::FromArgb(180, 45, 45)
    $btnDis.ForeColor = [System.Drawing.Color]::White
    $btnDis.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnDis.FlatAppearance.BorderSize = 0
    $btnDis.Add_Click($DisableAction)
    $Parent.Controls.Add($btnDis)

    $btnEna = New-Object System.Windows.Forms.Button
    $btnEna.Text = "REATIVAR"
    $btnEna.Location = New-Object System.Drawing.Point(525, ($Y - 4))
    $btnEna.Size = New-Object System.Drawing.Size(130, 30)
    $btnEna.BackColor = [System.Drawing.Color]::FromArgb(40, 140, 60)
    $btnEna.ForeColor = [System.Drawing.Color]::White
    $btnEna.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnEna.FlatAppearance.BorderSize = 0
    $btnEna.Add_Click($EnableAction)
    $Parent.Controls.Add($btnEna)
}

# 1. Windows Update
New-ComponentRow "Windows Update & Servicos de Atualizacao" 25 $tabComponents `
    -DisableAction {
        Log-Write "Desativando Windows Update e WaaSMedicSvc..."
        @("wuauserv", "bits", "dosvc", "usoSvc") | ForEach-Object { Set-ServiceState -SvcName $_ -StartupType "Disabled" }
        
        Set-RegProp -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Value 4
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1
        Log-Write "[OK] Windows Update totalmente DESATIVADO."
    } `
    -EnableAction {
        Log-Write "Reativando Windows Update..."
        Set-RegProp -Path "HKLM:\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc" -Name "Start" -Value 3
        Set-ServiceState -SvcName "wuauserv" -StartupType "Manual" -Stop $false
        Set-ServiceState -SvcName "bits" -StartupType "Manual" -Stop $false
        Set-ServiceState -SvcName "dosvc" -StartupType "Automatic" -Stop $false
        Set-ServiceState -SvcName "usoSvc" -StartupType "Automatic" -Stop $false
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate"
        Log-Write "[OK] Windows Update e dependencias REATIVADOS."
    }

# 2. Windows Defender
New-ComponentRow "Windows Defender (Protecao Nativa)" 85 $tabComponents `
    -DisableAction {
        Log-Write "Desativando Protecoes do Windows Defender..."
        Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -DisableOnAccessProtection $true -ErrorAction SilentlyContinue
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 1
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring" -Value 1
        Log-Write "[OK] Protecao em tempo real do Defender DESATIVADA."
    } `
    -EnableAction {
        Log-Write "Reativando Windows Defender..."
        Set-MpPreference -DisableRealtimeMonitoring $false -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -DisableOnAccessProtection $false -ErrorAction SilentlyContinue
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware"
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableRealtimeMonitoring"
        Log-Write "[OK] Protecoes do Windows Defender REATIVADAS."
    }

# 3. Microsoft Store
New-ComponentRow "Microsoft Store & Servicos de Download" 145 $tabComponents `
    -DisableAction {
        Log-Write "Desativando Microsoft Store..."
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "RemoveWindowsStore" -Value 1
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "DisableStoreApps" -Value 1
        Set-ServiceState -SvcName "InstallService" -StartupType "Disabled"
        Log-Write "[OK] Microsoft Store DESATIVADA."
    } `
    -EnableAction {
        Log-Write "Reativando Microsoft Store..."
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "RemoveWindowsStore"
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "DisableStoreApps"
        Set-ServiceState -SvcName "InstallService" -StartupType "Manual" -Stop $false
        Log-Write "[OK] Microsoft Store REATIVADA."
    }

# 4. Xbox & Barra de Jogo
New-ComponentRow "Xbox Live, Game Bar & GameDVR" 205 $tabComponents `
    -DisableAction {
        Log-Write "Desativando Xbox Services e GameDVR..."
        @("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc") | ForEach-Object { Set-ServiceState -SvcName $_ -StartupType "Disabled" }
        Set-RegProp -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0
        Log-Write "[OK] Xbox e captura em segundo plano DESATIVADOS."
    } `
    -EnableAction {
        Log-Write "Reativando Xbox Services e GameDVR..."
        @("XblAuthManager", "XblGameSave", "XboxNetApiSvc", "XboxGipSvc") | ForEach-Object { Set-ServiceState -SvcName $_ -StartupType "Manual" -Stop $false }
        Set-RegProp -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1
        Remove-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR"
        Log-Write "[OK] Xbox e Barra de Jogo REATIVADOS."
    }

# Barra de Progresso e Log Console
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 390)
$progressBar.Size = New-Object System.Drawing.Size(705, 12)
$form.Controls.Add($progressBar)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Location = New-Object System.Drawing.Point(20, 410)
$txtLog.Size = New-Object System.Drawing.Size(705, 220)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(0, 230, 120)
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Text = "--- WIN-SLIM PRONTO ---`r`nEscolha as opcoes e clique no botao abaixo para iniciar."
$form.Controls.Add($txtLog)

# Botoes de Acao Inferiores
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "INICIAR OTIMIZACAO GERAL"
$btnApply.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnApply.Location = New-Object System.Drawing.Point(20, 645)
$btnApply.Size = New-Object System.Drawing.Size(540, 45)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApply.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnApply)

$btnReboot = New-Object System.Windows.Forms.Button
$btnReboot.Text = "REINICIAR AGORA"
$btnReboot.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnReboot.Location = New-Object System.Drawing.Point(575, 645)
$btnReboot.Size = New-Object System.Drawing.Size(150, 45)
$btnReboot.BackColor = [System.Drawing.Color]::FromArgb(180, 40, 40)
$btnReboot.ForeColor = [System.Drawing.Color]::White
$btnReboot.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnReboot.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnReboot)

# ----------------------------------------------------------------------
# 3. LOGICA PRINCIPAL DE PROCESSAMENTO
# ----------------------------------------------------------------------
function Log-Write {
    param([string]$Msg)
    $timestamp = (Get-Date).ToString("HH:mm:ss")
    $txtLog.AppendText("`r`n[$timestamp] $Msg")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

$btnSelectAll.Add_Click({
    foreach ($ctl in $tabOptimization.Controls) {
        if ($ctl -is [System.Windows.Forms.CheckBox]) { $ctl.Checked = $true }
    }
})

$btnUnselectAll.Add_Click({
    foreach ($ctl in $tabOptimization.Controls) {
        if ($ctl -is [System.Windows.Forms.CheckBox]) { $ctl.Checked = $false }
    }
})

$btnReboot.Add_Click({ Restart-Computer -Force })

# Execucao das Otimizacoes
$btnApply.Add_Click({
    $btnApply.Enabled = $false
    $progressBar.Value = 0
    $txtLog.Text = "Iniciando otimizacao do sistema via Win-Slim..."

    $steps = 0; $completed = 0
    if ($chkRestorePoint.Checked) { $steps++ }
    if ($chkRemoveAI.Checked)     { $steps++ }
    if ($chkTelemetry.Checked)    { $steps++ }
    if ($chkBloatware.Checked)    { $steps++ }
    if ($chkServices.Checked)     { $steps++ }
    if ($chkLatency.Checked)      { $steps++ }
    if ($chkVisuals.Checked)      { $steps++ }
    if ($chkNetworkPower.Checked) { $steps++ }
    if ($chkCleanup.Checked)      { $steps++ }

    if ($steps -eq 0) {
        Log-Write "Nenhuma opcao de otimizacao foi selecionada."
        $btnApply.Enabled = $true
        return
    }

    # 1. Ponto de Restauracao
    if ($chkRestorePoint.Checked) {
        Log-Write "Criando Ponto de Restauracao..."
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "Win-Slim-RestorePoint" -RestorePointType "MODIFY_SETTINGS" -ErrorAction SilentlyContinue
            Log-Write "[OK] Ponto de Restauracao registrado."
        } catch { Log-Write "[!] Falha ao criar ponto de restauracao (ignorando)." }
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 2. Remocao de IA
    if ($chkRemoveAI.Checked) {
        Log-Write "Desativando Copilot, Recall e Servicos de IA..."
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
        Set-RegProp -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
        Set-RegProp -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
        Set-RegProp -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisabledHotkeys" -Value "C" -Type "String"
        Log-Write "[OK] Copilot e IA bloqueados."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 3. Telemetria
    if ($chkTelemetry.Checked) {
        Log-Write "Desativando Telemetria, Coleta de Digitacao e Rastreamento..."
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo" -Name "DisabledByGroupPolicy" -Value 1
        Set-RegProp -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1
        Set-RegProp -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1
        Set-RegProp -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 0
        Log-Write "[OK] Telemetria e rastreadores zerados."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 4. Bloatware
    if ($chkBloatware.Checked) {
        Log-Write "Mapeando e removendo Bloatwares (Modo Rapido)..."
        $BloatwareList = @(
            "BingNews", "BingWeather", "GetHelp", "Getstarted", "MicrosoftOfficeHub",
            "MicrosoftSolitaireCollection", "People", "PowerAutomateDesktop", "SkypeApp",
            "Todos", "WindowsFeedbackHub", "YourPhone", "ZuneMusic", "ZuneVideo",
            "Clipchamp", "Disney", "Spotify", "TikTok", "Cortana", "BingSearch", "3DBuilder"
        )
        
        $installedApps = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue
        $provisionedApps = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

        foreach ($App in $BloatwareList) {
            $installedApps | Where-Object { $_.Name -like "*$App*" } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
            $provisionedApps | Where-Object { $_.DisplayName -like "*$App*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
        }
        Log-Write "[OK] Bloatwares desinstalados rapidamente."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 5. Servicos Redundantes
    if ($chkServices.Checked) {
        Log-Write "Desativando servicos de fundo desnecessarios..."
        $ServicesToDisable = @("DiagTrack", "dmwappushservice", "MapsBroker", "RemoteRegistry", "WerSvc", "PcaSvc", "TrkWks", "Fax", "RetailDemo", "wisvc", "SemgrSvc", "SysMain", "lfsvc")
        foreach ($Svc in $ServicesToDisable) {
            Set-ServiceState -SvcName $Svc -StartupType "Disabled"
        }
        Log-Write "[OK] Servicos desativados preservando a estabilidade."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 6. Latencia da CPU, RAM e Registro
    if ($chkLatency.Checked) {
        Log-Write "Configurando Win32PrioritySeparation e ajustando resposta da CPU..."
        Set-RegProp -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38
        Set-RegProp -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -Type "String"
        Set-RegProp -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Value "1" -Type "String"
        Set-RegProp -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Type "String"
        Set-RegProp -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1
        
        $sysProfile = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-RegProp -Path $sysProfile -Name "SystemResponsiveness" -Value 0
        Set-RegProp -Path "$sysProfile\Tasks\Games" -Name "GPU Priority" -Value 8
        Set-RegProp -Path "$sysProfile\Tasks\Games" -Name "Priority" -Value 6
        
        Log-Write "[OK] Parametros de baixa latencia aplicados."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 7. Efeitos Visuais
    if ($chkVisuals.Checked) {
        Log-Write "Ajustando efeitos visuais..."
        Set-RegProp -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type "Binary"
        Set-RegProp -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2
        Log-Write "[OK] Animacoes e efeitos ajustados para maxima fluidez."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 8. Rede e Perfil de Energia
    if ($chkNetworkPower.Checked) {
        Log-Write "Otimizando rede TCP e ativando Desempenho Maximo..."
        Set-RegProp -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 4294967295
        netsh int tcp set global autotuninglevel=normal | Out-Null
        
        $pOut = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
        if ($pOut -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
            powercfg /setactive $matches[1] | Out-Null
        } else {
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a15-7e6d57243573 | Out-Null
        }
        Log-Write "[OK] Otimizacoes de Rede e Energia concluidas."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    # 9. Limpeza e DISM
    if ($chkCleanup.Checked) {
        Log-Write "Limpando caches do sistema e reduzindo base do DISM..."
        $TempFolders = @($env:TEMP, "C:\Windows\Temp", "C:\Windows\Prefetch", "C:\Windows\SoftwareDistribution\Download")
        foreach ($Folder in $TempFolders) {
            if (Test-Path $Folder) { Remove-Item -Path "$Folder\*" -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Start-Process "dism.exe" -ArgumentList "/Online /Cleanup-Image /StartComponentCleanup /ResetBase" -NoNewWindow -Wait -ErrorAction SilentlyContinue
        Log-Write "[OK] Limpeza de disco e componentes finalizada."
        $completed++; $progressBar.Value = [int](($completed / $steps) * 100)
    }

    Log-Write "`r`n=========================================="
    Log-Write "   WIN-SLIM CONCLUIDO COM SUCESSO!"
    Log-Write "=========================================="
    
    $btnApply.Enabled = $true

    if ($chkAutoReboot.Checked) {
        Log-Write "`r`nReiniciando o sistema em 5 segundos..."
        for ($i = 5; $i -gt 0; $i--) {
            Log-Write "Reiniciando em $i..."
            Start-Sleep -Seconds 1
        }
        Restart-Computer -Force
    }
})

# Exibir Janela
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()