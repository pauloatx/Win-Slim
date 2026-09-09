# Win-Slim Suite v2.0 - Otimizador e Debloat para Windows 10/11
#
# Consolida WinUtil, Atlas-OS, Win-Debloat-Tools, MeetRevision Playbook e Win-Slim.
# v2.0:
#   - VirusTotal REMOVIDO (verificação externa e varredura do sistema).
#     Substituido por confirmação manual para downloads externos.
#   - Novo layout com 3 abas: Bem-vindo, Avançado e Manutenção.
#   - Suporte a catálogos múltiplos: catalog.json + catalog-additions.json
#     (+ qualquer *.json na subpasta "catalogs/"), mesclados por ID.
#   - Rollback por snapshot real mantido (captura estado anterior a cada aplicação).
#   - Aba Manutenção: ações rápidas reutilizando o motor (ponto de restauração,
#     limpeza, SFC/DISM, reiniciar Explorer), exportar/importar seleção.
#
# Execute como Administrador. Compatível com Windows 10 e Windows 11.

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Este script requer Windows PowerShell 5.1 ou superior. Sua versão: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ============================================================================
# 0. BOOTSTRAP / ELEVAÇÃO
#    (a) Arquivo local (.ps1 + catalog.json na mesma pasta).
#    (b) Remoto via "irm <url>/WinSlimSuite.ps1 | iex" - catalog.json é baixado
#        para %LOCALAPPDATA%\WinSlimSuite e a auto-elevação relança o irm|iex.
# ============================================================================
$RepoRawBase = 'https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/heads/main'
$IsRemoteRun = [string]::IsNullOrEmpty($PSCommandPath)

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    if ($IsRemoteRun) {
        $remoteCmd = "irm $($RepoRawBase)/WinSlimSuite.ps1 | iex"
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $remoteCmd) -Verb RunAs
    } else {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    }
    exit
}

# ASCII-only block on purpose: roda antes de podermos confiar no decoding do
# processo. Re-lemos o próprio arquivo como UTF-8 e re-executamos via
# Invoke-Expression exatamente uma vez (marcador anti-loop por processo).
if ($PSCommandPath -and -not $env:WINSLIM_UTF8_OK) {
    $env:WINSLIM_UTF8_OK = '1'
    $fullText = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    Invoke-Expression $fullText
    exit
}

if ($IsRemoteRun) {
    $ScriptRoot = Join-Path $env:LOCALAPPDATA 'WinSlimSuite'
    if (-not (Test-Path $ScriptRoot)) { New-Item -Path $ScriptRoot -ItemType Directory -Force | Out-Null }
} else {
    $ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
}
$StatePath     = Join-Path $ScriptRoot 'winslim-state.json'
$RollbackPath  = Join-Path $ScriptRoot 'winslim-rollback.json'
$LogPath       = Join-Path $ScriptRoot 'winslim-log.txt'
$CatalogPath   = Join-Path $ScriptRoot 'catalog.json'
$AdditionsPath = Join-Path $ScriptRoot 'catalog-additions.json'
$CatalogsDir   = Join-Path $ScriptRoot 'catalogs'

# ============================================================================
# 1. LOG (definido antes da carga dos catálogos para registrar falhas de carga)
# ============================================================================
$script:LogBox = $null
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
    if ($script:LogBox) {
        try { $script:LogBox.Dispatcher.Invoke([Action]{ $script:LogBox.AppendText("$line`r`n"); $script:LogBox.ScrollToEnd() }) } catch { }
    }
}

# Invoke-Safe: reservado para AÇÕES DELIBERADAS. Interações leves usam try/catch
# simples SEM caixa de mensagem — só registram no log.
function Invoke-Safe {
    param([scriptblock]$Action, [string]$Context = 'ação')
    try { & $Action }
    catch {
        Write-Log "Erro em '$Context': $($_.Exception.Message)" 'ERROR'
        try { [System.Windows.MessageBox]::Show("Ocorreu um erro em '$Context':`n$($_.Exception.Message)`n`nDetalhes no log:`n$LogPath", "Win-Slim Suite", 'OK', 'Warning') | Out-Null } catch { }
    }
}

# ============================================================================
# 2. CARGA MULTI-CATÁLOGO
#    catalog.json (base) + catalog-additions.json (opcional) + catalogs\*.json
#    Tweaks com mesmo ID: o arquivo carregado por último sobrescreve o anterior.
# ============================================================================
if ($IsRemoteRun) {
    try {
        Invoke-WebRequest -Uri "$($RepoRawBase)/catalog.json" -OutFile $CatalogPath -UseBasicParsing -TimeoutSec 20
    } catch {
        [System.Windows.MessageBox]::Show("Não foi possível baixar o catalog.json do GitHub:`n$($_.Exception.Message)`n`nVerifique sua conexão com a internet.", "Win-Slim Suite", 'OK', 'Error') | Out-Null
        exit 1
    }
}

$CatalogFiles = New-Object System.Collections.Generic.List[string]
if (Test-Path $CatalogPath)   { $CatalogFiles.Add($CatalogPath) }
if (Test-Path $AdditionsPath) { $CatalogFiles.Add($AdditionsPath) }
if (Test-Path $CatalogsDir) {
    Get-ChildItem -Path $CatalogsDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $CatalogFiles.Add($_.FullName) }
}

if ($CatalogFiles.Count -eq 0) {
    [System.Windows.MessageBox]::Show("Nenhum catálogo encontrado. Coloque catalog.json na mesma pasta deste script (modo local) ou verifique sua conexão (modo irm|iex).", "Win-Slim Suite", 'OK', 'Error') | Out-Null
    exit 1
}

$TweakById = [ordered]@{}
foreach ($file in $CatalogFiles) {
    try {
        $raw = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
        $cat = $raw | ConvertFrom-Json
        foreach ($t in $cat.tweaks) {
            if ($TweakById.Contains($t.id)) {
                Write-Log "Tweak '$($t.id)' redefinido por '$file' (sobrescreve definição anterior)." 'WARN'
                $TweakById[$t.id] = $t
            } else {
                $TweakById[$t.id] = $t
            }
        }
        Write-Log "Catálogo carregado: $file ($($cat.tweaks.Count) entradas)." 'INFO'
    } catch {
        Write-Log "FALHA ao carregar catálogo '$file': $($_.Exception.Message)" 'ERROR'
    }
}
$AllTweaks = @($TweakById.Values)

# ============================================================================
# 3. DETECÇÃO DE SISTEMA + ESTADO PERSISTENTE
# ============================================================================
function Get-WinMajorVersion {
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    if ($build -ge 22000) { return '11' } else { return '10' }
}
$WinVersion = Get-WinMajorVersion
$WinBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
$VisibleTweaks = @($AllTweaks | Where-Object { $_.windowsVersion -contains $WinVersion })
Write-Log "Windows $($WinVersion) build $($WinBuild) - $($AllTweaks.Count) tweaks no catálogo, $($VisibleTweaks.Count) visíveis neste SO."

if (Test-Path $StatePath) {
    $AppliedState = @{}
    try { (Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $AppliedState[$_.Name] = $_.Value } } catch { $AppliedState = @{} }
} else { $AppliedState = @{} }
function Save-State { $AppliedState | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatePath -Encoding UTF8 }

# ============================================================================
# 4. ESTADO DE SELEÇÃO EM MEMÓRIA
# ============================================================================
$SelectedIds = [System.Collections.Generic.HashSet[string]]::new()
$LevelSelections = @{}

