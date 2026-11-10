#requires -Version 5.1
# Configura o PATH da sessão atual e verifica dependências do Win-Slim Suite R3.2.84.
# Executar em um NOVO shell do PowerShell (para o PATH do sistema entrar em vigor).
$ErrorActionPreference = 'Stop'

$gitBin   = 'C:\Program Files\Git\bin'
$gitCmd   = 'C:\Program Files\Git\cmd'
$pythonDir = 'C:\Program Files\Python311'
$pythonScripts = 'C:\Program Files\Python311\Scripts'

$novosCaminhos = @($gitBin, $gitCmd, $pythonDir, $pythonScripts)
$atualizado = $false
foreach ($c in $novosCaminhos) {
    if (-not $env:PATH -match [regex]::Escape($c)) {
        $env:PATH = $env:PATH + ';' + $c
        $atualizado = $true
    }
}

# Persistir no PATH de máquina para novas sessões
$maquina = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
foreach ($c in $novosCaminhos) {
    if (-not $maquina -match [regex]::Escape($c)) {
        $maquina = $maquina + ';' + $c
    }
}
[Environment]::SetEnvironmentVariable('PATH', $maquina, 'Machine')

Write-Host '==========================================================='
Write-Host '  Configuracao do ambiente - Win-Slim Suite R3.2.84'
Write-Host '==========================================================='
Write-Host ''

function Verificar-Executavel([string]$Nome, [string]$Caminho, [string[]]$Argumentos) {
    $completo = Join-Path $Caminho $Nome
    if (-not (Test-Path -LiteralPath $completo -PathType Leaf)) {
        Write-Host ("[FALTA] " + $Nome + " nao encontrado em: " + $Caminho) -ForegroundColor Red
        return $false
    }
    try {
        $saida = @(& $completo @Argumentos 2>&1)
        $primeiraLinha = if ($saida.Count -gt 0) { ($saida[0] -replace '\r','') } else { '' }
        Write-Host ("[OK]    " + $Nome + " -> " + $primeiraLinha) -ForegroundColor Green
        return $true
    } catch {
        Write-Host ("[ERRO]  " + $Nome + ": " + $_.Exception.Message) -ForegroundColor Red
        return $false
    }
}

$ok = $true
$resultado = Verificar-Executavel 'git.exe' 'C:\Program Files\Git\bin' @('--version')
$ok = $ok -and $resultado
$resultado = Verificar-Executavel 'python.exe' 'C:\Program Files\Python311' @('--version')
$ok = $ok -and $resultado
$resultado = Verificar-Executavel 'powershell.exe' 'C:\Windows\System32\WindowsPowerShell\v1.0' @('-Command', '$PSVersionTable.PSVersion')
$ok = $ok -and $resultado

Write-Host ''
Write-Host 'csc.exe (compilador C# .NET Framework):'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (Test-Path -LiteralPath $csc -PathType Leaf) {
    Write-Host ("[OK]    csc.exe encontrado em: " + $csc) -ForegroundColor Green
} else {
    Write-Host ("[FALTA] csc.exe nao encontrado em: " + $csc) -ForegroundColor Red
    $ok = $false
}

Write-Host ''
Write-Host 'Pasta é repositorio Git?'
if (Test-Path -LiteralPath (Join-Path $PWD '.git') -PathType Container) {
    Write-Host '[SIM]   Pasta contem .git (repositorio Git).' -ForegroundColor Green
} else {
    Write-Host '[NAO]   Pasta NAO contem .git (nao e um checkout Git acessível neste ambiente).' -ForegroundColor Yellow
    Write-Host '        Nao executar git init / clone / reset / clean automaticamente.'
}

Write-Host ''
Write-Host 'Arquivos de validacao locais:'
foreach ($f in @('Validar-Regressoes.bat', 'Iniciar-Validacao.bat', 'Coletar-Diagnostico.bat', 'Executar-Regressoes.ps1')) {
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        Write-Host ("[OK]    " + $f) -ForegroundColor Green
    } else {
        Write-Host ("[FALTA] " + $f) -ForegroundColor Red
        $ok = $false
    }
}

Write-Host ''
Write-Host 'PresentMon oficial (terceira parte):'
$pm = Join-Path $PWD 'third_party\PresentMon\PresentMon-2.6.0-x64.exe'
if (Test-Path -LiteralPath $pm -PathType Leaf) {
    $hash = (Get-FileHash -LiteralPath $pm -Algorithm SHA256).Hash
    Write-Host ("[OK]    PresentMon-2.6.0-x64.exe encontrado. SHA256: " + $hash) -ForegroundColor Green
    if ($hash.ToLower() -eq 'b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af') {
        Write-Host '        Hash confere com o esperado (b2a706bc...).' -ForegroundColor Green
    } else {
        Write-Host '        AVISO: hash nao confere com o esperado.' -ForegroundColor Yellow
    }
} else {
    Write-Host ("[FALTA] " + $pm) -ForegroundColor Red
    $ok = $false
}

Write-Host ''
Write-Host 'Dependencias Python para o empacotador (package_release.py):'
try {
    $saida = & 'C:\Program Files\Python311\python.exe' '--version'
    Write-Host ("[OK]    Python: " + ($saida -replace '\r','')) -ForegroundColor Green
} catch {
    Write-Host '[FALTA] Python nao e executavel.' -ForegroundColor Red
    $ok = $false
}

Write-Host ''
if ($ok) {
    Write-Host 'Todas as dependencias estao presentes.' -ForegroundColor Green
    exit 0
} else {
    Write-Host 'Existem dependencias ausentes. Revise os itens marcados [FALTA].' -ForegroundColor Red
    exit 1
}
