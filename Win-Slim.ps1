<#
.SYNOPSIS
    Win-Slim (Win 10 & Win 11 Auto-Detect)
    Focado em responsividade extrema, baixo input lag e RAM livre.
#>

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $scriptContent = $MyInvocation.MyCommand.Definition
    if ($scriptContent) {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$scriptContent`"" -Verb RunAs
    } else {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    return
}

$osBuild = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
$osName = if ($osBuild -ge 22000) { "Windows 11" } else { "Windows 10" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Set-RegProp {
    param ([string]$Path, [string]$Name, [PSObject]$Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force | Out-Null
    } catch {}
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Win-Slim ($osName Detectado)"
$form.Size = New-Object System.Drawing.Size(560, 740)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)
$form.ForeColor = [System.Drawing.Color]::White
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Win-Slim - $osName"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.AutoSize = $true
$lblTitle.ForeColor = if ($osBuild -ge 22000) { [System.Drawing.Color]::MediumPurple } else { [System.Drawing.Color]::DeepSkyBlue }
$form.Controls.Add($lblTitle)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(20, 60)
$tabControl.Size = New-Object System.Drawing.Size(505, 340)

$tabOS = New-Object System.Windows.Forms.TabPage
$tabOS.Text = "Especifico: $osName"
$tabOS.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)

$tabPerf = New-Object System.Windows.Forms.TabPage
$tabPerf.Text = "Core Performance"
$tabPerf.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)

$tabRAM = New-Object System.Windows.Forms.TabPage
$tabRAM.Text = "Servicos & RAM"
$tabRAM.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 25)

$tabControl.Controls.Add($tabOS)
$tabControl.Controls.Add($tabPerf)
$tabControl.Controls.Add($tabRAM)
$form.Controls.Add($tabControl)

$checkboxes = @()

function Add-Option ($tab, $text, $tag, $y, $checked = $true) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $text
    $chk.Tag = $tag
    $chk.Location = New-Object System.Drawing.Point(15, $y)
    $chk.Size = New-Object System.Drawing.Size(470, 25)
    $chk.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
    $chk.ForeColor = [System.Drawing.Color]::White
    $chk.Checked = $checked
    $tab.Controls.Add($chk)
    $script:checkboxes += $chk
}

if ($osBuild -ge 22000) {
    Add-Option $tabOS "Desativar VBS e Integridade de Memoria (Aumenta FPS drasticamente)" "W11_VBS" 20
    Add-Option $tabOS "Restaurar Menu de Contexto Classico (Elimina lag do clique direito)" "W11_Context" 60
    Add-Option $tabOS "Desativar Copilot, Recall e IA Nativa" "W11_AI" 100
    Add-Option $tabOS "Remover Widgets e Telemetria da Barra de Tarefas" "W11_Widgets" 140
    Add-Option $tabOS "Desativar Animacoes Pesadas e Efeito Mica/Acrilico" "W11_UI" 180
} else {
    Add-Option $tabOS "Desativar Noticias e Interesses (Consumo excessivo de CPU/RAM)" "W10_Feeds" 20
    Add-Option $tabOS "Desativar Cortana Completamente (Registro e Servico)" "W10_Cortana" 60
    Add-Option $tabOS "Desativar Telemetria de Compatibilidade e DiagTrack" "W10_Telemetry" 100
    Add-Option $tabOS "Remover 'Objetos 3D' do Explorador de Arquivos" "W10_Explorer" 140
    Add-Option $tabOS "Otimizar Transparencia do Action Center (Mais fluidez)" "W10_UI" 180
}

Add-Option $tabPerf "Aplicar Plano 'Desempenho Maximo' e forcar C-States" "Core_Power" 20
Add-Option $tabPerf "Injetar SystemResponsiveness=0 & Win32PrioritySeparation" "Core_Resp" 60
Add-Option $tabPerf "Habilitar HAGS (Hardware-Accelerated GPU Scheduling)" "Core_HAGS" 100
Add-Option $tabPerf "Desativar Network Throttling e Otimizar TCP (Menor Ping/Latencia)" "Core_Network" 140
Add-Option $tabPerf "Desativar Mitigacoes de Spectre/Meltdown (Aviso: Reduz seguranca, aumenta CPU)" "Core_Mitigations" 180 $false

Add-Option $tabRAM "Desativar SysMain/Superfetch (Essencial para SSD/NVMe)" "RAM_SysMain" 20
Add-Option $tabRAM "Forcar Suspensao de Apps UWP em Background" "RAM_UWP" 60
Add-Option $tabRAM "Desativar Indexacao de Busca no Disco C (Aumenta vida util e velocidade)" "RAM_Index" 100
Add-Option $tabRAM "Desativar Servicos de Impressora e Fax (Spooler)" "RAM_Print" 140 $false
Add-Option $tabRAM "Executar Limpeza de Cache de Apps e DISM/Temp" "RAM_Flush" 180

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 410)
$progressBar.Size = New-Object System.Drawing.Size(505, 10)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.Location = New-Object System.Drawing.Point(20, 430)
$txtLog.Size = New-Object System.Drawing.Size(505, 100)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(10, 10, 10)
$txtLog.ForeColor = [System.Drawing.Color]::LimeGreen
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Text = "Win-Slim Iniciado: $osName (Build $osBuild).`r`nPronto para executar ajustes de maxima performance.`r`n"
$form.Controls.Add($txtLog)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "APLICAR ALTERACOES SELECIONADAS"
$btnApply.Location = New-Object System.Drawing.Point(20, 545)
$btnApply.Size = New-Object System.Drawing.Size(505, 40)
$btnApply.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnApply.BackColor = if ($osBuild -ge 22000) { [System.Drawing.Color]::MediumPurple } else { [System.Drawing.Color]::DeepSkyBlue }
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnApply.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnApply)

$btnRestart = New-Object System.Windows.Forms.Button
$btnRestart.Text = "REINICIAR O COMPUTADOR AGORA"
$btnRestart.Location = New-Object System.Drawing.Point(20, 595)
$btnRestart.Size = New-Object System.Drawing.Size(505, 40)
$btnRestart.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnRestart.BackColor = [System.Drawing.Color]::FromArgb(180, 50, 50)
$btnRestart.ForeColor = [System.Drawing.Color]::White
$btnRestart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRestart.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnRestart)

function Write-Log ($msg) {
    $txtLog.AppendText("$msg`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

$btnRestart.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show("Deseja realmente reiniciar o computador agora para aplicar as alteracoes?", "Win-Slim - Confirmar Reinicializacao", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Restart-Computer -Force
    }
})

