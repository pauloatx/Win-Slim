#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R2
 Shell principal + Dashboard e Analise do Sistema conectados a hardware/contexto.

 Esta camada continua sem aplicar tweaks, sem executar providers e sem alterar
 configuracoes do Windows. R2 adiciona somente leituras e apresentacao de estado.
#>

function Show-WinSlimFase7Shell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        $PresetRuntime = $null,
        $PromotionStatus = $null
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $RootPath 'src\UI\Fase7\WinSlimShell.R2.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "XAML da FASE 7 R2 nao encontrado: $xamlPath"
    }

    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $window) { throw 'Falha ao carregar WinSlimShell.xaml.' }

    $script:WinSlimFase7Window = $window
    $script:WinSlimFase7Pages = @{}
    $script:WinSlimFase7NavButtons = @{}
    $script:WinSlimFase7SystemSnapshot = $null

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

    $updateSystem = {
        Set-WinSlimControlText -Name 'TxtStatus' -Text 'Lendo hardware e contexto do sistema...'
        try {
            if (-not (Get-Command Get-WinSlimUiSystemSnapshot -ErrorAction SilentlyContinue)) {
                throw 'Leitor de contexto da FASE 7 R2 nao foi carregado.'
            }
            $snapshot = Get-WinSlimUiSystemSnapshot
            $script:WinSlimFase7SystemSnapshot = $snapshot

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

    # R2 mantem os presets sem execucao. A integracao funcional pertence a R3.
    foreach ($presetButtonName in @('BtnPresetBalanced','BtnPresetGamer','BtnPresetExtreme')) {
        $presetButton = $window.FindName($presetButtonName)
        if ($null -ne $presetButton) {
            $presetButton.Add_Click({ Set-WinSlimFase7View -Name 'Personalizado' })
        }
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
    $window.Add_ContentRendered(({ & $updateSystem; & $updatePerf; $metricTimer.Start() }.GetNewClosure()))

    Set-WinSlimFase7View -Name 'Inicio'
    $window.ShowDialog() | Out-Null
}