# ============================================================================
# 5. DOWNLOADS EXTERNOS - confirmação manual (VirusTotal foi REMOVIDO na v2.0)
#    Mantida a mesma assinatura (Confirm-DownloadIsSafe) para compatibilidade
#    com tweaks do catálogo que baixam ferramentas externas (ex.: UI-005/ViVeTool).
#    O usuário vê o que será baixado/executado e decide. Falha fechada por padrão.
# ============================================================================
function Confirm-DownloadIsSafe {
    param([string]$FilePath, [string]$FriendlyName)
    $msg = "Esta ação vai executar um arquivo baixado pela ferramenta:`n`n$FilePath`n`n" +
           "A verificação automática via VirusTotal foi REMOVIDA nesta versão. " +
           "Só prossiga se você confia na origem (GitHub oficial do projeto).`n`nExecutar mesmo assim?"
    $r = [System.Windows.MessageBox]::Show($msg, "Win-Slim Suite - Confirmação de Segurança", 'YesNo', 'Warning')
    if ($r -eq 'Yes') { Write-Log "Usuário confirmou execução de '$FriendlyName' ($FilePath)." 'INFO'; return $true }
    Write-Log "Usuário CANCELOU a execução de '$FriendlyName'." 'WARN'
    return $false
}

# Stub de compatibilidade: a varredura VirusTotal do sistema foi removida na v2.0.
# O tweak EXT-005 (se ainda presente no catálogo) agora apenas registra isso no log.
function Invoke-SystemSecurityScan {
    param([switch]$Silent)
    Write-Log "A verificação de segurança via VirusTotal foi REMOVIDA na v2.0. Remova o item EXT-005 do catalog.json (opcional)." 'WARN'
    if (-not $Silent) {
        [System.Windows.MessageBox]::Show("A varredura com VirusTotal foi removida nesta versão do Win-Slim Suite.", "Win-Slim Suite", 'OK', 'Information') | Out-Null
    }
    return @()
}

# ============================================================================
# 6. ROLLBACK PROFISSIONAL - captura o estado REAL antes de cada alteração
# ============================================================================
if (Test-Path $RollbackPath) {
    $RollbackData = @{}
    try { (Get-Content $RollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $RollbackData[$_.Name] = $_.Value } } catch { $RollbackData = @{} }
} else { $RollbackData = @{} }

function Save-Rollback { $RollbackData | ConvertTo-Json -Depth 10 | Out-File -FilePath $RollbackPath -Encoding UTF8 }

function Get-CurrentRegistryState {
    param($Path, $Name)
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($item -and ($item.PSObject.Properties.Name -contains $Name)) {
            return [PSCustomObject]@{ Existed = $true; Value = $item.$Name }
        }
    }
    return [PSCustomObject]@{ Existed = $false; Value = $null }
}

function Backup-BeforeApply {
    param([string]$TweakId, $Payload)
    $snap = [PSCustomObject]@{ timestamp = (Get-Date -Format 'o'); registry = @(); service = @() }
    if ($Payload.registry) {
        foreach ($r in $Payload.registry) {
            $cur = Get-CurrentRegistryState -Path $r.Path -Name $r.Name
            $snap.registry += [PSCustomObject]@{ Path = $r.Path; Name = $r.Name; Type = $r.Type; Existed = $cur.Existed; PriorValue = $cur.Value }
        }
    }
    if ($Payload.service) {
        foreach ($s in $Payload.service) {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            if ($svc) { $snap.service += [PSCustomObject]@{ Name = $s.Name; PriorStartupType = $svc.StartType.ToString() } }
        }
    }
    $RollbackData[$TweakId] = $snap
}

function Restore-FromSnapshot {
    param([string]$TweakId)
    if (-not $RollbackData.ContainsKey($TweakId)) { return $false }
    $snap = $RollbackData[$TweakId]
    foreach ($r in $snap.registry) {
        if ($r.Existed) { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.PriorValue -Type $r.Type }
        else { Remove-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue }
    }
    foreach ($s in $snap.service) {
        Set-Service -Name $s.Name -StartupType $s.PriorStartupType -ErrorAction SilentlyContinue
    }
    $RollbackData.Remove($TweakId)
    return $true
}

# ============================================================================
# 7. MOTOR DE APLICAÇÃO / DESFAZIMENTO
# ============================================================================
function Set-RegistryValue {
    param($Path, $Name, $Value, $Type)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ("$Value" -eq '<Remove>') { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
    else { New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null }
}

function Invoke-Payload {
    param($Payload, [switch]$Undo)
    if ($Payload.registry) {
        foreach ($r in $Payload.registry) {
            if ($Undo -and $r.PSObject.Properties.Name -contains 'OriginalValue') {
                Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.OriginalValue -Type $r.Type
            } elseif (-not $Undo) {
                Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type
            }
        }
    }
    if ($Payload.service) {
        foreach ($s in $Payload.service) {
            $target = if ($Undo) { $s.OriginalType } else { $s.StartupType }
            if ($Undo -and -not $target) { continue }
            try {
                Set-Service -Name $s.Name -StartupType $target -ErrorAction SilentlyContinue
                if ($target -eq 'Automatic' -or $target -eq 'AutomaticDelayedStart') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
            } catch { Write-Log "Serviço $($s.Name) não encontrado, ignorado." 'WARN' }
        }
    }
    $scriptBlock = if ($Undo) { $Payload.UndoScript } else { $Payload.InvokeScript }
    if ($scriptBlock) { Invoke-Expression ($scriptBlock -join "`n") }
}

function Invoke-TweakEngine {
    param($Tweak, [switch]$Undo, [int]$Level = -1)
    $mode = if ($Undo) { 'UNDO' } else { 'APPLY' }
    Write-Log "[$mode] $($Tweak.id) - $($Tweak.name)"
    try {
        if ($Tweak.type -eq 'multilevel') {
            if ($Undo) {
                if (Restore-FromSnapshot -TweakId $Tweak.id) {
                    Write-Log "[UNDO] $($Tweak.id) -> rollback profissional aplicado (estado real anterior restaurado)." 'OK'
                    return $true
                }
                $levelObj = $Tweak.levels[0]
                Invoke-Payload -Payload $levelObj
                Write-Log "[UNDO] $($Tweak.id) -> sem snapshot; aplicado nível padrão do catálogo." 'WARN'
                return $true
            } else {
                $idx = if ($Level -lt 0) { 0 } else { $Level }
                $levelObj = $Tweak.levels[$idx]
                Backup-BeforeApply -TweakId $Tweak.id -Payload $levelObj
                Invoke-Payload -Payload $levelObj
                Write-Log "[APPLY] $($Tweak.id) -> nível '$($levelObj.name)' aplicado (snapshot de rollback salvo)." 'OK'
                return $true
            }
        }

        if ($Undo) {
            if (Restore-FromSnapshot -TweakId $Tweak.id) {
                Write-Log "[UNDO] $($Tweak.id) -> rollback profissional aplicado (estado real anterior restaurado)." 'OK'
            } else {
                Invoke-Payload -Payload $Tweak -Undo
                Write-Log "[UNDO] $($Tweak.id) -> sem snapshot; usado valor padrão do catálogo." 'WARN'
            }
        } else {
            Backup-BeforeApply -TweakId $Tweak.id -Payload $Tweak
            Invoke-Payload -Payload $Tweak
        }

        if ($Tweak.packages -and -not $Undo) {
            foreach ($pkg in $Tweak.packages) {
                Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pkg } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            }
        } elseif ($Tweak.packages -and $Undo) {
            Write-Log "Apps removidos ($($Tweak.id)) não são reinstalados automaticamente. Use a Microsoft Store se precisar." 'WARN'
        }
        if ($Tweak.capabilityName -and -not $Undo) {
            try {
                $cap = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Tweak.capabilityName)*" }
                if ($cap) { $cap | Remove-WindowsCapability -Online -ErrorAction SilentlyContinue | Out-Null }
            } catch { Write-Log "Capability $($Tweak.capabilityName) ausente, ignorado." 'WARN' }
        }
        if ($Tweak.hosts) {
            $hostsFile = "$Env:SystemRoot\System32\drivers\etc\hosts"
            $marker = "WinSlimSuite-$($Tweak.id)"
            $current = Get-Content $hostsFile -ErrorAction SilentlyContinue
            if ($Undo) {
                $filtered = $current | Where-Object { $_ -notmatch [regex]::Escape($marker) }
                Set-Content -Path $hostsFile -Value $filtered -Encoding ASCII
            } else {
                $existingLines = $current -join "`n"
                $toAdd = $Tweak.hosts | ForEach-Object { "0.0.0.0 $_  # $marker" } | Where-Object { $existingLines -notmatch [regex]::Escape($_) }
                if ($toAdd) { Add-Content -Path $hostsFile -Value $toAdd -Encoding ASCII }
            }
        }

        Write-Log "[$mode] $($Tweak.id) concluído com sucesso." 'OK'
        return $true
    } catch {
        Write-Log "[$mode] $($Tweak.id) FALHOU: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Resolve-Conflicts {
    param([string[]]$SelectedIds)
    $final = [System.Collections.Generic.List[string]]::new()
    $skipped = @()
    foreach ($id in $SelectedIds) {
        $tweak = $AllTweaks | Where-Object { $_.id -eq $id }
        if (-not $tweak) { continue }
        $conflict = @($tweak.conflicts) | Where-Object { $final -contains $_ }
        if ($conflict) { $skipped += "$id (conflita com $($conflict -join ', '))"; continue }
        $final.Add($id)
    }
    if ($skipped) { Write-Log "Itens ignorados por conflito: $($skipped -join '; ')" 'WARN' }
    return $final
}

