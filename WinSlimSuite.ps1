# Win-Slim Suite - Otimizador e Debloat para Windows 10/11
#
# Interface com aba "Bem-vindo" (presets) e aba "Avançado" (catálogo completo).
# Consolida WinUtil, Atlas-OS, Win-Debloat-Tools, MeetRevision Playbook e Win-Slim.
# SysMain e Windows Search são sempre tratados como OTIMIZAÇÃO, nunca desativados.
# Inclui rollback estruturado (snapshot do estado real antes de cada aplicação),
# verificação opcional via API gratuita do VirusTotal (arquivos baixados e,
# opcionalmente, varredura dos locais mais comuns de infecção do sistema).
#
# Execute como Administrador. Compatível com Windows 10 e Windows 11.

# Checagem de versão em runtime (em vez de #Requires, que não funciona quando o
# script roda via "irm | iex" — o parser só reconhece #Requires em arquivos .ps1
# executados diretamente do disco, não em texto avaliado por Invoke-Expression).
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "Este script requer Windows PowerShell 5.1 ou superior. Sua versão: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ============================================================================
# 0. BOOTSTRAP / ELEVAÇÃO
#    Funciona de duas formas:
#    (a) Arquivo local (.ps1 + catalog.json na mesma pasta) - modo original.
#    (b) Remoto via "irm <url>/WinSlimSuite.ps1 | iex" - detectado pela ausência
#        de $PSCommandPath (não existe arquivo físico rodando). Nesse caso o
#        catalog.json é baixado para uma pasta local persistente, e a
#        auto-elevação relança o mesmo comando irm|iex num processo admin,
#        em vez de apontar para um arquivo que não existe.
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

# ASCII-only block on purpose (no accented characters, no emoji): this runs
# BEFORE we can trust how this process decided to decode the file, so it must
# parse correctly no matter what. When running from a local .ps1 file, Windows
# PowerShell 5.1 can guess the wrong text encoding if the file has no BOM,
# which would corrupt accented characters and emoji used later in the script.
# Instead of relying on a BOM (which breaks "irm | iex" in a different way),
# we explicitly re-read our own file as UTF-8 and re-run it via Invoke-Expression
# exactly once. A process-only marker prevents this from looping forever.
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
$CatalogPath = Join-Path $ScriptRoot 'catalog.json'
$StatePath = Join-Path $ScriptRoot 'winslim-state.json'
$RollbackPath = Join-Path $ScriptRoot 'winslim-rollback.json'
$LogPath = Join-Path $ScriptRoot 'winslim-log.txt'

if ($IsRemoteRun) {
    # Sempre busca a versão mais recente do catálogo quando rodando via irm|iex
    try {
        Invoke-WebRequest -Uri "$($RepoRawBase)/catalog.json" -OutFile $CatalogPath -UseBasicParsing -TimeoutSec 20
    } catch {
        [System.Windows.MessageBox]::Show("Não foi possível baixar o catalog.json do GitHub:`n$($_.Exception.Message)`n`nVerifique sua conexão com a internet e se o repositório está público.", "Win-Slim Suite", 'OK', 'Error') | Out-Null
        exit 1
    }
}

if (-not (Test-Path $CatalogPath)) {
    [System.Windows.MessageBox]::Show("catalog.json não encontrado em:`n$CatalogPath`n`nColoque o arquivo catalog.json na mesma pasta deste script (modo local) ou verifique sua conexão com a internet (modo irm|iex).", "Win-Slim Suite", 'OK', 'Error') | Out-Null
    exit 1
}

# ============================================================================
# 1. DETECÇÃO DE SISTEMA
# ============================================================================
function Get-WinMajorVersion {
    $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    if ($build -ge 22000) { return '11' } else { return '10' }
}
$WinVersion = Get-WinMajorVersion
$WinBuild = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber

# ============================================================================
# 2. CARREGAR CATÁLOGO
# ============================================================================
$JsonRaw = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
$Catalog = $JsonRaw | ConvertFrom-Json
$AllTweaks = $Catalog.tweaks
$VisibleTweaks = $AllTweaks | Where-Object { $_.windowsVersion -contains $WinVersion }

if (Test-Path $StatePath) {
    $AppliedState = @{}
    (Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $AppliedState[$_.Name] = $_.Value }
} else { $AppliedState = @{} }
function Save-State { $AppliedState | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatePath -Encoding UTF8 }

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
    if ($LogBox) {
        try { $LogBox.Dispatcher.Invoke([Action]{ $LogBox.AppendText("$line`r`n"); $LogBox.ScrollToEnd() }) } catch { }
    }
}