$btnApply.Add_Click({
    $btnApply.Enabled = $false
    $progressBar.Value = 0
    $selected = $checkboxes | Where-Object { $_.Checked }

    if ($selected.Count -eq 0) { Write-Log "[!] Nada selecionado."; $btnApply.Enabled = $true; return }
    $step = 100 / $selected.Count

    foreach ($chk in $selected) {
        switch ($chk.Tag) {
            "W11_VBS" {
                Write-Log "[W11] Desativando VBS e Memory Integrity..."
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" 0
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" 0
            }
            "W11_Context" {
                Write-Log "[W11] Restaurando Menu de Contexto Classico..."
                $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                Set-ItemProperty -Path $path -Name "(Default)" -Value "" -Force
            }
            "W11_AI" {
                Write-Log "[W11] Bloqueando Copilot e Recall..."
                Set-RegProp "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
                Set-RegProp "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1
                Set-RegProp "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1
                Set-RegProp "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowCopilotButton" 0
            }
            "W11_Widgets" {
                Write-Log "[W11] Removendo Widgets e Telemetria da Barra..."
                Set-RegProp "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0
                Set-RegProp "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 0
            }
            "W11_UI" {
                Write-Log "[W11] Otimizando Efeitos Visuais (Mica/Acrylic)..."
                Set-RegProp "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
                Set-RegProp "HKCU:\Control Panel\Desktop" "UserPreferencesMask" ([byte[]](144,18,3,128,16,0,0,0)) "Binary"
            }
            "W10_Feeds" {
                Write-Log "[W10] Desativando Noticias e Interesses..."
                Set-RegProp "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Feeds" "ShellFeedsTaskbarViewMode" 2
            }
            "W10_Cortana" {
                Write-Log "[W10] Desabilitando Cortana..."
                Set-RegProp "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
                Set-RegProp "HKCU:\Software\Microsoft\Personalization\Settings" "AcceptPrivacyPolicy" 0
            }
            "W10_Telemetry" {
                Write-Log "[W10] Removendo Telemetria e DiagTrack..."
                Set-RegProp "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
                Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "DiagTrack" -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name "dmwappushservice" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "dmwappushservice" -StartupType Disabled -ErrorAction SilentlyContinue
            }
            "W10_Explorer" {
                Write-Log "[W10] Removendo Objetos 3D do Meu Computador..."
                Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue
            }
            "W10_UI" {
                Write-Log "[W10] Ajustando Transparencia para Performance..."
                Set-RegProp "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0
            }
            "Core_Power" {
                Write-Log "[Core] Aplicando Plano de Desempenho Maximo..."
                $pOut = powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1
                if ($pOut -match '([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})') {
                    powercfg /setactive $matches[1] | Out-Null
                } else {
                    powercfg /setactive 8c5e7fda-e8bf-4a96-9a15-7e6d57243573 | Out-Null
                }
            }
            "Core_Resp" {
                Write-Log "[Core] Reduzindo Latencia do Sistema (SystemResponsiveness=0 & Win32PrioritySeparation)..."
                $sysProf = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                Set-RegProp $sysProf "SystemResponsiveness" 0
                Set-RegProp "$sysProf\Tasks\Games" "GPU Priority" 8
                Set-RegProp "$sysProf\Tasks\Games" "Priority" 6
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" 38
            }
            "Core_HAGS" {
                Write-Log "[Core] Ativando Agendamento de GPU (HAGS)..."
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2
            }
            "Core_Network" {
                Write-Log "[Core] Otimizando TCP e Desativando Estrangulamento de Rede..."
                Set-RegProp "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" 4294967295
                netsh int tcp set global autotuninglevel=normal | Out-Null
            }
            "Core_Mitigations" {
                Write-Log "[Core] Desativando Mitigacoes Meltdown/Spectre (Aviso: Foco em Perf)..."
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride" 3
                Set-RegProp "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverrideMask" 3
            }
            "RAM_SysMain" {
                Write-Log "[RAM] Desativando SysMain (Superfetch)..."
                Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction SilentlyContinue
            }
            "RAM_UWP" {
                Write-Log "[RAM] Suspendendo Apps em Background..."
                Set-RegProp "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" 1
            }
            "RAM_Index" {
                Write-Log "[RAM] Desativando Windows Search (Indexacao)..."
                Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
            }
            "RAM_Print" {
                Write-Log "[RAM] Desativando Spooler de Impressao..."
                Stop-Service -Name "Spooler" -Force -ErrorAction SilentlyContinue
                Set-Service -Name "Spooler" -StartupType Disabled -ErrorAction SilentlyContinue
            }
            "RAM_Flush" {
                Write-Log "[RAM] Limpando arquivos temporarios e executando Coleta de Lixo..."
                $TempFolders = @($env:TEMP, "C:\Windows\Temp", "C:\Windows\Prefetch")
                foreach ($Folder in $TempFolders) {
                    if (Test-Path $Folder) { Remove-Item -Path "$Folder\*" -Recurse -Force -ErrorAction SilentlyContinue }
                }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        }
        $progressBar.Value = [Math]::Min(100, $progressBar.Value + $step)
    }

    $progressBar.Value = 100
    Write-Log "`r`n=== OPERACAO CONCLUIDA ==="
    Write-Log "Clique no botao abaixo para reiniciar o computador e aplicar as alteracoes."
    $btnApply.Enabled = $true
})

[void]$form.ShowDialog()