# ============================================================================
# 8. XAML DA INTERFACE (layout v2: 3 abas)
# ============================================================================
[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Win-Slim Suite" Height="880" Width="1380" WindowStartupLocation="CenterScreen"
        Background="#0F1115" FontFamily="Segoe UI">
    <Window.Resources>
        <SolidColorBrush x:Key="Accent" Color="#FF8C42"/>
        <SolidColorBrush x:Key="Panel" Color="#171A21"/>
        <SolidColorBrush x:Key="PanelAlt" Color="#1E222B"/>
        <SolidColorBrush x:Key="TextMain" Color="#E7E9EE"/>
        <SolidColorBrush x:Key="TextDim" Color="#9AA0AC"/>
        <LinearGradientBrush x:Key="OrangeGradient" StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#FFD9A15C" Offset="0"/>
            <GradientStop Color="#FF8C42" Offset="0.55"/>
            <GradientStop Color="#C9611C" Offset="1"/>
        </LinearGradientBrush>

        <Style TargetType="Button" x:Key="PresetBtn">
            <Setter Property="Background" Value="{StaticResource PanelAlt}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Margin" Value="4,0"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="BorderBrush" Value="#2A2F3A"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#262B36"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button" x:Key="ActionBtn" BasedOn="{StaticResource PresetBtn}">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="Foreground" Value="#1A0F08"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#FFA968"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button" x:Key="WelcomeBtn" BasedOn="{StaticResource PresetBtn}">
            <Setter Property="Padding" Value="18,12"/>
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="Margin" Value="0,0,0,6"/>
            <Setter Property="HorizontalAlignment" Value="Left"/>
            <Setter Property="MinWidth" Value="250"/>
            <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
        </Style>
        <Style TargetType="Button" x:Key="MaintBtn" BasedOn="{StaticResource PresetBtn}">
            <Setter Property="Padding" Value="16,14"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
            <Setter Property="HorizontalAlignment" Value="Stretch"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
        </Style>
        <Style TargetType="CheckBox"><Setter Property="Foreground" Value="{StaticResource TextMain}"/></Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource PanelAlt}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="BorderBrush" Value="#2A2F3A"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextMain}"/>
        </Style>
        <Style TargetType="ListBoxItem">
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="Margin" Value="0,1"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#1E222B"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#2A1D12"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="{StaticResource PanelAlt}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="Margin" Value="0,6,0,0"/>
        </Style>
        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="{StaticResource PanelAlt}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
        </Style>
        <Style TargetType="ToolTip">
            <Setter Property="Background" Value="#22262F"/>
            <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
            <Setter Property="Padding" Value="8"/>
            <Setter Property="MaxWidth" Value="360"/>
        </Style>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="{StaticResource Panel}"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Padding" Value="16,11"/>
            <Setter Property="Foreground" Value="{StaticResource TextDim}"/>
            <Setter Property="FontSize" Value="13.5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd" Background="{StaticResource Panel}" BorderBrush="Transparent" BorderThickness="0,0,0,3" Padding="{TemplateBinding Padding}">
                            <ContentPresenter x:Name="Cp" ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Foreground" Value="{StaticResource TextMain}"/>
                    <Setter Property="FontWeight" Value="Bold"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>

    <DockPanel>
        <!-- HEADER GLOBAL -->
        <Border DockPanel.Dock="Top" Background="{StaticResource Panel}" Padding="18,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Orientation="Horizontal">
                    <Viewbox Width="26" Height="26" Margin="0,0,10,0" VerticalAlignment="Center">
                        <Canvas Width="64" Height="64">
                            <Path Data="M14,56 C10,46 12,34 20,24 C26,17 34,12 50,8 C40,14 26,24 20,34 C14,42 12,50 14,56 Z"
                                  Fill="{StaticResource OrangeGradient}" Stroke="#8C4A14" StrokeThickness="1.1" StrokeLineJoin="Round"/>
                            <Path Data="M20,24 C26,17 34,12 50,8" Stroke="#FFEEDC" StrokeThickness="0.8" StrokeStartLineCap="Round" Opacity="0.55"/>
                            <Path Data="M14,56 C16,46 20,34 26,26 C32,20 40,14 50,8"
                                  Stroke="#FFF1DE" StrokeThickness="1.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0.9"/>
                            <Path Data="M16,52 L13.6,50.2 M16,52 L18.4,53.6 M18,47 L14,44 M18,47 L22,49.5 M20,42 L14.4,37.8 M20,42 L25.4,45.6 M22,37 L15.6,32.2 M22,37 L28.2,41.2 M25,32 L17.8,26.6 M25,32 L32,36.8 M29,27 L22.6,22.2 M29,27 L35.2,31.2 M33,22 L28.2,18.4 M33,22 L37.6,25 M38,18 L34.8,15.6 M38,18 L41,20 M44,13 L42.4,11.8 M44,13 L45.4,14"
                                  Stroke="#8C4A14" StrokeThickness="0.9" StrokeStartLineCap="Round" Opacity="0.8"/>
                            <Path Data="M14,56 L11,60" Stroke="#8C4A14" StrokeThickness="1.3" StrokeStartLineCap="Round"/>
                        </Canvas>
                    </Viewbox>
                    <TextBlock Text="Win-Slim Suite" FontSize="20" FontWeight="Bold" Foreground="{StaticResource TextMain}" VerticalAlignment="Center"/>
                    <TextBlock x:Name="OsBadge" Text="" FontSize="12" Foreground="{StaticResource TextDim}" Margin="14,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <CheckBox x:Name="ChkRestorePoint" Grid.Column="1" Content="Criar ponto de restauração antes de aplicar"
                          ToolTip="Fortemente recomendado: cria um checkpoint do Windows para reverter tudo em caso de problema."
                          IsChecked="True" VerticalAlignment="Center"/>
            </Grid>
        </Border>

        <TabControl x:Name="MainTabs">
            <!-- ================= ABA BEM-VINDO ================= -->
            <TabItem Header="👋 Bem-vindo">
                <Grid Background="#12141A">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Padding="36,28,36,16">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel MaxWidth="700" HorizontalAlignment="Left">
                                <TextBlock Text="Bem-vindo ao Win-Slim Suite" FontSize="24" FontWeight="Bold" Foreground="{StaticResource TextMain}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="13" TextWrapping="Wrap" Margin="0,6,0,20">
                                    Escolha um preset abaixo para começar. Cada um marca automaticamente um conjunto de
                                    tweaks — você pode aplicar direto por aqui, ou revisar e ajustar tudo individualmente
                                    na aba Avançado. A aba Manutenção traz ações rápidas de cuidado do sistema.
                                </TextBlock>

                                <StackPanel Margin="0,0,0,16">
                                    <CheckBox x:Name="ChkGamer" Content="🎮 Sou Gamer" FontSize="13.5" FontWeight="SemiBold"/>
                                    <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="22,4,0,0">
                                        Marque se joga no PC. Isto mantém os apps do Xbox instalados (só desativa a gravação
                                        em segundo plano). Se desmarcado, os apps do Xbox são removidos por completo.
                                    </TextBlock>
                                </StackPanel>

                                <Button x:Name="BtnWelcomeBalanceado" Content="⚖  Balanceado" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    Otimizações seguras de baixo risco, com impacto real: privacidade, debloat básico,
                                    limpeza de interface e ajustes de responsividade. Bom ponto de partida para qualquer PC.
                                </TextBlock>

                                <Button x:Name="BtnWelcomeGamer" Content="🎮  Gamer" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    Tudo do Balanceado, mais: plano de energia Alto Desempenho, prioridade de CPU para o
                                    jogo em foco, ajustes de rede/latência (Nagle, throttling, FSO, HAGS) e redução de
                                    prioridade de processos em segundo plano.
                                </TextBlock>

                                <Button x:Name="BtnWelcomeExtremo" Content="🔥  Extremo" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    O máximo de agressividade sem gerar conflitos entre tweaks: remove componentes de
                                    IA/Copilot, ativa o plano Ultimate Performance e aplica ajustes avançados de sistema,
                                    rede e disco. Itens de risco Alto continuam de fora e exigem confirmação manual.
                                </TextBlock>

                                <Border x:Name="WelcomeStatusBorder" Background="{StaticResource PanelAlt}" CornerRadius="10" Padding="14" Margin="0,4,0,10" Visibility="Collapsed">
                                    <TextBlock x:Name="WelcomeStatusText" Foreground="{StaticResource TextMain}" FontSize="12.5" FontWeight="SemiBold" TextWrapping="Wrap"/>
                                </Border>

                                <Border Background="{StaticResource PanelAlt}" CornerRadius="10" Padding="14">
                                    <TextBlock Foreground="{StaticResource TextDim}" FontSize="11.5" TextWrapping="Wrap">
                                        💡 Depois de escolher um preset, você pode aplicar direto pelo botão abaixo, ou
                                        conferir e ajustar tudo na aba
                                        <Run Foreground="{StaticResource Accent}" FontWeight="Bold">Avançado</Run>.
                                        Sem telemetria, sem verificação externa: tudo roda localmente no seu PC.
                                    </TextBlock>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>

                    <Border Grid.Row="1" Background="{StaticResource Panel}" BorderThickness="0,1,0,0" BorderBrush="#22262F" Padding="36,14">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <StackPanel Grid.Column="0" VerticalAlignment="Center" Margin="0,0,16,0">
                                <ProgressBar x:Name="WelcomeProgBar" Height="9" Margin="0,0,0,7" Background="{StaticResource PanelAlt}" Foreground="{StaticResource Accent}"/>
                                <TextBlock x:Name="WelcomeCompletionText" Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap"/>
                            </StackPanel>
                            <StackPanel Grid.Column="1" Orientation="Horizontal">
                                <Button x:Name="BtnWelcomeApply" Content="✓ Aplicar Perfil" Style="{StaticResource ActionBtn}"/>
                                <Button x:Name="BtnWelcomeUndo" Content="↺ Rollback" Style="{StaticResource PresetBtn}" ToolTip="Restaura o estado real capturado antes da última aplicação."/>
                                <Button x:Name="BtnWelcomeRestart" Content="⟳ Reiniciar Sistema" Style="{StaticResource PresetBtn}"/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ================= ABA AVANÇADO ================= -->
            <TabItem Header="⚙ Avançado">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="160"/>
                    </Grid.RowDefinitions>

                    <Border Grid.Row="0" Background="{StaticResource Panel}" Padding="18,9" BorderThickness="0,0,0,1" BorderBrush="#22262F">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Presets:" Foreground="{StaticResource TextDim}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                            <Button x:Name="BtnBalanceado" Content="⚖ Balanceado" Style="{StaticResource PresetBtn}"/>
                            <Button x:Name="BtnGamer" Content="🎮 Gamer" Style="{StaticResource PresetBtn}"/>
                            <Button x:Name="BtnExtremo" Content="🔥 Extremo" Style="{StaticResource PresetBtn}"/>
                            <Border Width="1" Background="#2A2F3A" Margin="10,4"/>
                            <Button x:Name="BtnMarcarVisiveis" Content="☑ Marcar Visíveis" Style="{StaticResource PresetBtn}"/>
                            <Button x:Name="BtnDesmarcarVisiveis" Content="☐ Desmarcar Visíveis" Style="{StaticResource PresetBtn}"/>
                            <Button x:Name="BtnLimpar" Content="✕ Limpar Tudo" Style="{StaticResource PresetBtn}"/>
                        </StackPanel>
                    </Border>

                    <Border Grid.Row="1" Background="{StaticResource Panel}" Padding="18,9" BorderThickness="0,0,0,1" BorderBrush="#22262F">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="TxtSearch" Grid.Column="0" VerticalContentAlignment="Center"/>
                            <TextBlock x:Name="SelectionCount" Grid.Column="1" Foreground="{StaticResource TextDim}" VerticalAlignment="Center" Margin="14,0,0,0" FontSize="12"/>
                        </Grid>
                    </Border>

                    <Grid Grid.Row="2">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="230"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Border Grid.Column="0" Background="{StaticResource Panel}">
                            <ListBox x:Name="CategoryList" Background="Transparent" BorderThickness="0" Margin="8,10" Foreground="{StaticResource TextMain}" FontSize="13"/>
                        </Border>
                        <Border Grid.Column="1" Background="#12141A">
                            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="18,12">
                                <ItemsControl x:Name="TweakList"/>
                            </ScrollViewer>
                        </Border>
                    </Grid>

                    <Border Grid.Row="3" Background="{StaticResource Panel}" BorderThickness="0,1,0,0" BorderBrush="#22262F" Padding="18,9">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="240"/>
                            </Grid.ColumnDefinitions>
                            <TextBox x:Name="LogBox" Grid.Column="0" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                                     FontFamily="Consolas" FontSize="10.5" Background="#0B0D11" BorderThickness="0" Margin="0,0,12,0"/>
                            <StackPanel Grid.Column="1" VerticalAlignment="Center">
                                <ProgressBar x:Name="ProgBar" Height="9" Margin="0,0,0,7" Background="{StaticResource PanelAlt}" Foreground="{StaticResource Accent}"/>
                                <Button x:Name="BtnApply" Content="Aplicar Selecionados" Style="{StaticResource ActionBtn}" Margin="0,0,0,6"/>
                                <Button x:Name="BtnUndo" Content="↺ Rollback (Desfazer)" Style="{StaticResource PresetBtn}" ToolTip="Restaura o estado real capturado antes da última aplicação de cada item marcado."/>
                            </StackPanel>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- ================= ABA MANUTENÇÃO (NOVA) ================= -->
            <TabItem Header="🛠 Manutenção">
                <Grid Background="#12141A">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="360"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0" Padding="28,24" Background="#12141A">
                        <StackPanel>
                            <TextBlock Text="Ações rápidas" FontSize="18" FontWeight="Bold" Foreground="{StaticResource TextMain}" Margin="0,0,0,4"/>
                            <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,18">
                                Execute tarefas de cuidado do sistema diretamente. Cada ação usa o mesmo motor de aplicação
                                com rollback quando aplicável.
                            </TextBlock>

                            <Button x:Name="BtnMaintRestorePoint" Content="💾  Criar ponto de restauração agora" Style="{StaticResource MaintBtn}"
                                    ToolTip="Cria um checkpoint do sistema imediatamente (EXT-001)."/>
                            <Button x:Name="BtnMaintCleanupTemp" Content="🧹  Limpar arquivos temporários" Style="{StaticResource MaintBtn}"
                                    ToolTip="Remove temporários do usuário/sistema e cache do Windows Update (EXT-002)."/>
                            <Button x:Name="BtnMaintCleanupWinSxS" Content="📦  Limpeza do Component Store (WinSxS)" Style="{StaticResource MaintBtn}"
                                    ToolTip="DISM /StartComponentCleanup - libera espaço ocupado por componentes antigos do Windows (EXTRA-006). Pode demorar."/>
                            <Button x:Name="BtnMaintSfcDism" Content="🔍  Verificação de integridade (SFC / DISM)" Style="{StaticResource MaintBtn}"
                                    ToolTip="Repara arquivos de sistema corrompidos (EXT-003). Pode demorar bastante."/>
                            <Button x:Name="BtnMaintRestartExplorer" Content="🖥  Reiniciar Explorer" Style="{StaticResource MaintBtn}"
                                    ToolTip="Reinicia o shell do Windows para aplicar mudanças de interface sem logoff (EXT-004)."/>
                            <Button x:Name="BtnMaintRestartPC" Content="⟳  Reiniciar computador" Style="{StaticResource MaintBtn}"
                                    ToolTip="Reinicia o sistema para garantir efeito completo dos tweaks."/>
                        </StackPanel>
                    </Border>

                    <Grid Grid.Column="1" Margin="0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>
                        <Border Grid.Row="0" Padding="28,24,28,10">
                            <StackPanel>
                                <TextBlock Text="Seleção e dados" FontSize="18" FontWeight="Bold" Foreground="{StaticResource TextMain}" Margin="0,0,0,4"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap">
                                    Exporte/importe sua seleção de tweaks entre PCs, ou abra a pasta de dados
                                    (catálogo, estado, rollback e log).
                                </TextBlock>
                                <StackPanel Orientation="Horizontal" Margin="0,12,0,0">
                                    <Button x:Name="BtnExportSelection" Content="⤒ Exportar seleção" Style="{StaticResource PresetBtn}"/>
                                    <Button x:Name="BtnImportSelection" Content="⤓ Importar seleção" Style="{StaticResource PresetBtn}"/>
                                    <Button x:Name="BtnOpenDataFolder" Content="📁 Abrir pasta de dados" Style="{StaticResource PresetBtn}"/>
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Grid.Row="1" Padding="28,10" Background="#0B0D11" Margin="28,0,28,24" CornerRadius="10">
                            <TextBox x:Name="MaintLogBox" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                                     FontFamily="Consolas" FontSize="10.5" Background="Transparent" BorderThickness="0"
                                     Foreground="#9AA0AC"/>
                        </Border>
                    </Grid>
                </Grid>
            </TabItem>
        </TabControl>
    </DockPanel>