# Invoke-Safe: reservado para AÇÕES DELIBERADAS (Aplicar, Desfazer, Presets, ações em
# lote). Interações leves (marcar uma checkbox, mudar de categoria, digitar na busca,
# trocar um nível) usam try/catch simples SEM caixa de mensagem — só registram no log —
# para não interromper o usuário a cada clique.
function Invoke-Safe {
    param([scriptblock]$Action, [string]$Context = 'ação')
    try { & $Action }
    catch {
        Write-Log "Erro em '$Context': $($_.Exception.Message)" 'ERROR'
        try { [System.Windows.MessageBox]::Show("Ocorreu um erro em '$Context':`n$($_.Exception.Message)`n`nDetalhes no log:`n$LogPath", "Win-Slim Suite", 'OK', 'Warning') | Out-Null } catch { }
    }
}

# ============================================================================
# 3. ESTADO DE SELEÇÃO EM MEMÓRIA
# ============================================================================
$SelectedIds = [System.Collections.Generic.HashSet[string]]::new()
$LevelSelections = @{}

# ============================================================================
# 4. VIRUSTOTAL - verificação opcional de arquivos baixados pela ferramenta
#    Usa uma API KEY GRATUITA (fornecida pelo usuário do projeto). APIs gratuitas
#    do VirusTotal têm limite de uso (requisições por minuto/dia) e podem falhar
#    ou ficar indisponíveis ocasionalmente — nesse caso o usuário decide se quer
#    prosseguir mesmo sem a verificação.
# ============================================================================
$VTApiKey = '50da278e8c9c0a37968b73e85357eb542464ad3339db8ffb649f1a7632196f31'

function Test-InternetAvailable {
    # Checagem rápida e barata de conectividade, para não travar o script quando
    # o usuário está offline. Timeout curto de propósito.
    try {
        $req = [System.Net.WebRequest]::Create('https://www.virustotal.com')
        $req.Timeout = 4000
        $req.Method = 'HEAD'
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch { return $false }
}

function Test-FileVirusTotal {
    param([string]$FilePath)
    try {
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
        $headers = @{ 'x-apikey' = $VTApiKey }
        $uri = "https://www.virustotal.com/api/v3/files/$hash"
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 10
        $stats = $resp.data.attributes.last_analysis_stats
        return @{ Success = $true; Malicious = [int]$stats.malicious; Suspicious = [int]$stats.suspicious
                  Total = [int]($stats.malicious + $stats.suspicious + $stats.harmless + $stats.undetected); Hash = $hash }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message; Hash = $null }
    }
}

function Confirm-DownloadIsSafe {
    # Retorna $true se está seguro para prosseguir (limpo, verificação desativada
    # pelo usuário, ou sem internet/API indisponível -> segue automaticamente
    # sem interromper o processo). Retorna $false SOMENTE quando o VirusTotal
    # respondeu e encontrou alerta real.
    param([string]$FilePath, [string]$FriendlyName)

    if ($ChkVirusTotal -and -not $ChkVirusTotal.IsChecked) {
        Write-Log "Verificação do VirusTotal para '$FriendlyName' desativada pelo usuário (checkbox desmarcada) — prosseguindo sem verificar." 'INFO'
        return $true
    }

    if (-not (Test-InternetAvailable)) {
        Write-Log "Sem conexão com a internet — verificação do VirusTotal para '$FriendlyName' foi pulada automaticamente (API gratuita, sem interromper o processo)." 'WARN'
        return $true
    }

    Write-Log "Verificando '$FriendlyName' no VirusTotal (API gratuita)..." 'INFO'
    $result = Test-FileVirusTotal -FilePath $FilePath
    if (-not $result.Success) {
        Write-Log "VirusTotal indisponível para '$FriendlyName' ($($result.Error)) — pulando verificação automaticamente, sem interromper o processo. Isto usa uma API KEY GRATUITA, que tem limite de uso e pode falhar às vezes." 'WARN'
        return $true
    }
    if ($result.Malicious -gt 0 -or $result.Suspicious -gt 0) {
        Write-Log "VirusTotal ALERTA para '$FriendlyName': $($result.Malicious) malicioso(s), $($result.Suspicious) suspeito(s) de $($result.Total) motores (hash $($result.Hash))." 'ERROR'
        [System.Windows.MessageBox]::Show(
            "⚠ O VirusTotal encontrou alertas para '$FriendlyName':`n`n$($result.Malicious) motor(es): MALICIOSO`n$($result.Suspicious) motor(es): suspeito`n(de $($result.Total) motores no total)`n`nPor segurança, esta etapa será CANCELADA.",
            "Win-Slim Suite - Alerta de Segurança", 'OK', 'Error') | Out-Null
        return $false
    }
    Write-Log "VirusTotal: '$FriendlyName' limpo (0 detecções de $($result.Total) motores)." 'OK'
    return $true
}

