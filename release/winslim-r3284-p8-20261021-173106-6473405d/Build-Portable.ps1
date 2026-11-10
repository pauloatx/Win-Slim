#Requires -Version 5.1
<#
.SYNOPSIS
    Gera o WinSlimSuite.exe portable: embute o catalog.json atual dentro do
    WinSlimSuite.ps1 e compila com PS2EXE em um único executável.

.DESCRIPTION
    Rode isto sempre que editar catalog.json e quiser gerar uma versão .exe
    atualizada. O WinSlimSuite.ps1 original NÃO é modificado no disco -
    trabalhamos em uma cópia temporária.

.EXAMPLE
    .\Build-Portable.ps1
    Gera .\WinSlimSuite.exe ao lado deste script.

.EXAMPLE
    .\Build-Portable.ps1 -IconPath .\icon.ico -Version 1.3.0.0
#>
param(
    [string]$SourcePs1    = (Join-Path $PSScriptRoot 'WinSlimSuite.ps1'),
    [string]$CatalogJson  = (Join-Path $PSScriptRoot 'catalog.json'),
    [string]$OutputExe    = (Join-Path $PSScriptRoot 'WinSlimSuite.exe'),
    [string]$IconPath     = '',
    [string]$Version      = '1.3.0.0'
)

$ErrorActionPreference = 'Stop'

function Write-Step { param($Msg) Write-Host "==> $Msg" -ForegroundColor Cyan }

if (-not (Test-Path $SourcePs1))   { throw "Não encontrei $SourcePs1" }
if (-not (Test-Path $CatalogJson)) { throw "Não encontrei $CatalogJson" }

# ---------------------------------------------------------------------------
# 1) Garante o módulo ps2exe (github.com/MScholtes/PS2EXE)
# ---------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Step "Módulo ps2exe não encontrado - instalando para o usuário atual..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe -ErrorAction Stop

# ---------------------------------------------------------------------------
# 2) Embute o catalog.json atual (Base64) numa CÓPIA temporária do .ps1
#    Isto é o que faz o .exe final não precisar de nenhum arquivo solto ao
#    lado - o catalog.json vira parte do binário e é extraído sozinho na
#    primeira execução (ver seção "1b. CATÁLOGO EMBUTIDO" no WinSlimSuite.ps1).
# ---------------------------------------------------------------------------
Write-Step "Lendo catalog.json e codificando em Base64..."
$catalogBytes = [System.IO.File]::ReadAllBytes($CatalogJson)
$catalogB64   = [System.Convert]::ToBase64String($catalogBytes)
Write-Host "    catalog.json: $([Math]::Round($catalogBytes.Length/1KB,1)) KB -> $([Math]::Round($catalogB64.Length/1KB,1)) KB em Base64"

$source  = [System.IO.File]::ReadAllText($SourcePs1, [System.Text.Encoding]::UTF8)
$pattern = '(?s)# EMBEDDED_CATALOG_B64_START.*?# EMBEDDED_CATALOG_B64_END'
if ($source -notmatch $pattern) {
    throw "Marcadores EMBEDDED_CATALOG_B64_START/END não encontrados em $SourcePs1.`nO WinSlimSuite.ps1 usado é de uma versão antiga sem suporte a build portable?"
}
$replacement = "# EMBEDDED_CATALOG_B64_START`n`$script:EmbeddedCatalogB64 = @'`n$catalogB64`n'@`n# EMBEDDED_CATALOG_B64_END"
$patched = [regex]::Replace($source, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement })

$tempPs1 = Join-Path $env:TEMP "WinSlimSuite.portable.$([guid]::NewGuid().ToString('N')).ps1"
# BOM UTF-8 obrigatório: é a mesma correção de acentuação que o WinSlimSuite.ps1
# já documenta no topo do arquivo original, necessária para o PowerShell 5.1
# interpretar corretamente os caracteres acentuados ao ler o arquivo fonte.
[System.IO.File]::WriteAllText($tempPs1, $patched, (New-Object System.Text.UTF8Encoding($true)))
Write-Step "Cópia temporária com catálogo embutido: $tempPs1"

# ---------------------------------------------------------------------------
# 3) Compila com PS2EXE
#    -requireAdmin  : Windows exige elevação via manifesto ANTES da 1a linha
#                      rodar (mais robusto que a auto-elevação manual, que
#                      continua no script só como rede de segurança).
#    -STA           : obrigatório para WPF.
#    -noConsole     : sem janela de console atrás da GUI.
# ---------------------------------------------------------------------------
Write-Step "Compilando com PS2EXE (pode levar 1-2 minutos)..."
$ps2exeParams = @{
    inputFile    = $tempPs1
    outputFile   = $OutputExe
    noConsole    = $true
    STA          = $true
    requireAdmin = $true
    x64          = $true
    title        = 'Win-Slim Suite'
    product      = 'Win-Slim Suite'
    description  = 'Otimizador e Debloat para Windows 10/11 - 100% reversivel'
    company      = 'Win-Slim'
    version      = $Version
    copyright    = 'Win-Slim Suite'
}
if ($IconPath -and (Test-Path $IconPath)) {
    $ps2exeParams['iconFile'] = $IconPath
} else {
    Write-Host "    (sem -IconPath: o .exe sai com o ícone padrão do PS2EXE)" -ForegroundColor DarkYellow
}

try {
    Invoke-ps2exe @ps2exeParams
} finally {
    Remove-Item -Path $tempPs1 -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 4) Confirma e mostra o hash (pra já alimentar o SHA256SUMS.txt da release)
# ---------------------------------------------------------------------------
if (Test-Path $OutputExe) {
    Write-Step "OK: $OutputExe gerado."
    $hash = Get-FileHash -Path $OutputExe -Algorithm SHA256
    Write-Host "    SHA256: $($hash.Hash)"
    Write-Host ""
    Write-Host "Teste rodando: .\$(Split-Path -Leaf $OutputExe)" -ForegroundColor Green
} else {
    Write-Host "FALHA: o executável não foi gerado. Veja os erros do ps2exe acima." -ForegroundColor Red
    exit 1
}