</Window>
'@

$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)
if (-not $Window) { throw "Falha ao carregar a interface (XamlReader retornou nulo)." }

$OsBadge = $Window.FindName('OsBadge')
$ChkGamer = $Window.FindName('ChkGamer')
$ChkRestorePoint = $Window.FindName('ChkRestorePoint')
$MainTabs = $Window.FindName('MainTabs')
$CategoryList = $Window.FindName('CategoryList')
$TweakList = $Window.FindName('TweakList')
$TxtSearch = $Window.FindName('TxtSearch')
$SelectionCount = $Window.FindName('SelectionCount')
$LogBox = $Window.FindName('LogBox')
$ProgBar = $Window.FindName('ProgBar')
$BtnApply = $Window.FindName('BtnApply')
$BtnUndo = $Window.FindName('BtnUndo')
$BtnBalanceado = $Window.FindName('BtnBalanceado')
$BtnGamer = $Window.FindName('BtnGamer')
$BtnExtremo = $Window.FindName('BtnExtremo')
$BtnLimpar = $Window.FindName('BtnLimpar')
$BtnMarcarVisiveis = $Window.FindName('BtnMarcarVisiveis')
$BtnDesmarcarVisiveis = $Window.FindName('BtnDesmarcarVisiveis')
$BtnWelcomeBalanceado = $Window.FindName('BtnWelcomeBalanceado')
$BtnWelcomeGamer = $Window.FindName('BtnWelcomeGamer')
$BtnWelcomeExtremo = $Window.FindName('BtnWelcomeExtremo')
$WelcomeStatusBorder = $Window.FindName('WelcomeStatusBorder')
$WelcomeStatusText = $Window.FindName('WelcomeStatusText')
$WelcomeProgBar = $Window.FindName('WelcomeProgBar')
$WelcomeCompletionText = $Window.FindName('WelcomeCompletionText')
$BtnWelcomeApply = $Window.FindName('BtnWelcomeApply')
$BtnWelcomeUndo = $Window.FindName('BtnWelcomeUndo')
$BtnWelcomeRestart = $Window.FindName('BtnWelcomeRestart')
$BtnMaintRestorePoint = $Window.FindName('BtnMaintRestorePoint')
$BtnMaintCleanupTemp = $Window.FindName('BtnMaintCleanupTemp')
$BtnMaintCleanupWinSxS = $Window.FindName('BtnMaintCleanupWinSxS')
$BtnMaintSfcDism = $Window.FindName('BtnMaintSfcDism')
$BtnMaintRestartExplorer = $Window.FindName('BtnMaintRestartExplorer')
$BtnMaintRestartPC = $Window.FindName('BtnMaintRestartPC')
$BtnExportSelection = $Window.FindName('BtnExportSelection')
$BtnImportSelection = $Window.FindName('BtnImportSelection')
$BtnOpenDataFolder = $Window.FindName('BtnOpenDataFolder')
$MaintLogBox = $Window.FindName('MaintLogBox')