# ---------------------------------------------------------------------------
# Verificação de Segurança do Sistema (VirusTotal) - varredura da unidade
#
# Varre de fato as pastas da unidade do sistema onde um usuário ou programa
# de terceiros pode gravar arquivos: Users (todos os perfis), ProgramData,
# Program Files e Program Files (x86). A pasta Windows (sistema operacional
# em si) fica de fora de propósito: são dezenas de milhares de arquivos
# assinados digitalmente pela própria Microsoft, praticamente nunca a origem
# de malware de terceiros, e verificá-los aumentaria o tempo de varredura em
# horas sem ganho real de segurança.
#
# LIMITAÇÃO REAL (não contornável): a API gratuita do VirusTotal só permite
# poucas consultas por minuto. Por isso a varredura prioriza os arquivos mais
# suspeitos (em pastas temporárias/Downloads, ou modificados recentemente) e
# verifica um número limitado deles no VirusTotal, em vez de checar todos os
# milhares de arquivos encontrados um por um.
# ---------------------------------------------------------------------------
function Get-SystemScanCandidates {
    param([int]$MaxToCheck = 150)

    $extensions = @('.exe', '.dll', '.scr', '.bat', '.cmd', '.ps1', '.vbs', '.js')
    $scanRoots = @(
        "$env:SystemDrive\Users",
        "$env:SystemDrive\ProgramData",
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

    Write-Log "Varrendo a unidade do sistema: $($scanRoots -join '; ')" 'INFO'

    $allFiles = New-Object System.Collections.Generic.List[object]
    foreach ($root in $scanRoots) {
        Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $extensions -contains $_.Extension.ToLower() } |
            ForEach-Object { $allFiles.Add($_) }
    }
    Write-Log "Varredura da unidade concluída: $($allFiles.Count) arquivo(s) executável(is) encontrados. Priorizando os mais suspeitos para checagem no VirusTotal." 'INFO'

    # Chaves Run (programas configurados para iniciar com o Windows)
    $runKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')
    $runTargets = New-Object System.Collections.Generic.List[string]
    foreach ($k in $runKeys) {
        if (Test-Path $k) {
            $props = (Get-Item $k -ErrorAction SilentlyContinue).Property
            foreach ($p in $props) {
                $val = (Get-ItemProperty -Path $k -Name $p -ErrorAction SilentlyContinue).$p
                if ($val -match '([A-Za-z]:\\[^"]+?\.exe)') { $runTargets.Add($Matches[1]) }
            }
        }
    }

    # Prioriza: itens de Run (mais suspeitos por natureza) primeiro, depois
    # arquivos em pastas de risco (Temp/Downloads/ProgramData), depois os
    # modificados mais recentemente.
    $scored = $allFiles | ForEach-Object {
        $score = 0
        if ($_.FullName -match '\\(Temp|Downloads|ProgramData)\\') { $score += 3 }
        if ($_.LastWriteTime -gt (Get-Date).AddDays(-7)) { $score += 3 }
        elseif ($_.LastWriteTime -gt (Get-Date).AddDays(-30)) { $score += 1 }
        [PSCustomObject]@{ FullName = $_.FullName; Score = $score; LastWriteTime = $_.LastWriteTime }
    }
    $prioritized = $scored | Sort-Object Score, LastWriteTime -Descending | Select-Object -ExpandProperty FullName

    $combined = @($runTargets) + @($prioritized)
    return $combined | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -Unique -First $MaxToCheck
}

function Wait-WithoutFreezingUI {
    # Espera o número de segundos indicado SEM travar a janela — chama
    # DoEvents em pequenos intervalos para a interface continuar respondendo
    # (mover a janela, ver o log atualizando) durante a espera exigida pelo
    # limite de requisições da API gratuita do VirusTotal.
    param([int]$Seconds)
    $elapsedMs = 0
    $stepMs = 200
    while ($elapsedMs -lt ($Seconds * 1000)) {
        Start-Sleep -Milliseconds $stepMs
        [System.Windows.Forms.Application]::DoEvents()
        $elapsedMs += $stepMs
    }
}

