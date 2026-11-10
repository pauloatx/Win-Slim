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


function Set-RegistryValue {
    param($Path, $Name, $Value, $Type)
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ("$Value" -eq '<Remove>') { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
    else { New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null }
}


function Test-EmbeddedRegistryVerify {
    # Compartilhada por qualquer tweak tipo 'script' que grava registro via
    # Set-ItemProperty/Remove-ItemProperty com caminho LITERAL (entre aspas
    # simples) em vez do array estruturado 'registry'. Caminhos dinâmicos
    # (variável interpolada, como no PERF-018 por GPU) não são capturados
    # aqui de propósito - não finjo verificar o que não consigo resolver
    # sem re-executar a mesma enumeração de hardware do próprio tweak.
    param([string]$ScriptText)
    $checks = @()
    $setMatches = [regex]::Matches($ScriptText, "(?i)Set-ItemProperty\s+-Path\s+'([^']+)'\s+-Name\s+'([^']+)'\s+-Value\s+(\S+?)[\s,]")
    foreach ($m in $setMatches) {
        $path = $m.Groups[1].Value; $name = $m.Groups[2].Value; $valRaw = $m.Groups[3].Value
        if ($valRaw -match '^\(') { continue }  # valores complexos (ex.: [byte[]](...)) nao dao pra comparar por regex simples
        $expectedNum = if ($valRaw -match '^0x') { [Convert]::ToInt64($valRaw, 16) } else { $valRaw }
        $cur = Get-CurrentRegistryState -Path $path -Name $name
        $pass = $cur.Existed -and ([string]$cur.Value -eq [string]$expectedNum)
        $checks += [PSCustomObject]@{ Type = 'Registry'; Target = "$path\$name"; Expected = $expectedNum; Actual = $(if ($cur.Existed) { $cur.Value } else { '<ausente>' }); Pass = $pass }
    }
    $remMatches = [regex]::Matches($ScriptText, "(?i)Remove-ItemProperty\s+-Path\s+'([^']+)'\s+-Name\s+'([^']+)'")
    foreach ($m in $remMatches) {
        $path = $m.Groups[1].Value; $name = $m.Groups[2].Value
        $cur = Get-CurrentRegistryState -Path $path -Name $name
        $checks += [PSCustomObject]@{ Type = 'Registry'; Target = "$path\$name"; Expected = '<ausente>'; Actual = $(if ($cur.Existed) { $cur.Value } else { '<ausente>' }); Pass = (-not $cur.Existed) }
    }
    return @($checks)
}


function Test-RegistryVerify {
    # Verifica o array 'registry' estruturado de um tweak (Path/Name/Value/
    # OriginalValue). Para registro embutido em InvokeScript sem essa
    # estrutura, ver Test-EmbeddedRegistryVerify acima.
    param($RegistryOps, [switch]$Undo)
    $checks = @()
    foreach ($r in @($RegistryOps)) {
        $cur = Get-CurrentRegistryState -Path $r.Path -Name $r.Name
        $expectExists = if ($Undo) { $r.PSObject.Properties.Name -contains 'OriginalValue' } else { $true }
        $expected = if ($Undo) { $r.OriginalValue } else { $r.Value }
        $pass = if (-not $expectExists) { -not $cur.Existed } else { $cur.Existed -and ("$($cur.Value)" -eq "$expected") }
        $checks += [PSCustomObject]@{ Type = 'Registry'; Target = "$($r.Path)\$($r.Name)"; Expected = $expected; Actual = $(if ($cur.Existed) { $cur.Value } else { '<ausente>' }); Pass = [bool]$pass }
    }
    return @($checks)
}


# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2) - Detect/Backup/Apply/Verify/Undo por trás
# do contrato único (New-ProviderResult). Get-CurrentRegistryState/
# Set-RegistryValue acima continuam existindo (usados pelo motor legado
# ainda em migração) - as funções abaixo são a API nova, mais rica.
# ============================================================================

function Get-RegistryState {
    # Detect: estado atual de uma chave, no formato da seção 10 do backlog.
    param([string]$Path, [string]$Name)
    $cur = Get-CurrentRegistryState -Path $Path -Name $Name
    $type = $null
    if ($cur.Existed) {
        try {
            $key = Get-Item -Path $Path -ErrorAction Stop
            $type = $key.GetValueKind($Name).ToString()
        } catch { }
    }
    return [PSCustomObject]@{ Path = $Path; Name = $Name; Exists = $cur.Existed; Type = $type; Value = $cur.Value }
}

function Remove-RegistryValue {
    param([string]$Path, [string]$Name)
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue }
}