$controlMap = @{
    OsBadge=$OsBadge; ChkGamer=$ChkGamer; ChkRestorePoint=$ChkRestorePoint; MainTabs=$MainTabs
    CategoryList=$CategoryList; TweakList=$TweakList; TxtSearch=$TxtSearch; SelectionCount=$SelectionCount
    LogBox=$LogBox; ProgBar=$ProgBar; BtnApply=$BtnApply; BtnUndo=$BtnUndo
    BtnBalanceado=$BtnBalanceado; BtnGamer=$BtnGamer; BtnExtremo=$BtnExtremo; BtnLimpar=$BtnLimpar
    BtnMarcarVisiveis=$BtnMarcarVisiveis; BtnDesmarcarVisiveis=$BtnDesmarcarVisiveis
    BtnWelcomeBalanceado=$BtnWelcomeBalanceado; BtnWelcomeGamer=$BtnWelcomeGamer; BtnWelcomeExtremo=$BtnWelcomeExtremo
    WelcomeStatusBorder=$WelcomeStatusBorder; WelcomeStatusText=$WelcomeStatusText
    WelcomeProgBar=$WelcomeProgBar; WelcomeCompletionText=$WelcomeCompletionText
    BtnWelcomeApply=$BtnWelcomeApply; BtnWelcomeUndo=$BtnWelcomeUndo; BtnWelcomeRestart=$BtnWelcomeRestart
    BtnMaintRestorePoint=$BtnMaintRestorePoint; BtnMaintCleanupTemp=$BtnMaintCleanupTemp
    BtnMaintCleanupWinSxS=$BtnMaintCleanupWinSxS; BtnMaintSfcDism=$BtnMaintSfcDism
    BtnMaintRestartExplorer=$BtnMaintRestartExplorer; BtnMaintRestartPC=$BtnMaintRestartPC
    BtnExportSelection=$BtnExportSelection; BtnImportSelection=$BtnImportSelection
    BtnOpenDataFolder=$BtnOpenDataFolder; MaintLogBox=$MaintLogBox
}
$missing = $controlMap.GetEnumerator() | Where-Object { -not $_.Value } | Select-Object -ExpandProperty Key
if ($missing) {
    [System.Windows.MessageBox]::Show("Elementos de interface não encontrados: $($missing -join ', ')`n`nO arquivo pode estar corrompido. Baixe novamente.", "Win-Slim Suite - Erro", 'OK', 'Error') | Out-Null
    exit 1
}