function Invoke-SystemSecurityScan {
    # Roda a varredura da unidade do sistema, respeitando o limite da API
    # gratuita do VirusTotal (~4 consultas/min -> ~15s de intervalo, sem
    # travar a interface). Reporta progresso via Write-Log e via $ProgBar /
    # $WelcomeProgBar quando disponíveis. Retorna a lista de alertas encontrados.
    param([switch]$Silent)

    if (-not (Test-InternetAvailable)) {
        Write-Log "Sem internet — verificação de segurança do sistema cancelada." 'WARN'
        if (-not $Silent) { [System.Windows.MessageBox]::Show("Sem conexão com a internet. Tente novamente quando estiver online.", "Win-Slim Suite", 'OK', 'Warning') | Out-Null }
        return @()
    }

    $files = Get-SystemScanCandidates -MaxToCheck 150
    $total = $files.Count
    if ($total -eq 0) {
        Write-Log "Verificação de segurança do sistema: nenhum arquivo candidato encontrado." 'INFO'
        if (-not $Silent) { [System.Windows.MessageBox]::Show("Nenhum arquivo executável encontrado nas pastas verificadas.", "Win-Slim Suite", 'OK', 'Information') | Out-Null }
        return @()
    }

    $estimatedMin = [Math]::Ceiling(($total * 15) / 60)
    if (-not $Silent) {
        $r = [System.Windows.MessageBox]::Show(
            "Isto vai varrer a unidade do sistema (Users, ProgramData, Program Files) e verificar os $total arquivo(s) mais suspeitos no VirusTotal.`n`n" +
            "A pasta Windows não é verificada (arquivos assinados pela Microsoft, praticamente nunca a origem de malware).`n`n" +
            "A API gratuita é lenta de propósito — tempo estimado: ~$estimatedMin minuto(s). A interface continua responsiva durante a espera.`n`n" +
            "Deseja continuar?", "Win-Slim Suite - Verificação de Segurança", 'YesNo', 'Information')
        if ($r -ne 'Yes') { Write-Log "Verificação de segurança do sistema cancelada pelo usuário." 'INFO'; return @() }
    }

    Write-Log "Iniciando verificação de segurança da unidade: $total arquivo(s) candidatos (tempo estimado ~$estimatedMin min)." 'INFO'
    $alerts = New-Object System.Collections.Generic.List[object]
    $i = 0
    foreach ($f in $files) {
        $i++
        Write-Log "[VT-SCAN] ($i/$total) Verificando: $f" 'INFO'
        if ($ProgBar) { $ProgBar.Value = [double]($i / $total) * 100 }
        if ($WelcomeProgBar) { $WelcomeProgBar.Value = [double]($i / $total) * 100 }
        [System.Windows.Forms.Application]::DoEvents()

        $result = Test-FileVirusTotal -FilePath $f
        if ($result.Success -and ($result.Malicious -gt 0 -or $result.Suspicious -gt 0)) {
            Write-Log "[VT-SCAN] ALERTA em '$f': $($result.Malicious) malicioso(s), $($result.Suspicious) suspeito(s)." 'ERROR'
            $alerts.Add([PSCustomObject]@{ Path = $f; Malicious = $result.Malicious; Suspicious = $result.Suspicious })
        } elseif (-not $result.Success) {
            Write-Log "[VT-SCAN] Não foi possível verificar '$f' ($($result.Error))." 'WARN'
        }
        if ($i -lt $total) { Wait-WithoutFreezingUI -Seconds 15 }
    }
    if ($ProgBar) { $ProgBar.Value = 0 }
    if ($WelcomeProgBar) { $WelcomeProgBar.Value = 0 }

    if ($alerts.Count -gt 0) {
        $list = ($alerts | ForEach-Object { "• $($_.Path) — $($_.Malicious) malicioso(s), $($_.Suspicious) suspeito(s)" }) -join "`n"
        Write-Log "Verificação de segurança do sistema concluída: $($alerts.Count) arquivo(s) com alerta." 'ERROR'
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show("⚠ Encontrados $($alerts.Count) arquivo(s) com alerta no VirusTotal:`n`n$list`n`nRecomendado: investigar e remover manualmente esses arquivos.", "Win-Slim Suite - Alerta de Segurança", 'OK', 'Error') | Out-Null
        }
    } else {
        Write-Log "Verificação de segurança do sistema concluída: nenhum alerta encontrado em $total arquivo(s)." 'OK'
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show("✅ Verificação concluída. Nenhum alerta encontrado em $total arquivo(s) verificados na unidade.", "Win-Slim Suite", 'OK', 'Information') | Out-Null
        }
    }
    return $alerts
}

