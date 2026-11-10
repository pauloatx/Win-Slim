#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R3.1.1
 Hotfix de runtime para o shell visual compacto R3.1.

 Corrige o escopo dos helpers usados por eventos WPF/Dispatcher no Windows PowerShell 5.1.
 Mantem o layout R3.1, Dashboard R2, Presets/overlays R3 e nenhuma mutacao do Windows.
#>

function Set-WinSlimR311ControlText {
    param([string]$Name, [string]$Text)
    $window = $script:WinSlimFase7Window
    if ($null -eq $window) { return }
    $control = $window.FindName($Name)
    if ($null -ne $control) { $control.Text = $Text }
}

function Set-WinSlimR311View {
    param([Parameter(Mandatory)][string]$Name)
    foreach ($key in @($script:WinSlimFase7Pages.Keys)) {
        $script:WinSlimFase7Pages[$key].Visibility = if ($key -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($key in @($script:WinSlimFase7NavButtons.Keys)) {
        if ($key -eq $Name) {
            $script:WinSlimFase7NavButtons[$key].Background = $script:WinSlimFase7ActiveBg
            $script:WinSlimFase7NavButtons[$key].Foreground = $script:WinSlimFase7ActiveFg
            $script:WinSlimFase7NavButtons[$key].FontWeight = 'SemiBold'
        } else {
            $script:WinSlimFase7NavButtons[$key].Background = $script:WinSlimFase7IdleBg
            $script:WinSlimFase7NavButtons[$key].Foreground = $script:WinSlimFase7IdleFg
            $script:WinSlimFase7NavButtons[$key].FontWeight = 'Normal'
        }
    }
    Set-WinSlimR311ControlText -Name 'TxtStatus' -Text "Pronto — $Name"
}

function Format-WinSlimR311Metric {
    param($Value)
    if ($null -eq $Value) { return '--' }
    try { return ('{0}%' -f [int]$Value) } catch { return '--' }
}

function Get-WinSlimR311ShortText {
    param([string]$Value, [int]$Max = 58)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Nao identificado' }
    if ($Value.Length -le $Max) { return $Value }
    return ($Value.Substring(0, [Math]::Max(1, $Max - 1)) + '…')
}

function Get-WinSlimR311SelectedConditionalProfiles {
    $selected = New-Object System.Collections.ArrayList
    foreach ($entry in $script:WinSlimFase7OverlayControlMap.GetEnumerator()) {
        $control = $script:WinSlimFase7Window.FindName([string]$entry.Key)
        if ($null -ne $control -and $control.IsEnabled -and [bool]$control.IsChecked) {
            [void]$selected.Add([string]$entry.Value)
        }
    }
    return @($selected.ToArray())
}

function Set-WinSlimR311PresetCardState {
    param([string]$PresetName)
    $cards = @{
        'Balanceado'='CardPresetBalanced'
        'Gamer'='CardPresetGamer'
        'Extremo'='CardPresetExtreme'
    }
    foreach ($name in @($cards.Keys)) {
        $card = $script:WinSlimFase7Window.FindName($cards[$name])
        if ($null -eq $card) { continue }
        if ($name -eq $PresetName) {
            $card.BorderBrush = $script:WinSlimFase7ActiveFg
            $card.BorderThickness = (New-Object System.Windows.Thickness -ArgumentList 2.0)
            $card.Background = $script:WinSlimFase7Brush.ConvertFromString('#171109')
        } else {
            $card.BorderThickness = (New-Object System.Windows.Thickness -ArgumentList 1.0)
            $card.Background = $script:WinSlimFase7Brush.ConvertFromString('#111111')
            if ($name -eq 'Balanceado') { $card.BorderBrush = $script:WinSlimFase7Brush.ConvertFromString('#1D8C4B') }
            elseif ($name -eq 'Gamer') { $card.BorderBrush = $script:WinSlimFase7Brush.ConvertFromString('#C85A00') }
            else { $card.BorderBrush = $script:WinSlimFase7Brush.ConvertFromString('#8A2929') }
        }
    }
}

function Update-WinSlimR311OverlayEligibility {
    $window = $script:WinSlimFase7Window
    $panel = $window.FindName('PanelOverlays')
    $hasPreset = -not [string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)
    if ($null -ne $panel) { $panel.IsEnabled = $hasPreset }
    $clear = $window.FindName('BtnClearOverlays')
    if ($null -ne $clear) { $clear.IsEnabled = $hasPreset }

    if (-not $hasPreset) {
        Set-WinSlimR311ControlText -Name 'TxtOverlayHardwareHint' -Text 'Selecione um preset para habilitar'
        return
    }
    if (-not (Get-Command Get-WinSlimUiConditionalProfileDescriptors -ErrorAction SilentlyContinue)) {
        Set-WinSlimR311ControlText -Name 'TxtOverlayHardwareHint' -Text 'Metadados de overlays indisponiveis'
        return
    }

    $profiles = @(Get-WinSlimUiConditionalProfileDescriptors -PresetRuntime $script:WinSlimFase7PresetRuntime)
    $byName = @{}
    foreach ($profile in $profiles) { $byName[[string]$profile.Name] = $profile }
    $disabledHardware = 0
    foreach ($entry in $script:WinSlimFase7OverlayControlMap.GetEnumerator()) {
        $control = $window.FindName([string]$entry.Key)
        if ($null -eq $control) { continue }
        $profileName = [string]$entry.Value
        $profile = $byName[$profileName]
        if ($null -eq $profile) { $control.IsEnabled = $false; continue }
        $eligibility = Test-WinSlimUiConditionalProfileEligibility -Profile $profile -SystemSnapshot $script:WinSlimFase7SystemSnapshot
        $control.IsEnabled = [bool]$eligibility.Eligible
        if (-not $control.IsEnabled) {
            $control.IsChecked = $false
            if ([string]$profile.Kind -eq 'Hardware') { $disabledHardware++ }
        }
        $tip = [string]$profile.Description
        if (-not [string]::IsNullOrWhiteSpace([string]$eligibility.Reason)) { $tip += "`n$($eligibility.Reason)" }
        $control.ToolTip = $tip
    }
    if ($disabledHardware -gt 0) {
        Set-WinSlimR311ControlText -Name 'TxtOverlayHardwareHint' -Text "$disabledHardware overlay(s) de hardware indisponivel(is)"
    } else {
        Set-WinSlimR311ControlText -Name 'TxtOverlayHardwareHint' -Text 'Hardware compativel com os overlays visiveis'
    }
}

function Update-WinSlimR311PresetSelection {
    $window = $script:WinSlimFase7Window
    if ([string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)) {
        $script:WinSlimFase7ResolvedPreset = $null
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionStatus' -Text 'Nenhum preset selecionado.'
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionDetail' -Text 'Base — · overlays — · total — · bloqueios —'
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionFingerprint' -Text 'Fingerprint: —'
        $next = $window.FindName('BtnPresetNext'); if ($null -ne $next) { $next.IsEnabled = $false }
        return
    }
    if ($null -eq $script:WinSlimFase7PresetRuntime) {
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionStatus' -Text 'PresetRuntime indisponivel.'
        return
    }
    try {
        $profiles = @(Get-WinSlimR311SelectedConditionalProfiles)
        $consent = $window.FindName('ChkAllowHighRiskConditional')
        $allowHigh = ($null -ne $consent -and [bool]$consent.IsChecked)
        $resolved = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $script:WinSlimFase7PresetRuntime -PresetName $script:WinSlimFase7SelectedPreset -ConditionalProfiles $profiles -AllowHighRiskConditional:$allowHigh
        $script:WinSlimFase7ResolvedPreset = $resolved
        $overlayCount = @($resolved.EnabledConditionalProfiles).Count
        $blockedCount = @($resolved.BlockedRequests).Count
        $warningCount = @($resolved.Warnings).Count
        $status = if ([bool]$resolved.CanResolve) { "✓ $($resolved.PresetName) resolvido" } else { "⚠ $($resolved.PresetName) possui bloqueios" }
        $statusControl = $window.FindName('TxtPresetSelectionStatus')
        if ($null -ne $statusControl) {
            $statusControl.Text = $status
            $statusControl.Foreground = if ([bool]$resolved.CanResolve) { $script:WinSlimFase7GreenFg } else { $script:WinSlimFase7YellowFg }
        }
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionDetail' -Text ("Base {0} · overlays {1} · total {2} · bloqueios {3} · avisos {4}" -f [int]$resolved.BaseCount,$overlayCount,@($resolved.SelectedIds).Count,$blockedCount,$warningCount)
        $fp = [string]$resolved.Fingerprint
        if ($fp.Length -gt 24) { $fp = $fp.Substring(0,24) + '…' }
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionFingerprint' -Text ("Policy fingerprint: $fp")
        $next = $window.FindName('BtnPresetNext')
        if ($null -ne $next) { $next.IsEnabled = [bool]$resolved.CanResolve }
        if ($blockedCount -gt 0) {
            $first = $resolved.BlockedRequests | Select-Object -First 1
            if ($null -ne $first) { Set-WinSlimR311ControlText -Name 'TxtStatus' -Text ([string]$first.Message) }
        } else {
            Set-WinSlimR311ControlText -Name 'TxtStatus' -Text "Preset $($resolved.PresetName) pronto; nenhuma alteracao aplicada."
        }
    } catch {
        $script:WinSlimFase7ResolvedPreset = $null
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionStatus' -Text 'Falha ao resolver preset.'
        Set-WinSlimR311ControlText -Name 'TxtPresetSelectionDetail' -Text $_.Exception.Message
        $next = $window.FindName('BtnPresetNext'); if ($null -ne $next) { $next.IsEnabled = $false }
    }
}

function Select-WinSlimR311PresetUi {
    param([Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName)
    $script:WinSlimFase7SelectedPreset = $PresetName
    Set-WinSlimR311PresetCardState -PresetName $PresetName
    Update-WinSlimR311OverlayEligibility
    Update-WinSlimR311PresetSelection
}

function Show-WinSlimFase7ShellR311 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        $PresetRuntime = $null,
        $PromotionStatus = $null
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $RootPath 'src\UI\Fase7\WinSlimShell.R3_1.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "XAML da FASE 7 R3.1 nao encontrado: $xamlPath"
    }

    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $window) { throw 'Falha ao carregar WinSlimShell.R3_1.xaml.' }

    $script:WinSlimFase7Window = $window
    $script:WinSlimFase7Pages = @{}
    $script:WinSlimFase7NavButtons = @{}
    $script:WinSlimFase7SystemSnapshot = $null
    $script:WinSlimFase7SelectedPreset = $null
    $script:WinSlimFase7ResolvedPreset = $null
    $script:WinSlimFase7PresetRuntime = $PresetRuntime

    foreach ($name in @('Inicio','Presets','Personalizado','Backup','Analise','Configuracoes','Sobre','Preview','Apply','Result','TweakDetail')) {
        $page = $window.FindName("Page$name")
        if ($null -ne $page) { $script:WinSlimFase7Pages[$name] = $page }
    }
    foreach ($name in @('Inicio','Presets','Personalizado','Backup','Analise','Configuracoes','Sobre')) {
        $button = $window.FindName("Nav$name")
        if ($null -ne $button) { $script:WinSlimFase7NavButtons[$name] = $button }
    }

    $brush = New-Object System.Windows.Media.BrushConverter
    $activeBg = $brush.ConvertFromString('#2A1608')
    $activeFg = $brush.ConvertFromString('#FF9A2E')
    $idleBg = $brush.ConvertFromString('Transparent')
    $idleFg = $brush.ConvertFromString('#B9B9B9')
    $greenFg = $brush.ConvertFromString('#24D66F')
    $yellowFg = $brush.ConvertFromString('#FFBC35')
    $redFg = $brush.ConvertFromString('#FF4D4D')
    $mutedFg = $brush.ConvertFromString('#808080')

    $script:WinSlimFase7Brush = $brush
    $script:WinSlimFase7ActiveBg = $activeBg
    $script:WinSlimFase7ActiveFg = $activeFg
    $script:WinSlimFase7IdleBg = $idleBg
    $script:WinSlimFase7IdleFg = $idleFg
    $script:WinSlimFase7GreenFg = $greenFg
    $script:WinSlimFase7YellowFg = $yellowFg
    $script:WinSlimFase7RedFg = $redFg
    $script:WinSlimFase7MutedFg = $mutedFg

    $overlayControlMap = [ordered]@{
        'ChkOverlayHags'='HW-HAGS-ON'
        'ChkOverlayMsiGpu'='HW-MSI-GPU'
        'ChkOverlayCoreParking'='HW-CORE-PARKING-100'
        'ChkOverlayCs2PCores'='HW-CS2-P-CORES'
        'ChkOverlayGpuIrq'='HW-GPU-IRQ-AFFINITY'
        'ChkOverlayValorant'='WL-VALORANT'
        'ChkOverlayCs2'='WL-CS2'
        'ChkOverlayApex'='WL-APEX'
        'ChkOverlayFortnite'='WL-FORTNITE'
        'ChkOverlayGtav'='WL-GTAV'
        'ChkOverlayFso'='WL-FSO-OFF'
        'ChkOverlayDefenderDev'='WL-DEFENDER-DEV-EXCLUSIONS'
        'ChkOverlayStreaming'='WL-STREAMING'
        'ChkOverlayVideo'='WL-VIDEO-EDITING'
        'ChkOverlayDesign'='WL-DESIGN'
        'ChkOverlayProgramming'='WL-PROGRAMMING'
    }
    $script:WinSlimFase7OverlayControlMap = $overlayControlMap

    $updateSystem = {
        Set-WinSlimR311ControlText -Name 'TxtStatus' -Text 'Lendo hardware e contexto do sistema...'
        try {
            if (-not (Get-Command Get-WinSlimUiSystemSnapshot -ErrorAction SilentlyContinue)) {
                throw 'Leitor de contexto da FASE 7 R3.1.1 nao foi carregado.'
            }
            $snapshot = Get-WinSlimUiSystemSnapshot
            $script:WinSlimFase7SystemSnapshot = $snapshot
            if (-not [string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)) { Update-WinSlimR311OverlayEligibility; Update-WinSlimR311PresetSelection }

            $buildText = if ($snapshot.Build) { "Build $($snapshot.Build)" } else { 'Build desconhecida' }
            $archText = if ($snapshot.Architecture) { [string]$snapshot.Architecture } else { 'Arquitetura desconhecida' }
            Set-WinSlimR311ControlText -Name 'TxtSystemPrimary' -Text ([string]$snapshot.OSName)
            Set-WinSlimR311ControlText -Name 'TxtSystemSecondary' -Text ("$buildText · $archText · $($snapshot.DeviceType)")
            Set-WinSlimR311ControlText -Name 'TxtSystemHardware' -Text ("$(Get-WinSlimR311ShortText $snapshot.CPUName 36) · $(Get-WinSlimR311ShortText $snapshot.GPUName 32) · $($snapshot.RamGB) GB RAM")
            Set-WinSlimR311ControlText -Name 'TxtDeviceType' -Text ("Dispositivo: $($snapshot.DeviceType) · $($snapshot.StorageType)")

            $compat = $window.FindName('TxtCompatibilityBadge')
            if ($null -ne $compat) {
                if ($snapshot.OSName -match '(?i)Windows\s+(10|11)') {
                    $compat.Text = '✓ Sistema compatível'
                    $compat.Foreground = $greenFg
                } else {
                    $compat.Text = '⚠ Compatibilidade não confirmada'
                    $compat.Foreground = $yellowFg
                }
            }
            $admin = $window.FindName('TxtAdminBadge')
            if ($null -ne $admin) {
                if ($snapshot.IsAdmin) { $admin.Text = '✓ Administrador'; $admin.Foreground = $greenFg }
                else { $admin.Text = '⚠ Sem elevação'; $admin.Foreground = $yellowFg }
            }
            $pending = $window.FindName('TxtPendingReboot')
            if ($null -ne $pending) {
                if ($snapshot.PendingReboot) { $pending.Text = 'Sim'; $pending.Foreground = $yellowFg }
                else { $pending.Text = 'Não'; $pending.Foreground = $greenFg }
            }

            $cpuTopology = @()
            if ($snapshot.CPUCores) { $cpuTopology += "$($snapshot.CPUCores) núcleos" }
            if ($snapshot.CPUThreads) { $cpuTopology += "$($snapshot.CPUThreads) threads" }
            $cpuText = [string]$snapshot.CPUName
            if ($cpuTopology.Count -gt 0) { $cpuText += ' · ' + ($cpuTopology -join ' / ') }
            $storageText = "$($snapshot.StorageType) · $($snapshot.StorageBus) · $($snapshot.StorageModel)"
            if ($snapshot.StorageSizeGB) { $storageText += " · $($snapshot.StorageSizeGB) GB" }

            Set-WinSlimR311ControlText -Name 'TxtAnalysisWindows' -Text ("$($snapshot.OSName) · $buildText")
            Set-WinSlimR311ControlText -Name 'TxtAnalysisArch' -Text $archText
            Set-WinSlimR311ControlText -Name 'TxtAnalysisCpu' -Text $cpuText
            Set-WinSlimR311ControlText -Name 'TxtAnalysisGpu' -Text ([string]$snapshot.GPUName)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisGpuDriver' -Text ($(if ($snapshot.GPUDriver) { [string]$snapshot.GPUDriver } else { 'Indisponível' }))
            Set-WinSlimR311ControlText -Name 'TxtAnalysisRam' -Text ($(if ($snapshot.RamGB) { "$($snapshot.RamGB) GB" } else { 'Indisponível' }))
            Set-WinSlimR311ControlText -Name 'TxtAnalysisStorage' -Text $storageText
            Set-WinSlimR311ControlText -Name 'TxtAnalysisDevice' -Text ([string]$snapshot.DeviceType)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisAdmin' -Text ($(if ($snapshot.IsAdmin) { 'Sim' } else { 'Não' }))
            Set-WinSlimR311ControlText -Name 'TxtAnalysisSecureBoot' -Text ([string]$snapshot.SecureBoot)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisTpm' -Text ([string]$snapshot.TPM)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisVbs' -Text ([string]$snapshot.VBS)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisHvci' -Text ([string]$snapshot.HVCI)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisBitLocker' -Text ([string]$snapshot.BitLocker)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisReboot' -Text ($(if ($snapshot.PendingReboot) { 'Sim' } else { 'Não' }))
            Set-WinSlimR311ControlText -Name 'TxtAnalysisNetwork' -Text ([string]$snapshot.Network)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisPower' -Text ([string]$snapshot.PowerPlan)
            Set-WinSlimR311ControlText -Name 'TxtAnalysisTime' -Text ($snapshot.CollectedAt.ToString('dd/MM/yyyy HH:mm:ss'))

            $summary = 'Leitura concluída. Hardware e contexto foram consultados sem aplicar alterações.'
            if ($snapshot.PendingReboot) { $summary += ' Há um reinício pendente no Windows.' }
            Set-WinSlimR311ControlText -Name 'TxtAnalysisSummary' -Text $summary
            Set-WinSlimR311ControlText -Name 'TxtStatus' -Text 'Diagnóstico do sistema atualizado.'
        } catch {
            Set-WinSlimR311ControlText -Name 'TxtAnalysisSummary' -Text ("Falha parcial ao coletar contexto: $($_.Exception.Message)")
            Set-WinSlimR311ControlText -Name 'TxtStatus' -Text 'Diagnóstico concluído com dados indisponíveis.'
        }
    }.GetNewClosure()

    $updatePerf = {
        try {
            if (-not (Get-Command Get-WinSlimUiPerformanceSnapshot -ErrorAction SilentlyContinue)) { return }
            $perf = Get-WinSlimUiPerformanceSnapshot
            Set-WinSlimR311ControlText -Name 'TxtMetricCpu' -Text (Format-WinSlimR311Metric $perf.CPU)
            Set-WinSlimR311ControlText -Name 'TxtMetricGpu' -Text (Format-WinSlimR311Metric $perf.GPU)
            Set-WinSlimR311ControlText -Name 'TxtMetricRam' -Text (Format-WinSlimR311Metric $perf.RAM)
            Set-WinSlimR311ControlText -Name 'TxtMetricDisk' -Text (Format-WinSlimR311Metric $perf.Disk)
            Set-WinSlimR311ControlText -Name 'TxtMetricTimestamp' -Text ((Get-Date).ToString('HH:mm:ss'))
        } catch { }
    }.GetNewClosure()

    $viewMap = @{
        NavInicio='Inicio'; NavPresets='Presets'; NavPersonalizado='Personalizado';
        NavBackup='Backup'; NavAnalise='Analise'; NavConfiguracoes='Configuracoes'; NavSobre='Sobre'
    }
    foreach ($pair in $viewMap.GetEnumerator()) {
        $control = $window.FindName([string]$pair.Key)
        $target = [string]$pair.Value
        if ($null -ne $control) {
            $control.Add_Click(({ Set-WinSlimR311View -Name $target }.GetNewClosure()))
        }
    }

    $btnAnalyze = $window.FindName('BtnAnalyzeSystem')
    if ($null -ne $btnAnalyze) {
        $btnAnalyze.Add_Click(({ & $updateSystem; & $updatePerf; Set-WinSlimR311View -Name 'Analise' }.GetNewClosure()))
    }
    $btnRefreshSystem = $window.FindName('BtnRefreshSystem')
    if ($null -ne $btnRefreshSystem) {
        $btnRefreshSystem.Add_Click(({ & $updateSystem; & $updatePerf }.GetNewClosure()))
    }
    $btnRefreshDashboard = $window.FindName('BtnRefreshDashboard')
    if ($null -ne $btnRefreshDashboard) {
        $btnRefreshDashboard.Add_Click(({ & $updateSystem; & $updatePerf }.GetNewClosure()))
    }
    $btnGoCustom = $window.FindName('BtnGoCustom')
    if ($null -ne $btnGoCustom) { $btnGoCustom.Add_Click({ Set-WinSlimR311View -Name 'Personalizado' }) }

    # R3.1: overlays continuam funcionais, mas ficam em uma gaveta visual para preservar o layout da referencia.
    $btnToggleOverlays = $window.FindName('BtnToggleOverlays')
    $panelOverlaysHost = $window.FindName('PanelOverlaysHost')
    if ($null -ne $btnToggleOverlays -and $null -ne $panelOverlaysHost) {
        $btnToggleOverlays.Add_Click(({
            if ($panelOverlaysHost.Visibility -eq 'Visible') {
                $panelOverlaysHost.Visibility = 'Collapsed'
                $btnToggleOverlays.Content = '☷  Overlays condicionais'
            } else {
                $panelOverlaysHost.Visibility = 'Visible'
                $btnToggleOverlays.Content = '⌃  Ocultar overlays'
            }
        }.GetNewClosure()))
    }

    # R3: selecao funcional de preset/overlays. Continua sem Planner, Preview, Transaction ou Provider.
    $presetActions = @{
        'BtnPresetBalanced'='Balanceado'
        'BtnPresetGamer'='Gamer'
        'BtnPresetExtreme'='Extremo'
    }
    foreach ($entry in $presetActions.GetEnumerator()) {
        $presetButton = $window.FindName([string]$entry.Key)
        $presetName = [string]$entry.Value
        if ($null -ne $presetButton) {
            $presetButton.Add_Click(({ Select-WinSlimR311PresetUi -PresetName $presetName }.GetNewClosure()))
        }
    }
    foreach ($entry in $overlayControlMap.GetEnumerator()) {
        $overlay = $window.FindName([string]$entry.Key)
        if ($null -ne $overlay) {
            $overlay.Add_Checked({ Update-WinSlimR311PresetSelection })
            $overlay.Add_Unchecked({ Update-WinSlimR311PresetSelection })
        }
    }
    $highRiskConsent = $window.FindName('ChkAllowHighRiskConditional')
    if ($null -ne $highRiskConsent) {
        $highRiskConsent.Add_Checked({ Update-WinSlimR311PresetSelection })
        $highRiskConsent.Add_Unchecked({ Update-WinSlimR311PresetSelection })
    }
    $btnClearOverlays = $window.FindName('BtnClearOverlays')
    if ($null -ne $btnClearOverlays) {
        $btnClearOverlays.Add_Click(({
            foreach ($entry in $overlayControlMap.GetEnumerator()) {
                $overlay = $window.FindName([string]$entry.Key)
                if ($null -ne $overlay) { $overlay.IsChecked = $false }
            }
            $consent = $window.FindName('ChkAllowHighRiskConditional')
            if ($null -ne $consent) { $consent.IsChecked = $false }
            Update-WinSlimR311PresetSelection
        }.GetNewClosure()))
    }
    $btnPresetNext = $window.FindName('BtnPresetNext')
    if ($null -ne $btnPresetNext) {
        $btnPresetNext.Add_Click({
            [System.Windows.MessageBox]::Show(
                'A seleção do preset e dos overlays está resolvida pelo PresetRuntime. A pré-visualização transacional será conectada na FASE 7 R5; nenhuma alteração foi aplicada.',
                'Win-Slim Suite — FASE 7 R3.1.1',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        })
    }

    $btnClose = $window.FindName('BtnClose')
    if ($null -ne $btnClose) { $btnClose.Add_Click({ $script:WinSlimFase7Window.Close() }) }
    $btnMinimize = $window.FindName('BtnMinimize')
    if ($null -ne $btnMinimize) { $btnMinimize.Add_Click({ $script:WinSlimFase7Window.WindowState = 'Minimized' }) }
    $btnMaximize = $window.FindName('BtnMaximize')
    if ($null -ne $btnMaximize) {
        $btnMaximize.Add_Click({
            if ($script:WinSlimFase7Window.WindowState -eq 'Maximized') { $script:WinSlimFase7Window.WindowState = 'Normal' } else { $script:WinSlimFase7Window.WindowState = 'Maximized' }
        })
    }
    $drag = $window.FindName('TopDragArea')
    if ($null -ne $drag) {
        $drag.Add_MouseLeftButtonDown({
            param($sender,$e)
            if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
            if ($e.ClickCount -eq 2) {
                if ($script:WinSlimFase7Window.WindowState -eq 'Maximized') { $script:WinSlimFase7Window.WindowState = 'Normal' } else { $script:WinSlimFase7Window.WindowState = 'Maximized' }
            } else {
                try { $script:WinSlimFase7Window.DragMove() } catch { }
            }
        })
    }

    $backendCount = 0
    if ($null -ne $PresetRuntime) {
        try { $backendCount = @($PresetRuntime.CatalogRuntime.Tweaks).Count } catch { $backendCount = 0 }
    }
    $runtimeText = 'Runtime: Legacy'
    $runtimeDetail = 'Planner Legacy / Transaction Legacy'
    if ($null -ne $PromotionStatus) {
        try {
            $runtimeText = "Runtime: $($PromotionStatus.Planner) / $($PromotionStatus.Transaction)"
            $runtimeDetail = "Planner $($PromotionStatus.Planner) / Transaction $($PromotionStatus.Transaction)"
        } catch { }
    }

    Set-WinSlimR311ControlText -Name 'TxtRuntimeState' -Text $runtimeText
    Set-WinSlimR311ControlText -Name 'TxtRuntimeDetail' -Text $runtimeDetail
    Set-WinSlimR311ControlText -Name 'TxtBackendState' -Text ($(if ($backendCount -gt 0) { "Backend: $backendCount tweaks" } else { 'Backend: indisponivel' }))
    if ($backendCount -gt 0) { Set-WinSlimR311ControlText -Name 'TxtTweakCount' -Text "$backendCount / $backendCount" }

    $metricTimer = New-Object System.Windows.Threading.DispatcherTimer
    $metricTimer.Interval = [TimeSpan]::FromSeconds(3)
    $metricTimer.Add_Tick(({ & $updatePerf }.GetNewClosure()))
    $window.Add_Closed(({ try { $metricTimer.Stop() } catch { } }.GetNewClosure()))
    $window.Add_ContentRendered(({ & $updateSystem; & $updatePerf; Update-WinSlimR311OverlayEligibility; Update-WinSlimR311PresetSelection; $metricTimer.Start() }.GetNewClosure()))

    Set-WinSlimR311View -Name 'Inicio'
    Set-WinSlimR311ControlText -Name 'TxtStatus' -Text 'Pronto — layout R3.1 carregado'
    $window.ShowDialog() | Out-Null
}