$script:LogBox = $LogBox
$OsBadge.Text = "Windows $($WinVersion)  •  Build $($WinBuild)  •  $($VisibleTweaks.Count) tweaks disponíveis"

# ============================================================================
# 9. POPULAR CATEGORIAS + RENDERIZAÇÃO DE CARDS
# ============================================================================
$Categories = @('Todas') + @($VisibleTweaks | Select-Object -ExpandProperty category -Unique | Sort-Object)
$CategoryList.ItemsSource = $Categories
$CategoryList.SelectedIndex = 0
$CurrentRenderedIds = [System.Collections.Generic.List[string]]::new()

function Update-SelectionCount {
    param($SelectedIdsRef, $LevelSelectionsRef, $CountControl)
    if (-not $SelectedIdsRef -or -not $LevelSelectionsRef -or -not $CountControl) { return }
    $simpleCount = $SelectedIdsRef.Count
    $levelCount = ($LevelSelectionsRef.GetEnumerator() | Where-Object { $_.Value -gt 0 }).Count
    $CountControl.Text = "$simpleCount tweaks marcados + $levelCount ajustes multinível ativos"
}

function New-TweakCard {
    param($Tweak)
    $riskColor = switch ($Tweak.risk) { 'Baixo' { '#3FC97A' } 'Médio' { '#F2C744' } 'Alto' { '#F26D6D' } default { '#9AA0AC' } }
    $tweakId = $Tweak.id
    $tweakLevels = $Tweak.levels
    $isMultilevel = ($Tweak.type -eq 'multilevel')

    $selectedIdsRef = $SelectedIds
    $levelSelRef = $LevelSelections
    $countCtrl = $SelectionCount

    $border = New-Object System.Windows.Controls.Border
    $border.Background = '#171A21'
    $border.CornerRadius = 9
    $border.Padding = '12,10'
    $border.Margin = '0,0,0,7'
    $border.ToolTip = "ID: $($Tweak.id)  |  Fonte: $($Tweak.source)  |  Windows: $($Tweak.windowsVersion -join '/')"

    $headerGrid = New-Object System.Windows.Controls.Grid
    $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = 'Auto'
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = 'Auto'
    $headerGrid.ColumnDefinitions.Add($col1); $headerGrid.ColumnDefinitions.Add($col2); $headerGrid.ColumnDefinitions.Add($col3)

    if (-not $isMultilevel) {
        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.VerticalAlignment = 'Top'
        $chk.Margin = '0,2,10,0'
        $chk.IsChecked = $selectedIdsRef.Contains($tweakId)
        $chk.Add_Checked({
            try { $selectedIdsRef.Add($tweakId) | Out-Null; Update-SelectionCount -SelectedIdsRef $selectedIdsRef -LevelSelectionsRef $levelSelRef -CountControl $countCtrl }
            catch { Write-Log "Erro ao marcar $tweakId : $($_.Exception.Message)" 'ERROR' }
        }.GetNewClosure())
        $chk.Add_Unchecked({
            try { $selectedIdsRef.Remove($tweakId) | Out-Null; Update-SelectionCount -SelectedIdsRef $selectedIdsRef -LevelSelectionsRef $levelSelRef -CountControl $countCtrl }
            catch { Write-Log "Erro ao desmarcar $tweakId : $($_.Exception.Message)" 'ERROR' }
        }.GetNewClosure())
        [System.Windows.Controls.Grid]::SetColumn($chk, 0)
        $headerGrid.Children.Add($chk) | Out-Null
    }

    $stack = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $Tweak.name
    $title.FontWeight = 'SemiBold'
    $title.FontSize = 13
    $title.Foreground = '#E7E9EE'
    $title.TextWrapping = 'Wrap'
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = $Tweak.description
    $desc.Foreground = '#9AA0AC'
    $desc.FontSize = 11.5
    $desc.TextWrapping = 'Wrap'
    $desc.Margin = '0,3,0,0'
    $stack.Children.Add($title) | Out-Null
    $stack.Children.Add($desc) | Out-Null

    if ($isMultilevel) {
        $combo = New-Object System.Windows.Controls.ComboBox
        $combo.Width = 330
        $combo.HorizontalAlignment = 'Left'
        foreach ($lv in $tweakLevels) { $combo.Items.Add($lv.name) | Out-Null }
        $savedIdx = if ($levelSelRef.ContainsKey($tweakId)) { $levelSelRef[$tweakId] } else { 0 }
        if ($savedIdx -ge $combo.Items.Count) { $savedIdx = 0 }
        $combo.SelectedIndex = $savedIdx
        if (-not $levelSelRef.ContainsKey($tweakId)) { $levelSelRef[$tweakId] = 0 }

        $levelDesc = New-Object System.Windows.Controls.TextBlock
        $levelDesc.Text = $tweakLevels[$savedIdx].description
        $levelDesc.Foreground = '#FF8C42'
        $levelDesc.FontSize = 11
        $levelDesc.FontStyle = 'Italic'
        $levelDesc.TextWrapping = 'Wrap'
        $levelDesc.Margin = '0,4,0,0'

        $combo.Add_SelectionChanged({
            try {
                $levelSelRef[$tweakId] = $combo.SelectedIndex
                $levelDesc.Text = $tweakLevels[$combo.SelectedIndex].description
                Update-SelectionCount -SelectedIdsRef $selectedIdsRef -LevelSelectionsRef $levelSelRef -CountControl $countCtrl
            } catch { Write-Log "Erro ao mudar nível de $tweakId : $($_.Exception.Message)" 'ERROR' }
        }.GetNewClosure())

        $stack.Children.Add($combo) | Out-Null
        $stack.Children.Add($levelDesc) | Out-Null
    }

    $headerGrid.Children.Add($stack) | Out-Null

    $riskBadge = New-Object System.Windows.Controls.Border
    $riskBadge.Background = $riskColor
    $riskBadge.CornerRadius = 6
    $riskBadge.Padding = '7,2'
    $riskBadge.VerticalAlignment = 'Top'
    $riskText = New-Object System.Windows.Controls.TextBlock
    $riskText.Text = $Tweak.risk
    $riskText.FontSize = 10.5
    $riskText.FontWeight = 'Bold'
    $riskText.Foreground = '#0F1115'
    $riskBadge.Child = $riskText
    [System.Windows.Controls.Grid]::SetColumn($riskBadge, 2)
    $headerGrid.Children.Add($riskBadge) | Out-Null

    $border.Child = $headerGrid
    return $border
}

function Render-Tweaks {
    param([string]$Category = 'Todas', [string]$Filter = '')
    $items = $VisibleTweaks
    if ($Category -ne 'Todas') { $items = @($items | Where-Object { $_.category -eq $Category }) }
    if ($Filter) { $items = @($items | Where-Object { $_.name -match [regex]::Escape($Filter) -or $_.description -match [regex]::Escape($Filter) }) }

    $gamerRemovalIds = @('APP-038', 'APP-039', 'APP-040', 'APP-041', 'APP-042', 'APP-043')
    if ($ChkGamer.IsChecked) { $items = @($items | Where-Object { $gamerRemovalIds -notcontains $_.id }) }
    else { $items = @($items | Where-Object { $_.id -ne 'APP-044' }) }

    $CurrentRenderedIds.Clear()
    $CurrentRenderedIds.AddRange([string[]]@($items | Where-Object { $_.type -ne 'multilevel' } | Select-Object -ExpandProperty id))

    $TweakList.Items.Clear()
    foreach ($t in $items) {
        try { $TweakList.Items.Add((New-TweakCard -Tweak $t)) | Out-Null }
        catch { Write-Log "Erro ao renderizar tweak $($t.id): $($_.Exception.Message)" 'ERROR' }
    }
    Update-SelectionCount
}

Render-Tweaks