# ============================================================================
# 5. ROLLBACK PROFISSIONAL - captura o estado REAL antes de cada alteração
#    (não depende de valores 'padrão' assumidos pelo catálogo) e restaura
#    exatamente esse estado quando o usuário clica em Desfazer.
# ============================================================================
if (Test-Path $RollbackPath) {
    $RollbackData = @{}
    try {
        (Get-Content $RollbackPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $RollbackData[$_.Name] = $_.Value }
    } catch { $RollbackData = @{} }
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
    # Captura o estado real (registro/serviço) imediatamente antes de aplicar um
    # payload, e guarda em $RollbackData[$TweakId], sobrescrevendo qualquer
    # snapshot anterior daquele tweak (sempre reflete o estado anterior à ÚLTIMA aplicação).
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
    # Rollback profissional: restaura o estado EXATO capturado antes da última
    # aplicação. Retorna $true se havia snapshot e foi restaurado; $false se não
    # havia snapshot (aí o chamador cai para o fallback do catálogo).
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
# 6. MOTOR DE APLICAÇÃO / DESFAZIMENTO
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
        $conflict = $tweak.conflicts | Where-Object { $final -contains $_ }
        if ($conflict) { $skipped += "$id (conflita com $($conflict -join ', '))"; continue }
        $final.Add($id)
    }
    if ($skipped) { Write-Log "Itens ignorados por conflito: $($skipped -join '; ')" 'WARN' }
    return $final
}

