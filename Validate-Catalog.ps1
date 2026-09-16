<#
.SYNOPSIS
    Valida catalog.json contra as regras de integridade do Win-Slim Suite.

.DESCRIPTION
    Esse script existe porque bugs de dados no catalog.json não dão erro de
    sintaxe: o JSON continua "válido" e o app continua abrindo, mas os tweaks
    se comportam errado silenciosamente (cor de risco trocada, rollback que
    desfaz o tweak errado, dois tweaks brigando pela mesma chave de registro).
    Cada checagem abaixo existe por causa de um bug real já encontrado no
    catálogo (ver CHANGELOG.md v1.3).

.EXAMPLE
    pwsh ./scripts/Validate-Catalog.ps1
    pwsh ./scripts/Validate-Catalog.ps1 -Path ./catalog.json -Strict
#>
param(
    [string]$Path = (Join-Path $PSScriptRoot '../catalog.json'),
    [switch]$Strict   # -Strict: avisos (warnings) também retornam exit code != 0
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Err { param($msg) $errors.Add($msg) }
function Add-Warn { param($msg) $warnings.Add($msg) }

if (-not (Test-Path $Path)) { Write-Host "❌ Arquivo não encontrado: $Path" -ForegroundColor Red; exit 1 }

try {
    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $cat = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    Write-Host "❌ catalog.json não é um JSON válido: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$tweaks = @($cat.tweaks)
$byId = @{}
$validRisks = @('Baixo', 'Médio', 'Alto')
$validPresets = @($cat.presets)

Write-Host "Validando $($tweaks.Count) tweaks (schemaVersion $($cat.schemaVersion))..." -ForegroundColor Cyan

# 1) IDs únicos --------------------------------------------------------------
$idGroups = $tweaks | Group-Object -Property id
foreach ($g in $idGroups) {
    if ($g.Count -gt 1) { Add-Err "ID duplicado: '$($g.Name)' aparece $($g.Count) vezes." }
    $byId[$g.Name] = $g.Group[0]
}

# 2) Campos obrigatórios + risco/presets válidos -----------------------------
foreach ($t in $tweaks) {
    foreach ($field in @('id','name','category','risk','type','windowsVersion')) {
        if (-not $t.PSObject.Properties.Name -contains $field -or [string]::IsNullOrWhiteSpace([string]$t.$field)) {
            Add-Err "$($t.id): campo obrigatório '$field' ausente ou vazio."
        }
    }
    if ($t.risk -and ($validRisks -notcontains $t.risk)) {
        Add-Err "$($t.id): risk='$($t.risk)' inválido (esperado um de: $($validRisks -join ', ')). Provável problema de acentuação."
    }
    foreach ($p in @($t.presets)) {
        if ($validPresets -notcontains $p) { Add-Err "$($t.id): preset '$p' não existe em cat.presets ($($validPresets -join ', '))." }
    }
}

# 3) Cada tweak precisa ser reversível ----------------------------------------
#    - type 'registry': cada operação precisa ter OriginalValue
#    - type 'service'  : cada operação precisa ter OriginalType
#    - type 'script'   : precisa ter UndoScript não vazio
#    - type 'composite'/'multilevel'/'appx': mínimo, precisa ter alguma forma de reversão documentada
foreach ($t in $tweaks) {
    switch ($t.type) {
        'registry' {
            foreach ($op in @($t.registry)) {
                if (-not $op.PSObject.Properties.Name -contains 'OriginalValue') {
                    Add-Err "$($t.id): operação de registry em '$($op.Path)\$($op.Name)' sem 'OriginalValue' -> não é reversível."
                }
            }
        }
        'service' {
            foreach ($op in @($t.service)) {
                if (-not $op.PSObject.Properties.Name -contains 'OriginalType') {
                    Add-Err "$($t.id): operação de service '$($op.Name)' sem 'OriginalType' -> não é reversível."
                }
            }
        }
        'script' {
            if (-not $t.UndoScript -or @($t.UndoScript).Count -eq 0) {
                Add-Warn "$($t.id): type=script sem UndoScript. Se for realmente irreversível, documente isso na description."
            }
        }
    }
}

# 4) InvokeScript/UndoScript precisam ser PowerShell válido -------------------
#    Usa o parser real do PowerShell (sem executar nada) para pegar erro de
#    sintaxe antes de chegar na máquina do usuário.
foreach ($t in $tweaks) {
    foreach ($prop in @('InvokeScript','UndoScript')) {
        $lines = @($t.$prop)
        if ($lines.Count -eq 0) { continue }
        $joined = $lines -join "`n"
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($joined, [ref]$null, [ref]$parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            foreach ($pe in $parseErrors) {
                Add-Err "$($t.id).${prop}: erro de sintaxe PowerShell - $($pe.Message) (linha $($pe.Extent.StartLineNumber))"
            }
        }
    }
}

# 5) Conflitos: referência existe e é simétrica -------------------------------
foreach ($t in $tweaks) {
    foreach ($c in @($t.conflicts)) {
        if (-not $byId.ContainsKey($c)) {
            Add-Err "$($t.id): conflicts referencia ID inexistente '$c'."
            continue
        }
        $other = $byId[$c]
        if (@($other.conflicts) -notcontains $t.id) {
            Add-Err "$($t.id) -> ${c}: conflito assimétrico ($c não lista '$($t.id)' de volta em conflicts). Resolve-Conflicts depende da ordem de seleção e pode falhar nesse caso."
        }
    }
    foreach ($d in @($t.dependencies)) {
        if (-not $byId.ContainsKey($d)) { Add-Err "$($t.id): dependencies referencia ID inexistente '$d'." }
    }
}

# 6) Duplicatas de AÇÃO (mesmo efeito sob IDs diferentes) --------------------
function Get-ActionFingerprint($t) {
    switch ($t.type) {
        'registry' { return 'registry|' + (($t.registry | ForEach-Object { "$($_.Path)::$($_.Name)::$($_.Value)" } | Sort-Object) -join ';') }
        'script'   { return 'script|' + (($t.InvokeScript) -join "`n") }
        'appx'     { $pkgs = if ($t.packages) { $t.packages } else { $t.appx }; if ($pkgs) { return 'appx|' + (($pkgs | Sort-Object) -join ';') } else { return $null } }
        default    { return $null }
    }
}
$fpMap = @{}
foreach ($t in $tweaks) {
    $fp = Get-ActionFingerprint $t
    if (-not $fp) { continue }
    if (-not $fpMap.ContainsKey($fp)) { $fpMap[$fp] = New-Object System.Collections.Generic.List[string] }
    $fpMap[$fp].Add($t.id)
}
foreach ($fp in $fpMap.Keys) {
    if ($fpMap[$fp].Count -gt 1) {
        Add-Err "Ação idêntica duplicada entre IDs: $($fpMap[$fp] -join ', ') -> mesmo efeito, deveria ser um único tweak."
    }
}

# 7) Chave de registro compartilhada sem conflito declarado -------------------
#    (dois tweaks diferentes que escrevem o mesmo Path+Name sem se marcarem
#    como conflitantes = risco de rollback pisar um no outro)
$keyMap = @{}
foreach ($t in $tweaks) {
    if ($t.type -ne 'registry') { continue }
    foreach ($op in @($t.registry)) {
        $key = "$($op.Path)::$($op.Name)"
        if (-not $keyMap.ContainsKey($key)) { $keyMap[$key] = New-Object System.Collections.Generic.List[string] }
        $keyMap[$key].Add($t.id)
    }
}
foreach ($key in $keyMap.Keys) {
    $ids = $keyMap[$key] | Select-Object -Unique
    if ($ids.Count -le 1) { continue }
    foreach ($a in $ids) {
        foreach ($b in $ids) {
            if ($a -ne $b -and (@($byId[$a].conflicts) -notcontains $b)) {
                Add-Warn "Chave de registro '$key' escrita por $a e $b sem conflito declarado entre eles -> risco de rollback incorreto."
            }
        }
    }
}

# ---- Relatório final ---------------------------------------------------
Write-Host ""
if ($errors.Count -gt 0) {
    Write-Host "❌ $($errors.Count) erro(s):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
}
if ($warnings.Count -gt 0) {
    Write-Host "⚠️  $($warnings.Count) aviso(s):" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "   - $_" -ForegroundColor Yellow }
}
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "✅ catalog.json passou em todas as checagens." -ForegroundColor Green
}

if ($errors.Count -gt 0) { exit 1 }
if ($Strict -and $warnings.Count -gt 0) { exit 1 }
exit 0
