#requires -Version 5.1
<#
 Win-Slim Suite - FASE 7 R1
 Shell principal, navegacao e tema.

 Esta camada e somente UI. Ela nao altera o Windows, nao executa providers e
 nao chama Apply/Undo. A integracao funcional sera adicionada nas revisoes R2-R7.
#>

function Show-WinSlimFase7Shell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RootPath,
        $PresetRuntime = $null,
        $PromotionStatus = $null
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    $xamlPath = Join-Path $RootPath 'src\UI\Fase7\WinSlimShell.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath)) {
        throw "XAML da FASE 7 R1 nao encontrado: $xamlPath"
    }

    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ($null -eq $window) { throw 'Falha ao carregar WinSlimShell.xaml.' }

    $script:WinSlimFase7Window = $window
    $script:WinSlimFase7Pages = @{}
    $script:WinSlimFase7NavButtons = @{}

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
        $status = $window.FindName('TxtStatus')
        if ($null -ne $status) { $status.Text = "Pronto — $Name" }
    }

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
    if ($null -ne $btnAnalyze) { $btnAnalyze.Add_Click({ Set-WinSlimFase7View -Name 'Analise' }) }
    $btnGoCustom = $window.FindName('BtnGoCustom')
    if ($null -ne $btnGoCustom) { $btnGoCustom.Add_Click({ Set-WinSlimFase7View -Name 'Personalizado' }) }

    # Os cards de preset em R1 apenas levam ao shell Personalizado. Nenhum Apply e executado.
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
            # Evita iniciar drag quando o clique partiu de um Button.
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

    $txtRuntime = $window.FindName('TxtRuntimeState')
    if ($null -ne $txtRuntime) { $txtRuntime.Text = $runtimeText }
    $txtRuntimeDetail = $window.FindName('TxtRuntimeDetail')
    if ($null -ne $txtRuntimeDetail) { $txtRuntimeDetail.Text = $runtimeDetail }
    $txtBackend = $window.FindName('TxtBackendState')
    if ($null -ne $txtBackend) { $txtBackend.Text = if ($backendCount -gt 0) { "Backend: $backendCount tweaks" } else { 'Backend: indisponivel' } }
    $txtTweakCount = $window.FindName('TxtTweakCount')
    if ($null -ne $txtTweakCount -and $backendCount -gt 0) { $txtTweakCount.Text = "$backendCount / $backendCount" }

    Set-WinSlimFase7View -Name 'Inicio'
    $window.ShowDialog() | Out-Null
}