$CategoryList.Add_SelectionChanged({
    try { Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text }
    catch { Write-Log "Erro ao trocar categoria: $($_.Exception.Message)" 'ERROR' }
})
$TxtSearch.Add_TextChanged({
    try { Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text }
    catch { Write-Log "Erro na busca: $($_.Exception.Message)" 'ERROR' }
})
$ChkGamer.Add_Checked({
    try { Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text }
    catch { Write-Log "Erro ao ativar modo gamer: $($_.Exception.Message)" 'ERROR' }
})
$ChkGamer.Add_Unchecked({
    try { Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text }
    catch { Write-Log "Erro ao desativar modo gamer: $($_.Exception.Message)" 'ERROR' }
})

# ============================================================================
# 10. SELEÇÃO EM LOTE
# ============================================================================
$BtnMarcarVisiveis.Add_Click({
    Invoke-Safe -Context 'marcar visíveis' -Action {
        foreach ($id in $CurrentRenderedIds) { $SelectedIds.Add($id) | Out-Null }
        Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
    }
})
$BtnDesmarcarVisiveis.Add_Click({
    Invoke-Safe -Context 'desmarcar visíveis' -Action {
        foreach ($id in $CurrentRenderedIds) { $SelectedIds.Remove($id) | Out-Null }
        Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
    }
})
$BtnLimpar.Add_Click({
    Invoke-Safe -Context 'limpar seleção' -Action {
        $SelectedIds.Clear()
        $keys = @($LevelSelections.Keys)
        foreach ($k in $keys) { $LevelSelections[$k] = 0 }
        Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
    }
})

# ============================================================================
# 11. PRESETS
# ============================================================================
$WelcomeButtons = @{ 'Balanceado' = $BtnWelcomeBalanceado; 'Gamer' = $BtnWelcomeGamer; 'Extremo' = $BtnWelcomeExtremo }
$AccentBrush = $Window.FindResource('Accent')
$PanelAltBrush = $Window.FindResource('PanelAlt')
$TextMainBrush = $Window.FindResource('TextMain')
$DarkOnAccentBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#1A0F08')

function Get-ActiveTweakCount {
    $simple = $SelectedIds.Count
    $leveled = ($LevelSelections.GetEnumerator() | Where-Object { $_.Value -gt 0 }).Count
    return $simple + $leveled
}

function Update-WelcomePresetVisual {
    param([string]$SelectedPreset)
    foreach ($kv in $WelcomeButtons.GetEnumerator()) {
        if ($kv.Key -eq $SelectedPreset) {
            $kv.Value.Background = $AccentBrush
            $kv.Value.Foreground = $DarkOnAccentBrush
        } else {
            $kv.Value.Background = $PanelAltBrush
            $kv.Value.Foreground = $TextMainBrush
        }
    }
    $count = Get-ActiveTweakCount
    $WelcomeStatusText.Text = "✓ Preset '$SelectedPreset' selecionado — $count tweaks serão aplicados"
    $WelcomeStatusBorder.Visibility = 'Visible'
}

function Select-Preset {
    param([string]$PresetName)
    $SelectedIds.Clear()
    $keys = @($LevelSelections.Keys)
    foreach ($k in $keys) { $LevelSelections[$k] = 0 }

    foreach ($t in $AllTweaks) {
        if ($t.type -eq 'multilevel') {
            if ($t.presetLevels -and $t.presetLevels.PSObject.Properties.Name -contains $PresetName) {
                $LevelSelections[$t.id] = [int]$t.presetLevels.$PresetName
            }
        } elseif (@($t.presets) -contains $PresetName) {
            $SelectedIds.Add($t.id) | Out-Null
        }
    }
    if ($PresetName -eq 'Gamer') { $ChkGamer.IsChecked = $true }
    Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
    Update-WelcomePresetVisual -SelectedPreset $PresetName
    Write-Log "Preset '$PresetName' selecionado ($($SelectedIds.Count) tweaks + ajustes multinível)."
}

$BtnBalanceado.Add_Click({ Invoke-Safe -Context 'preset Balanceado' -Action { Select-Preset 'Balanceado' } })
$BtnGamer.Add_Click({ Invoke-Safe -Context 'preset Gamer' -Action { Select-Preset 'Gamer' } })
$BtnExtremo.Add_Click({
    Invoke-Safe -Context 'preset Extremo' -Action {
        $r = [System.Windows.MessageBox]::Show("O preset Extremo aplica a maior quantidade possível de tweaks agressivos SEM causar conflitos entre si. Itens de risco Alto continuam de fora e exigem confirmação manual. Continuar?", "Confirmação - Preset Extremo", 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Select-Preset 'Extremo' }
    }
})
$BtnWelcomeBalanceado.Add_Click({ Invoke-Safe -Context 'preset Balanceado' -Action { Select-Preset 'Balanceado' } })
$BtnWelcomeGamer.Add_Click({ Invoke-Safe -Context 'preset Gamer' -Action { Select-Preset 'Gamer' } })
$BtnWelcomeExtremo.Add_Click({
    Invoke-Safe -Context 'preset Extremo' -Action {
        $r = [System.Windows.MessageBox]::Show("O preset Extremo aplica a maior quantidade possível de tweaks agressivos SEM causar conflitos entre si. Itens de risco Alto continuam de fora e exigem confirmação manual. Continuar?", "Confirmação - Preset Extremo", 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Select-Preset 'Extremo' }
    }
})