function Test-RegistryValue {
    # Verify de UM valor especifico contra um estado esperado (Exists/Value).
    param([string]$Path, [string]$Name, $ExpectedValue, [bool]$ExpectedExists = $true)
    $cur = Get-RegistryState -Path $Path -Name $Name
    $pass = if (-not $ExpectedExists) { -not $cur.Exists } else { $cur.Exists -and ("$($cur.Value)" -eq "$ExpectedValue") }
    return [PSCustomObject]@{ Type = 'Registry'; Target = "$Path\$Name"; Expected = $(if ($ExpectedExists) { $ExpectedValue } else { '<ausente>' }); Actual = $(if ($cur.Exists) { $cur.Value } else { '<ausente>' }); Pass = [bool]$pass }
}

function Backup-RegistryValue {
    # Backup: devolve o snapshot ANTES de qualquer Apply - inclui se a chave
    # existia ou não (crucial pro Undo saber se deve restaurar valor ou
    # remover a chave por completo).
    param([string]$Path, [string]$Name)
    return Get-RegistryState -Path $Path -Name $Name
}

function Restore-RegistryValue {
    # Undo: recebe o StateBefore devolvido por Backup-RegistryValue.
    param($StateBefore)
    if (-not $StateBefore.Exists) {
        Remove-RegistryValue -Path $StateBefore.Path -Name $StateBefore.Name
    } else {
        Set-RegistryValue -Path $StateBefore.Path -Name $StateBefore.Name -Value $StateBefore.Value -Type $StateBefore.Type
    }
}

function Invoke-RegistryProvider {
    <#
        Fluxo completo Detect -> Backup -> Apply -> Verify para UM tweak
        (pode ter varios pares Path/Name em $RegistryOps).

        Correcoes da Fase 2.1 (achadas em execucao real no Windows, nao
        teoricas):
        1) Generic.List[object].Add() dava ArgumentException no binder do
           PowerShell 5.1 nesse fluxo - trocado por array comum (@() + +=),
           que nao depende de resolucao de metodo .NET.
        2) $referenceState explicito: no Undo, a referencia OBRIGATORIA e o
           BackupData persistido, nunca $stateBefore (que numa sessao nova
           de Undo comeca vazio - usar isso como fallback era um bug: o
           Verify contra "vazio" resultava em sucesso falso por ausencia
           de checks, nao por confirmacao real).
        3) Sem BackupData no Undo -> throw explicito, nunca inventar estado.
        4) Verify so pode ser Success=true se o numero de checks bater com o
           numero de operacoes - checks vazios nunca contam como sucesso.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] $RegistryOps,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null
    )
    $stateBefore = @()
    $stateAfter = @()
    $referenceState = @()
    $changed = $false
    $errorMsg = $null

    try {
        if ($Action -eq 'Apply') {
            foreach ($op in @($RegistryOps)) {
                $before = Backup-RegistryValue -Path $op.Path -Name $op.Name
                $stateBefore += $before
                Set-RegistryValue -Path $op.Path -Name $op.Name -Value $op.Value -Type $op.Type
                $changed = $true
            }
            $referenceState = $stateBefore
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar com segurança sem o estado original salvo."
            }
            $referenceState = @($BackupData)
            foreach ($before in $referenceState) {
                Restore-RegistryValue -StateBefore $before
                $changed = $true
            }
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    foreach ($op in @($RegistryOps)) {
        $stateAfter += (Get-RegistryState -Path $op.Path -Name $op.Name)
    }

    $verifyChecks = @()
    foreach ($op in @($RegistryOps)) {
        if ($Action -eq 'Apply') {
            $verifyChecks += (Test-RegistryValue -Path $op.Path -Name $op.Name -ExpectedValue $op.Value -ExpectedExists $true)
        } else {
            $matchRef = @($referenceState) | Where-Object { $_.Path -eq $op.Path -and $_.Name -eq $op.Name } | Select-Object -First 1
            if ($matchRef) {
                $verifyChecks += (Test-RegistryValue -Path $op.Path -Name $op.Name -ExpectedValue $matchRef.Value -ExpectedExists $matchRef.Exists)
            } else {
                $verifyChecks += [PSCustomObject]@{ Type = 'Registry'; Target = "$($op.Path)\$($op.Name)"; Expected = '<referência ausente no backup>'; Actual = '<não verificável>'; Pass = $false }
            }
        }
    }
    # Verify só passa se TODO op teve um check gerado E todos passaram -
    # checks vazios (menos checks do que operações) nunca contam como sucesso.
    $verifyOk = (@($verifyChecks).Count -eq @($RegistryOps).Count) -and (-not (@($verifyChecks) | Where-Object { -not $_.Pass }))

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]($changed -and -not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore @($stateBefore) -StateAfter @($stateAfter) `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = @($verifyChecks) }) `
        -ErrorMessage $errorMsg
}