# ============================================================================
# 7. XAML DA INTERFACE
# ============================================================================
[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Win-Slim Suite" Height="860" Width="1360" WindowStartupLocation="CenterScreen"
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
                            <!-- corpo da pena (vane), preenchido com degradê laranja -->
                            <Path Data="M14,56 C10,46 12,34 20,24 C26,17 34,12 50,8 C40,14 26,24 20,34 C14,42 12,50 14,56 Z"
                                  Fill="{StaticResource OrangeGradient}" Stroke="#8C4A14" StrokeThickness="1.1" StrokeLineJoin="Round"/>
                            <!-- brilho sutil na borda superior -->
                            <Path Data="M20,24 C26,17 34,12 50,8" Stroke="#FFEEDC" StrokeThickness="0.8" StrokeStartLineCap="Round" Opacity="0.55"/>
                            <!-- haste central (rachis) -->
                            <Path Data="M14,56 C16,46 20,34 26,26 C32,20 40,14 50,8"
                                  Stroke="#FFF1DE" StrokeThickness="1.3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0.9"/>
                            <!-- barbas -->
                            <Path Data="M16,52 L13.6,50.2 M16,52 L18.4,53.6 M18,47 L14,44 M18,47 L22,49.5 M20,42 L14.4,37.8 M20,42 L25.4,45.6 M22,37 L15.6,32.2 M22,37 L28.2,41.2 M25,32 L17.8,26.6 M25,32 L32,36.8 M29,27 L22.6,22.2 M29,27 L35.2,31.2 M33,22 L28.2,18.4 M33,22 L37.6,25 M38,18 L34.8,15.6 M38,18 L41,20 M44,13 L42.4,11.8 M44,13 L45.4,14"
                                  Stroke="#8C4A14" StrokeThickness="0.9" StrokeStartLineCap="Round" Opacity="0.8"/>
                            <!-- ponta da pluma (quill) -->
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
                                    na aba Avançado quando quiser.
                                </TextBlock>

                                <!-- Sou Gamer: discreto, sem destaque exagerado -->
                                <StackPanel Margin="0,0,0,16">
                                    <CheckBox x:Name="ChkGamer" Content="🎮 Sou Gamer" FontSize="13.5" FontWeight="SemiBold"/>
                                    <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="22,4,0,0">
                                        Marque se joga no PC. Isto mantém os apps do Xbox instalados (só desativa a gravação
                                        em segundo plano). Se desmarcado, os apps do Xbox são removidos por completo.
                                    </TextBlock>
                                </StackPanel>

                                <!-- Verificação VirusTotal: mesma lógica visual do Sou Gamer -->
                                <StackPanel Margin="0,0,0,22">
                                    <CheckBox x:Name="ChkVirusTotal" Content="🛡 Verificar arquivos baixados com VirusTotal" FontSize="13.5" FontWeight="SemiBold" IsChecked="True"/>
                                    <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="22,4,0,0">
                                        Checa arquivos baixados por esta ferramenta antes de rodar. Usa uma API gratuita
                                        (pode falhar às vezes, sem travar o processo).
                                    </TextBlock>
                                </StackPanel>

                                <Button x:Name="BtnWelcomeBalanceado" Content="⚖  Balanceado" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    Otimizações seguras de baixo risco, com impacto real: privacidade, debloat básico,
                                    limpeza de interface e ajustes de responsividade (menus, apps travados, apps em
                                    segundo plano). Bom ponto de partida para qualquer PC, incluindo notebooks.
                                </TextBlock>

                                <Button x:Name="BtnWelcomeGamer" Content="🎮  Gamer" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    Tudo do Balanceado, mais: plano de energia Alto Desempenho, prioridade de CPU para o
                                    jogo em foco, ajustes de rede/latência e redução de prioridade de processos em
                                    segundo plano — feito para responsividade e fluidez em jogos.
                                </TextBlock>

                                <Button x:Name="BtnWelcomeExtremo" Content="🔥  Extremo" Style="{StaticResource WelcomeBtn}"/>
                                <TextBlock Foreground="{StaticResource TextDim}" FontSize="12" TextWrapping="Wrap" Margin="4,0,0,18">
                                    O máximo de agressividade sem gerar conflitos entre tweaks: remove componentes de
                                    IA/Copilot, ativa o plano Ultimate Performance e aplica ajustes avançados de sistema
                                    e rede. Itens de risco Alto continuam de fora e exigem confirmação manual.
                                </TextBlock>

                                <!-- Feedback visual do preset selecionado -->
                                <Border x:Name="WelcomeStatusBorder" Background="{StaticResource PanelAlt}" CornerRadius="10" Padding="14" Margin="0,4,0,10" Visibility="Collapsed">
                                    <TextBlock x:Name="WelcomeStatusText" Foreground="{StaticResource TextMain}" FontSize="12.5" FontWeight="SemiBold" TextWrapping="Wrap"/>
                                </Border>

                                <Border Background="{StaticResource PanelAlt}" CornerRadius="10" Padding="14" Margin="0,0,0,0">
                                    <TextBlock Foreground="{StaticResource TextDim}" FontSize="11.5" TextWrapping="Wrap">
                                        💡 Depois de escolher um preset, você pode aplicar direto pelo botão abaixo, ou
                                        conferir e ajustar tudo na aba
                                        <Run Foreground="{StaticResource Accent}" FontWeight="Bold">Avançado</Run>.
                                    </TextBlock>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </Border>

                    <!-- RODAPÉ: progresso + aplicar + reiniciar -->
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
                                <Button x:Name="BtnWelcomeUndo" Content="↺ Rollback" Style="{StaticResource PresetBtn}" ToolTip="Restaura o estado real capturado antes da última aplicação (rollback estruturado)."/>
                                <Button x:Name="BtnWelcomeRestart" Content="⟳ Reiniciar Sistema" Style="{StaticResource PresetBtn}" ToolTip="Reinicia o computador agora, para garantir que todas as mudanças tenham efeito completo."/>
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
                                <Button x:Name="BtnUndo" Content="↺ Rollback (Desfazer)" Style="{StaticResource PresetBtn}" ToolTip="Restaura o estado real capturado antes da última aplicação de cada item marcado (rollback estruturado, não apenas valores padrão)."/>
                            </StackPanel>
                        </Grid>
                    </Border>
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
$ChkVirusTotal = $Window.FindName('ChkVirusTotal')
$WelcomeStatusBorder = $Window.FindName('WelcomeStatusBorder')
$WelcomeStatusText = $Window.FindName('WelcomeStatusText')
$WelcomeProgBar = $Window.FindName('WelcomeProgBar')
$WelcomeCompletionText = $Window.FindName('WelcomeCompletionText')
$BtnWelcomeApply = $Window.FindName('BtnWelcomeApply')
$BtnWelcomeUndo = $Window.FindName('BtnWelcomeUndo')
$BtnWelcomeRestart = $Window.FindName('BtnWelcomeRestart')

$controlMap = @{
    OsBadge=$OsBadge; ChkGamer=$ChkGamer; ChkRestorePoint=$ChkRestorePoint; MainTabs=$MainTabs
    CategoryList=$CategoryList; TweakList=$TweakList; TxtSearch=$TxtSearch; SelectionCount=$SelectionCount
    LogBox=$LogBox; ProgBar=$ProgBar; BtnApply=$BtnApply; BtnUndo=$BtnUndo
    BtnBalanceado=$BtnBalanceado; BtnGamer=$BtnGamer; BtnExtremo=$BtnExtremo; BtnLimpar=$BtnLimpar
    BtnMarcarVisiveis=$BtnMarcarVisiveis; BtnDesmarcarVisiveis=$BtnDesmarcarVisiveis
    BtnWelcomeBalanceado=$BtnWelcomeBalanceado; BtnWelcomeGamer=$BtnWelcomeGamer; BtnWelcomeExtremo=$BtnWelcomeExtremo
    ChkVirusTotal=$ChkVirusTotal; WelcomeStatusBorder=$WelcomeStatusBorder; WelcomeStatusText=$WelcomeStatusText
    WelcomeProgBar=$WelcomeProgBar; WelcomeCompletionText=$WelcomeCompletionText
    BtnWelcomeApply=$BtnWelcomeApply; BtnWelcomeUndo=$BtnWelcomeUndo; BtnWelcomeRestart=$BtnWelcomeRestart
}
$missing = $controlMap.GetEnumerator() | Where-Object { -not $_.Value } | Select-Object -ExpandProperty Key
if ($missing) {
    [System.Windows.MessageBox]::Show("Elementos de interface não encontrados: $($missing -join ', ')`n`nO arquivo pode estar corrompido. Baixe novamente.", "Win-Slim Suite - Erro", 'OK', 'Error') | Out-Null
    exit 1
}

$OsBadge.Text = "Windows $($WinVersion)  •  Build $($WinBuild)  •  $($VisibleTweaks.Count) tweaks disponíveis"

# ============================================================================
# 8. POPULAR CATEGORIAS
# ============================================================================
$Categories = @('Todas') + ($VisibleTweaks | Select-Object -ExpandProperty category -Unique | Sort-Object)
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

    # Referências capturadas localmente e passadas via GetNewClosure(): garante
    # que cada evento (marcar checkbox, mudar nível) sempre tem uma referência
    # válida às coleções compartilhadas, independente de como o script foi
    # executado (arquivo local ou "irm | iex").
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
    if ($Category -ne 'Todas') { $items = $items | Where-Object { $_.category -eq $Category } }
    if ($Filter) { $items = $items | Where-Object { $_.name -match [regex]::Escape($Filter) -or $_.description -match [regex]::Escape($Filter) } }

    $gamerRemovalIds = @('APP-038', 'APP-039', 'APP-040', 'APP-041', 'APP-042', 'APP-043')
    if ($ChkGamer.IsChecked) { $items = $items | Where-Object { $gamerRemovalIds -notcontains $_.id } }
    else { $items = $items | Where-Object { $_.id -ne 'APP-044' } }

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
# 9. SELECIONAR / DESSELECIONAR VISÍVEIS + LIMPAR (ações deliberadas -> Invoke-Safe)
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
# 10. PRESETS (sem navegação automática de aba)
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
        } elseif ($t.presets -contains $PresetName) {
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
# 11. APLICAR / ROLLBACK
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

    if (-not $Undo -and $ChkRestorePoint.IsChecked) {
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
        if ($Undo) { $LevelSelections[$id] = 0 }
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

Write-Log "Win-Slim Suite iniciado. Windows $($WinVersion) build $($WinBuild). $($VisibleTweaks.Count) tweaks carregados."

# ============================================================================
# 12. EXIBIR JANELA
# ============================================================================
try {
    $Window.ShowDialog() | Out-Null
} catch {
    Write-Log "Erro fatal na janela principal: $($_.Exception.Message)" 'ERROR'
    [System.Windows.MessageBox]::Show("Ocorreu um erro inesperado:`n$($_.Exception.Message)`n`nDetalhes no log:`n$LogPath", "Win-Slim Suite - Erro", 'OK', 'Error') | Out-Null
}