# ============================================================================
# 12. ABA MANUTENÇÃO - ações rápidas via motor de tweaks
# ============================================================================
function Invoke-MaintenanceAction {
    param([string]$TweakId, [string]$ContextLabel, [switch]$Confirm)
    if ($Confirm) {
        $r = [System.Windows.MessageBox]::Show("Confirmar: $ContextLabel?", "Win-Slim Suite - Manutenção", 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
    }
    Invoke-Safe -Context $ContextLabel -Action {
        $tweak = $AllTweaks | Where-Object { $_.id -eq $TweakId }
        if (-not $tweak) {
            [System.Windows.MessageBox]::Show("Tweak '$TweakId' não encontrado no catálogo.`nVerifique se catalog.json/catalog-additions.json estão na pasta.", "Win-Slim Suite", 'OK', 'Warning') | Out-Null
            return
        }
        $BtnMaintRestorePoint.IsEnabled = $false; $BtnMaintCleanupTemp.IsEnabled = $false
        $BtnMaintCleanupWinSxS.IsEnabled = $false; $BtnMaintSfcDism.IsEnabled = $false
        $BtnMaintRestartExplorer.IsEnabled = $false
        Invoke-TweakEngine -Tweak $tweak | Out-Null
        $BtnMaintRestorePoint.IsEnabled = $true; $BtnMaintCleanupTemp.IsEnabled = $true
        $BtnMaintCleanupWinSxS.IsEnabled = $true; $BtnMaintSfcDism.IsEnabled = $true
        $BtnMaintRestartExplorer.IsEnabled = $true
        Save-Rollback
    }
}

$BtnMaintRestorePoint.Add_Click({ Invoke-MaintenanceAction -TweakId 'EXT-001' -ContextLabel 'criar ponto de restauração' -Confirm })
$BtnMaintCleanupTemp.Add_Click({ Invoke-MaintenanceAction -TweakId 'EXT-002' -ContextLabel 'limpar arquivos temporários' -Confirm })
$BtnMaintCleanupWinSxS.Add_Click({ Invoke-MaintenanceAction -TweakId 'EXTRA-006' -ContextLabel 'limpeza do Component Store (WinSxS)' -Confirm })
$BtnMaintSfcDism.Add_Click({ Invoke-MaintenanceAction -TweakId 'EXT-003' -ContextLabel 'verificação de integridade (SFC/DISM)' -Confirm })
$BtnMaintRestartExplorer.Add_Click({ Invoke-MaintenanceAction -TweakId 'EXT-004' -ContextLabel 'reiniciar Explorer' })
$BtnMaintRestartPC.Add_Click({
    Invoke-Safe -Context 'reiniciar sistema' -Action {
        $r = [System.Windows.MessageBox]::Show("Isto vai reiniciar o computador agora. Salve qualquer trabalho pendente antes de continuar.`n`nDeseja reiniciar agora?", "Win-Slim Suite - Reiniciar", 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Write-Log "Reinício solicitado pelo usuário." 'INFO'; Restart-Computer -Force }
    }
})

$BtnExportSelection.Add_Click({
    Invoke-Safe -Context 'exportar seleção' -Action {
        $export = [ordered]@{ simple = @($SelectedIds); levels = [ordered]@{} }
        foreach ($kv in ($LevelSelections.GetEnumerator() | Sort-Object Key)) { $export.levels[$kv.Key] = $kv.Value }
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Filter = 'Seleção Win-Slim (*.json)|*.json'
        $dlg.FileName = 'winslim-selecao.json'
        if ($dlg.ShowDialog() -eq 'OK') {
            $export | ConvertTo-Json -Depth 5 | Out-File -FilePath $dlg.FileName -Encoding UTF8
            Write-Log "Seleção exportada para $($dlg.FileName)." 'OK'
            [System.Windows.MessageBox]::Show("Seleção exportada para:`n$($dlg.FileName)", "Win-Slim Suite", 'OK', 'Information') | Out-Null
        }
    }
})
$BtnImportSelection.Add_Click({
    Invoke-Safe -Context 'importar seleção' -Action {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = 'Seleção Win-Slim (*.json)|*.json'
        if ($dlg.ShowDialog() -ne 'OK') { return }
        $data = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        $SelectedIds.Clear()
        foreach ($id in @($data.simple)) {
            if ($AllTweaks.id -contains $id) { $SelectedIds.Add($id) | Out-Null } else { Write-Log "Item importado '$id' não existe no catálogo, ignorado." 'WARN' }
        }
        $LevelSelections.Clear()
        foreach ($p in $data.levels.PSObject.Properties) {
            if ($AllTweaks.id -contains $p.Name) { $LevelSelections[$p.Name] = [int]$p.Value }
        }
        Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
        $MainTabs.SelectedIndex = 1
        Write-Log "Seleção importada de $($dlg.FileName): $($SelectedIds.Count) tweaks." 'OK'
    }
})
$BtnOpenDataFolder.Add_Click({ Invoke-Safe -Context 'abrir pasta de dados' -Action { Invoke-Item $ScriptRoot } })

# ============================================================================
# 13. APLICAR / ROLLBACK
# ============================================================================
function Get-SelectedSimpleIds { return @($SelectedIds) }
function Get-SelectedLeveledIds { return @($LevelSelections.GetEnumerator() | Where-Object { $_.Value -gt 0 } | Select-Object -ExpandProperty Key) }

function Run-Batch {
    param([switch]$Undo)
    $selectedSimple = Get-SelectedSimpleIds
    $selectedLeveled = Get-SelectedLeveledIds

    if ($selectedSimple.Count -eq 0 -and $selectedLeveled.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nenhum tweak selecionado.", "Win-Slim Suite", 'OK', 'Information') | Out-Null
        return
    }

    $ordered = Resolve-Conflicts -SelectedIds $selectedSimple

    $restorePointHandledSeparately = (-not $Undo -and $ChkRestorePoint.IsChecked)
    if ($restorePointHandledSeparately) {
        $ordered = @($ordered | Where-Object { $_ -ne 'EXT-001' })
        $rp = $AllTweaks | Where-Object { $_.id -eq 'EXT-001' }
        if ($rp) { Invoke-TweakEngine -Tweak $rp | Out-Null }
    }

    $totalItems = [Math]::Max($ordered.Count + $selectedLeveled.Count, 1)
    $i = 0
    $BtnApply.IsEnabled = $false
    $BtnUndo.IsEnabled = $false
    $BtnWelcomeApply.IsEnabled = $false
    $BtnWelcomeUndo.IsEnabled = $false
    $WelcomeCompletionText.Text = "Aplicando... aguarde."

    foreach ($id in $ordered) {
        $i++
        $pct = [double]($i / $totalItems) * 100
        $ProgBar.Value = $pct
        $WelcomeProgBar.Value = $pct
        $tweak = $AllTweaks | Where-Object { $_.id -eq $id }
        $ok = Invoke-TweakEngine -Tweak $tweak -Undo:$Undo
        if ($ok) { if ($Undo) { $AppliedState.Remove($id) } else { $AppliedState[$id] = (Get-Date -Format 'o') } }
        [System.Windows.Forms.Application]::DoEvents()
    }
    foreach ($id in $selectedLeveled) {
        $i++
        $pct = [double]($i / $totalItems) * 100
        $ProgBar.Value = $pct
        $WelcomeProgBar.Value = $pct
        $tweak = $AllTweaks | Where-Object { $_.id -eq $id }
        $lvl = $LevelSelections[$id]
        $ok = Invoke-TweakEngine -Tweak $tweak -Undo:$Undo -Level $lvl
        if ($ok -and -not $Undo) { $AppliedState[$id] = (Get-Date -Format 'o') }
        if ($ok -and $Undo) { $AppliedState.Remove($id); $LevelSelections[$id] = 0 }
        [System.Windows.Forms.Application]::DoEvents()
    }

    if (-not $Undo) { try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Process explorer.exe } catch { } }

    Save-State
    Save-Rollback
    $BtnApply.IsEnabled = $true
    $BtnUndo.IsEnabled = $true
    $BtnWelcomeApply.IsEnabled = $true
    $BtnWelcomeUndo.IsEnabled = $true
    $ProgBar.Value = 0
    $WelcomeProgBar.Value = 0
    $action = if ($Undo) { 'revertidos (rollback profissional aplicado quando havia snapshot salvo)' } else { 'aplicados' }
    $WelcomeCompletionText.Text = "✅ Concluído — $totalItems tweaks $action. Reinicie para garantir efeito completo."
    [System.Windows.MessageBox]::Show("$totalItems tweaks $action. Veja o log para detalhes. Reinicie o computador para garantir que todas as mudanças tenham efeito completo.", "Win-Slim Suite", 'OK', 'Information') | Out-Null
    Render-Tweaks -Category $CategoryList.SelectedItem -Filter $TxtSearch.Text
}

$BtnApply.Add_Click({ Invoke-Safe -Context 'aplicar selecionados' -Action { Run-Batch } })
$BtnUndo.Add_Click({ Invoke-Safe -Context 'rollback (desfazer selecionados)' -Action { Run-Batch -Undo } })
$BtnWelcomeApply.Add_Click({ Invoke-Safe -Context 'aplicar perfil (Bem-vindo)' -Action { Run-Batch } })
$BtnWelcomeUndo.Add_Click({ Invoke-Safe -Context 'rollback (Bem-vindo)' -Action { Run-Batch -Undo } })
$BtnWelcomeRestart.Add_Click({
    Invoke-Safe -Context 'reiniciar sistema' -Action {
        $r = [System.Windows.MessageBox]::Show("Isto vai reiniciar o computador agora. Salve qualquer trabalho pendente antes de continuar.`n`nDeseja reiniciar agora?", "Win-Slim Suite - Reiniciar", 'YesNo', 'Warning')
        if ($r -eq 'Yes') { Write-Log "Reinício solicitado pelo usuário." 'INFO'; Restart-Computer -Force }
    }
})

Write-Log "Win-Slim Suite v2.0 iniciado. Windows $($WinVersion) build $($WinBuild). $($VisibleTweaks.Count) tweaks carregados."

# ============================================================================
# 14. EXIBIR JANELA
# ============================================================================
try {
    $Window.ShowDialog() | Out-Null
} catch {
    Write-Log "Erro fatal na janela principal: $($_.Exception.Message)" 'ERROR'
    [System.Windows.MessageBox]::Show("Ocorreu um erro inesperado:`n$($_.Exception.Message)`n`nDetalhes no log:`n$LogPath", "Win-Slim Suite - Erro", 'OK', 'Error') | Out-Null
}
