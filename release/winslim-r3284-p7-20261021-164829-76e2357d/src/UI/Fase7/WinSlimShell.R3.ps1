#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R3
 Shell principal + Dashboard R2 + Presets e overlays condicionais R3.

 Esta camada continua sem aplicar tweaks, sem executar providers e sem alterar
 configuracoes do Windows. R3 adiciona somente resolucao pura de presets/overlays e apresentacao de estado.
#>

function Show-WinSlimFase7Shell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        $PresetRuntime = $null,
        $PromotionStatus = $null
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $RootPath 'src\UI\Fase7\WinSlimShell.R3.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "XAML da FASE 7 R3 nao encontrado: $xamlPath"
    }

    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $window) { throw 'Falha ao carregar WinSlimShell.xaml.' }

    $script:WinSlimFase7Window = $window
    $script:WinSlimFase7Pages = @{}
    $script:WinSlimFase7NavButtons = @{}
    $script:WinSlimFase7SystemSnapshot = $null
    $script:WinSlimFase7SelectedPreset = $null
    $script:WinSlimFase7ResolvedPreset = $null

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

    function Set-WinSlimControlText {
        param([string]$Name, [string]$Text)
        $control = $window.FindName($Name)
        if ($null -ne $control) { $control.Text = $Text }
    }

    function Set-WinSlimFase7View {
        param([Parameter(Mandatory)][string]$Name)
        foreach ($key in @($script:WinSlimFase7Pages.Keys)) {
            $script:WinSlimFase7Pages[$key].Visibility = if ($key -eq $Name) { 'Visible' } else { 'Collapsed' }
        }
        foreach ($key in @($script:WinSlimFase7NavButtons.Keys)) {
            if ($key -eq $Name) {
                $script:WinSlimFase7NavButtons[$key].Background = $activeBg
                $script:WinSlimFase7NavButtons[$key].Foreground = $activeFg
                $script:WinSlimFase7NavButtons[$key].FontWeight = 'SemiBold'
            } else {
                $script:WinSlimFase7NavButtons[$key].Background = $idleBg
                $script:WinSlimFase7NavButtons[$key].Foreground = $idleFg
                $script:WinSlimFase7NavButtons[$key].FontWeight = 'Normal'
            }
        }
        Set-WinSlimControlText -Name 'TxtStatus' -Text "Pronto — $Name"
    }

    function Format-WinSlimMetric {
        param($Value)
        if ($null -eq $Value) { return '--' }
        try { return ('{0}%' -f [int]$Value) } catch { return '--' }
    }

    function Get-WinSlimShortText {
        param([string]$Value, [int]$Max = 58)
        if ([string]::IsNullOrWhiteSpace($Value)) { return 'Nao identificado' }
        if ($Value.Length -le $Max) { return $Value }
        return ($Value.Substring(0, [Math]::Max(1, $Max - 1)) + '…')
    }


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

    function Get-WinSlimSelectedConditionalProfiles {
        $selected = New-Object System.Collections.ArrayList
        foreach ($entry in $overlayControlMap.GetEnumerator()) {
            $control = $window.FindName([string]$entry.Key)
            if ($null -ne $control -and $control.IsEnabled -and [bool]$control.IsChecked) {
                [void]$selected.Add([string]$entry.Value)
            }
        }
        return @($selected.ToArray())
    }

    function Set-WinSlimPresetCardState {
        param([string]$PresetName)
        $cards = @{
            'Balanceado'='CardPresetBalanced'
            'Gamer'='CardPresetGamer'
            'Extremo'='CardPresetExtreme'
        }
        foreach ($name in @($cards.Keys)) {
            $card = $window.FindName($cards[$name])
            if ($null -eq $card) { continue }
            if ($name -eq $PresetName) {
                $card.BorderBrush = $activeFg
                $card.BorderThickness = (New-Object System.Windows.Thickness -ArgumentList 2.0)
                $card.Background = $brush.ConvertFromString('#171109')
            } else {
                $card.BorderThickness = (New-Object System.Windows.Thickness -ArgumentList 1.0)
                $card.Background = $brush.ConvertFromString('#111111')
                if ($name -eq 'Balanceado') { $card.BorderBrush = $brush.ConvertFromString('#1D8C4B') }
                elseif ($name -eq 'Gamer') { $card.BorderBrush = $brush.ConvertFromString('#C85A00') }
                else { $card.BorderBrush = $brush.ConvertFromString('#8A2929') }
            }
        }
    }

    function Update-WinSlimOverlayEligibility {
        $panel = $window.FindName('PanelOverlays')
        $hasPreset = -not [string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)
        if ($null -ne $panel) { $panel.IsEnabled = $hasPreset }
        $clear = $window.FindName('BtnClearOverlays')
        if ($null -ne $clear) { $clear.IsEnabled = $hasPreset }

        if (-not $hasPreset) {
            Set-WinSlimControlText -Name 'TxtOverlayHardwareHint' -Text 'Selecione um preset para habilitar'
            return
        }
        if (-not (Get-Command Get-WinSlimUiConditionalProfileDescriptors -ErrorAction SilentlyContinue)) {
            Set-WinSlimControlText -Name 'TxtOverlayHardwareHint' -Text 'Metadados de overlays indisponiveis'
            return
        }

        $profiles = @(Get-WinSlimUiConditionalProfileDescriptors -PresetRuntime $PresetRuntime)
        $byName = @{}
        foreach ($profile in $profiles) { $byName[[string]$profile.Name] = $profile }
        $disabledHardware = 0
        foreach ($entry in $overlayControlMap.GetEnumerator()) {
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
            Set-WinSlimControlText -Name 'TxtOverlayHardwareHint' -Text "$disabledHardware overlay(s) de hardware indisponivel(is)"
        } else {
            Set-WinSlimControlText -Name 'TxtOverlayHardwareHint' -Text 'Hardware compativel com os overlays visiveis'
        }
    }

    function Update-WinSlimPresetSelection {
        if ([string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)) {
            $script:WinSlimFase7ResolvedPreset = $null
            Set-WinSlimControlText -Name 'TxtPresetSelectionStatus' -Text 'Nenhum preset selecionado.'
            Set-WinSlimControlText -Name 'TxtPresetSelectionDetail' -Text 'Base — · overlays — · total — · bloqueios —'
            Set-WinSlimControlText -Name 'TxtPresetSelectionFingerprint' -Text 'Fingerprint: —'
            $next = $window.FindName('BtnPresetNext'); if ($null -ne $next) { $next.IsEnabled = $false }
            return
        }
        if ($null -eq $PresetRuntime) {
            Set-WinSlimControlText -Name 'TxtPresetSelectionStatus' -Text 'PresetRuntime indisponivel.'
            return
        }
        try {
            $profiles = @(Get-WinSlimSelectedConditionalProfiles)
            $consent = $window.FindName('ChkAllowHighRiskConditional')
            $allowHigh = ($null -ne $consent -and [bool]$consent.IsChecked)
            $resolved = Resolve-WinSlimPresetRuntimeSelection -PresetRuntime $PresetRuntime -PresetName $script:WinSlimFase7SelectedPreset -ConditionalProfiles $profiles -AllowHighRiskConditional:$allowHigh
            $script:WinSlimFase7ResolvedPreset = $resolved
            $overlayCount = @($resolved.EnabledConditionalProfiles).Count
            $blockedCount = @($resolved.BlockedRequests).Count
            $warningCount = @($resolved.Warnings).Count
            $status = if ([bool]$resolved.CanResolve) { "✓ $($resolved.PresetName) resolvido" } else { "⚠ $($resolved.PresetName) possui bloqueios" }
            $statusControl = $window.FindName('TxtPresetSelectionStatus')
            if ($null -ne $statusControl) {
                $statusControl.Text = $status
                $statusControl.Foreground = if ([bool]$resolved.CanResolve) { $greenFg } else { $yellowFg }
            }
            Set-WinSlimControlText -Name 'TxtPresetSelectionDetail' -Text ("Base {0} · overlays {1} · total {2} · bloqueios {3} · avisos {4}" -f [int]$resolved.BaseCount,$overlayCount,@($resolved.SelectedIds).Count,$blockedCount,$warningCount)
            $fp = [string]$resolved.Fingerprint
            if ($fp.Length -gt 24) { $fp = $fp.Substring(0,24) + '…' }
            Set-WinSlimControlText -Name 'TxtPresetSelectionFingerprint' -Text ("Policy fingerprint: $fp")
            $next = $window.FindName('BtnPresetNext')
            if ($null -ne $next) { $next.IsEnabled = [bool]$resolved.CanResolve }
            if ($blockedCount -gt 0) {
                $first = $resolved.BlockedRequests | Select-Object -First 1
                if ($null -ne $first) { Set-WinSlimControlText -Name 'TxtStatus' -Text ([string]$first.Message) }
            } else {
                Set-WinSlimControlText -Name 'TxtStatus' -Text "Preset $($resolved.PresetName) pronto; nenhuma alteracao aplicada."
            }
        } catch {
            $script:WinSlimFase7ResolvedPreset = $null
            Set-WinSlimControlText -Name 'TxtPresetSelectionStatus' -Text 'Falha ao resolver preset.'
            Set-WinSlimControlText -Name 'TxtPresetSelectionDetail' -Text $_.Exception.Message
            $next = $window.FindName('BtnPresetNext'); if ($null -ne $next) { $next.IsEnabled = $false }
        }
    }

    function Select-WinSlimPresetUi {
        param([Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName)
        $script:WinSlimFase7SelectedPreset = $PresetName
        Set-WinSlimPresetCardState -PresetName $PresetName
        Update-WinSlimOverlayEligibility
        Update-WinSlimPresetSelection
    }

    $updateSystem = {
        Set-WinSlimControlText -Name 'TxtStatus' -Text 'Lendo hardware e contexto do sistema...'
        try {
            if (-not (Get-Command Get-WinSlimUiSystemSnapshot -ErrorAction SilentlyContinue)) {
                throw 'Leitor de contexto da FASE 7 R3 nao foi carregado.'
            }
            $snapshot = Get-WinSlimUiSystemSnapshot
            $script:WinSlimFase7SystemSnapshot = $snapshot
            if (-not [string]::IsNullOrWhiteSpace([string]$script:WinSlimFase7SelectedPreset)) { Update-WinSlimOverlayEligibility; Update-WinSlimPresetSelection }

            $buildText = if ($snapshot.Build) { "Build $($snapshot.Build)" } else { 'Build desconhecida' }
            $archText = if ($snapshot.Architecture) { [string]$snapshot.Architecture } else { 'Arquitetura desconhecida' }
            Set-WinSlimControlText -Name 'TxtSystemPrimary' -Text ([string]$snapshot.OSName)
            Set-WinSlimControlText -Name 'TxtSystemSecondary' -Text ("$buildText · $archText · $($snapshot.DeviceType)")
            Set-WinSlimControlText -Name 'TxtSystemHardware' -Text ("$(Get-WinSlimShortText $snapshot.CPUName 36) · $(Get-WinSlimShortText $snapshot.GPUName 32) · $($snapshot.RamGB) GB RAM")
            Set-WinSlimControlText -Name 'TxtDeviceType' -Text ("Dispositivo: $($snapshot.DeviceType) · $($snapshot.StorageType)")

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

            Set-WinSlimControlText -Name 'TxtAnalysisWindows' -Text ("$($snapshot.OSName) · $buildText")
            Set-WinSlimControlText -Name 'TxtAnalysisArch' -Text $archText
            Set-WinSlimControlText -Name 'TxtAnalysisCpu' -Text $cpuText
            Set-WinSlimControlText -Name 'TxtAnalysisGpu' -Text ([string]$snapshot.GPUName)
            Set-WinSlimControlText -Name 'TxtAnalysisGpuDriver' -Text ($(if ($snapshot.GPUDriver) { [string]$snapshot.GPUDriver } else { 'Indisponível' }))
            Set-WinSlimControlText -Name 'TxtAnalysisRam' -Text ($(if ($snapshot.RamGB) { "$($snapshot.RamGB) GB" } else { 'Indisponível' }))
            Set-WinSlimControlText -Name 'TxtAnalysisStorage' -Text $storageText
            Set-WinSlimControlText -Name 'TxtAnalysisDevice' -Text ([string]$snapshot.DeviceType)
            Set-WinSlimControlText -Name 'TxtAnalysisAdmin' -Text ($(if ($snapshot.IsAdmin) { 'Sim' } else { 'Não' }))
            Set-WinSlimControlText -Name 'TxtAnalysisSecureBoot' -Text ([string]$snapshot.SecureBoot)
            Set-WinSlimControlText -Name 'TxtAnalysisTpm' -Text ([string]$snapshot.TPM)
            Set-WinSlimControlText -Name 'TxtAnalysisVbs' -Text ([string]$snapshot.VBS)
            Set-WinSlimControlText -Name 'TxtAnalysisHvci' -Text ([string]$snapshot.HVCI)
            Set-WinSlimControlText -Name 'TxtAnalysisBitLocker' -Text ([string]$snapshot.BitLocker)
            Set-WinSlimControlText -Name 'TxtAnalysisReboot' -Text ($(if ($snapshot.PendingReboot) { 'Sim' } else { 'Não' }))
            Set-WinSlimControlText -Name 'TxtAnalysisNetwork' -Text ([string]$snapshot.Network)
            Set-WinSlimControlText -Name 'TxtAnalysisPower' -Text ([string]$snapshot.PowerPlan)
            Set-WinSlimControlText -Name 'TxtAnalysisTime' -Text ($snapshot.CollectedAt.ToString('dd/MM/yyyy HH:mm:ss'))

            $summary = 'Leitura concluída. Hardware e contexto foram consultados sem aplicar alterações.'
            if ($snapshot.PendingReboot) { $summary += ' Há um reinício pendente no Windows.' }
            Set-WinSlimControlText -Name 'TxtAnalysisSummary' -Text $summary
            Set-WinSlimControlText -Name 'TxtStatus' -Text 'Diagnóstico do sistema atualizado.'
        } catch {
            Set-WinSlimControlText -Name 'TxtAnalysisSummary' -Text ("Falha parcial ao coletar contexto: $($_.Exception.Message)")
            Set-WinSlimControlText -Name 'TxtStatus' -Text 'Diagnóstico concluído com dados indisponíveis.'
        }
    }.GetNewClosure()

    $updatePerf = {
        try {
            if (-not (Get-Command Get-WinSlimUiPerformanceSnapshot -ErrorAction SilentlyContinue)) { return }
            $perf = Get-WinSlimUiPerformanceSnapshot
            Set-WinSlimControlText -Name 'TxtMetricCpu' -Text (Format-WinSlimMetric $perf.CPU)
            Set-WinSlimControlText -Name 'TxtMetricGpu' -Text (Format-WinSlimMetric $perf.GPU)
            Set-WinSlimControlText -Name 'TxtMetricRam' -Text (Format-WinSlimMetric $perf.RAM)
            Set-WinSlimControlText -Name 'TxtMetricDisk' -Text (Format-WinSlimMetric $perf.Disk)
            Set-WinSlimControlText -Name 'TxtMetricTimestamp' -Text ((Get-Date).ToString('HH:mm:ss'))
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
            $control.Add_Click(({ Set-WinSlimFase7View -Name $target }.GetNewClosure()))
        }
    }

    $btnAnalyze = $window.FindName('BtnAnalyzeSystem')
    if ($null -ne $btnAnalyze) {
        $btnAnalyze.Add_Click(({ & $updateSystem; & $updatePerf; Set-WinSlimFase7View -Name 'Analise' }.GetNewClosure()))
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
    if ($null -ne $btnGoCustom) { $btnGoCustom.Add_Click({ Set-WinSlimFase7View -Name 'Personalizado' }) }

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
            $presetButton.Add_Click(({ Select-WinSlimPresetUi -PresetName $presetName }.GetNewClosure()))
        }
    }
    foreach ($entry in $overlayControlMap.GetEnumerator()) {
        $overlay = $window.FindName([string]$entry.Key)
        if ($null -ne $overlay) {
            $overlay.Add_Checked({ Update-WinSlimPresetSelection })
            $overlay.Add_Unchecked({ Update-WinSlimPresetSelection })
        }
    }
    $highRiskConsent = $window.FindName('ChkAllowHighRiskConditional')
    if ($null -ne $highRiskConsent) {
        $highRiskConsent.Add_Checked({ Update-WinSlimPresetSelection })
        $highRiskConsent.Add_Unchecked({ Update-WinSlimPresetSelection })
    }
    $btnClearOverlays = $window.FindName('BtnClearOverlays')
    if ($null -ne $btnClearOverlays) {
        $btnClearOverlays.Add_Click({
            foreach ($entry in $overlayControlMap.GetEnumerator()) {
                $overlay = $window.FindName([string]$entry.Key)
                if ($null -ne $overlay) { $overlay.IsChecked = $false }
            }
            $consent = $window.FindName('ChkAllowHighRiskConditional')
            if ($null -ne $consent) { $consent.IsChecked = $false }
            Update-WinSlimPresetSelection
        })
    }
    $btnPresetNext = $window.FindName('BtnPresetNext')
    if ($null -ne $btnPresetNext) {
        $btnPresetNext.Add_Click({
            [System.Windows.MessageBox]::Show(
                'A seleção do preset e dos overlays está resolvida pelo PresetRuntime. A pré-visualização transacional será conectada na FASE 7 R5; nenhuma alteração foi aplicada.',
                'Win-Slim Suite — FASE 7 R3',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Information
            ) | Out-Null
        })
    }

    $btnClose = $window.FindName('BtnClose')
    if ($null -ne $btnClose) { $btnClose.Add_Click({ $window.Close() }) }
    $btnMinimize = $window.FindName('BtnMinimize')
    if ($null -ne $btnMinimize) { $btnMinimize.Add_Click({ $window.WindowState = 'Minimized' }) }
    $btnMaximize = $window.FindName('BtnMaximize')
    if ($null -ne $btnMaximize) {
        $btnMaximize.Add_Click({
            if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
        })
    }
    $drag = $window.FindName('TopDragArea')
    if ($null -ne $drag) {
        $drag.Add_MouseLeftButtonDown({
            param($sender,$e)
            if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
            if ($e.ClickCount -eq 2) {
                if ($window.WindowState -eq 'Maximized') { $window.WindowState = 'Normal' } else { $window.WindowState = 'Maximized' }
            } else {
                try { $window.DragMove() } catch { }
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

    Set-WinSlimControlText -Name 'TxtRuntimeState' -Text $runtimeText
    Set-WinSlimControlText -Name 'TxtRuntimeDetail' -Text $runtimeDetail
    Set-WinSlimControlText -Name 'TxtBackendState' -Text ($(if ($backendCount -gt 0) { "Backend: $backendCount tweaks" } else { 'Backend: indisponivel' }))
    if ($backendCount -gt 0) { Set-WinSlimControlText -Name 'TxtTweakCount' -Text "$backendCount / $backendCount" }

    $metricTimer = New-Object System.Windows.Threading.DispatcherTimer
    $metricTimer.Interval = [TimeSpan]::FromSeconds(3)
    $metricTimer.Add_Tick(({ & $updatePerf }.GetNewClosure()))
    $window.Add_Closed({ try { $metricTimer.Stop() } catch { } })
    $window.Add_ContentRendered(({ & $updateSystem; & $updatePerf; Update-WinSlimOverlayEligibility; Update-WinSlimPresetSelection; $metricTimer.Start() }.GetNewClosure()))

    Set-WinSlimFase7View -Name 'Inicio'
    $window.ShowDialog() | Out-Null
}
