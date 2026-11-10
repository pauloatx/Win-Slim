function Test-ScheduledTaskVerify {
    # Extrai nomes de tarefa literais do proprio script (via -TaskName 'X' ou
    # $var = 'X' reaproveitado depois). Quando a selecao e dinamica (ex.:
    # -TaskPath + -match, como no PRIV-014), nao finge que verificou algo
    # que nao consegue identificar por nome - registra isso explicitamente.
    param([string]$ScriptText)
    $checks = @()
    $taskNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in [regex]::Matches($ScriptText, "-TaskName\s+'([^']+)'")) { [void]$taskNames.Add($m.Groups[1].Value) }
    foreach ($m in [regex]::Matches($ScriptText, "\`$\w+\s*=\s*'([^']+)'")) { [void]$taskNames.Add($m.Groups[1].Value) }

    $registers = [regex]::IsMatch($ScriptText, '(?i)Register-ScheduledTask')
    $unregisters = [regex]::IsMatch($ScriptText, '(?i)Unregister-ScheduledTask')
    $disables = [regex]::IsMatch($ScriptText, '(?i)\|\s*Disable-ScheduledTask')
    $enables = [regex]::IsMatch($ScriptText, '(?i)\|\s*Enable-ScheduledTask')

    foreach ($name in $taskNames) {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($unregisters) {
            $checks += [PSCustomObject]@{ Type = 'ScheduledTask'; Target = $name; Expected = '<ausente>'; Actual = $(if ($task) { 'presente' } else { 'ausente' }); Pass = (-not $task) }
        } elseif ($registers) {
            $checks += [PSCustomObject]@{ Type = 'ScheduledTask'; Target = $name; Expected = 'presente'; Actual = $(if ($task) { 'presente' } else { 'ausente' }); Pass = [bool]$task }
        } elseif ($disables) {
            $state = if ($task) { $task.State.ToString() } else { $null }
            $checks += [PSCustomObject]@{ Type = 'ScheduledTask'; Target = $name; Expected = 'Disabled'; Actual = $(if ($state) { $state } else { '<tarefa ausente>' }); Pass = ($state -eq 'Disabled') }
        } elseif ($enables) {
            $state = if ($task) { $task.State.ToString() } else { $null }
            $checks += [PSCustomObject]@{ Type = 'ScheduledTask'; Target = $name; Expected = 'habilitada (Ready/Running)'; Actual = $(if ($state) { $state } else { '<tarefa ausente ou nunca existiu>' }); Pass = ($state -eq 'Ready' -or $state -eq 'Running') }
        }
    }
    if ($taskNames.Count -eq 0 -and ($registers -or $unregisters -or $disables -or $enables)) {
        $checks += [PSCustomObject]@{ Type = 'ScheduledTask'; Target = '(seleção dinâmica via -TaskPath/-match)'; Expected = '<não verificável automaticamente>'; Actual = 'nome de tarefa não é literal no script'; Pass = $true }
    }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2) - Backup preserva existencia + estado +
# DEFINICAO (XML completo via Export-ScheduledTask), nao so o nome. Isso
# permite recriar a tarefa do zero no Undo se ela tiver sido removida por
# completo (Unregister), nao so reabilitar uma que so foi desativada.
# ============================================================================

function Get-ScheduledTaskState {
    param([string]$TaskName, [string]$TaskPath = '\')
    $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
    if (-not $task) { return [PSCustomObject]@{ TaskName = $TaskName; TaskPath = $TaskPath; Exists = $false; State = $null; Xml = $null } }
    $xml = $null
    try { $xml = Export-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction Stop } catch { }
    return [PSCustomObject]@{ TaskName = $TaskName; TaskPath = $TaskPath; Exists = $true; State = $task.State.ToString(); Xml = $xml }
}

function Set-ScheduledTaskEnabledState {
    param([string]$TaskName, [string]$TaskPath = '\', [bool]$Enabled)
    if ($Enabled) { Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null }
    else { Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null }
}

function Restore-ScheduledTaskState {
    <#
        Undo: se a tarefa nao existia antes (StateBefore.Exists = false) e
        ainda existe agora, remove. Se existia e foi so desativada, reabilita.
        Se existia mas foi REMOVIDA por completo (Unregister) e temos o XML
        do backup, recria a tarefa a partir dele - fallback real, nao so
        reabilitar algo que nao esta la.
    #>
    param($StateBefore)
    $nowExists = [bool](Get-ScheduledTask -TaskName $StateBefore.TaskName -TaskPath $StateBefore.TaskPath -ErrorAction SilentlyContinue)
    if (-not $StateBefore.Exists) {
        if ($nowExists) { Unregister-ScheduledTask -TaskName $StateBefore.TaskName -TaskPath $StateBefore.TaskPath -Confirm:$false -ErrorAction SilentlyContinue }
        return
    }
    if (-not $nowExists -and $StateBefore.Xml) {
        Register-ScheduledTask -TaskName $StateBefore.TaskName -TaskPath $StateBefore.TaskPath -Xml $StateBefore.Xml -Force -ErrorAction SilentlyContinue | Out-Null
        return
    }
    Set-ScheduledTaskEnabledState -TaskName $StateBefore.TaskName -TaskPath $StateBefore.TaskPath -Enabled ($StateBefore.State -ne 'Disabled')
}

function Invoke-ScheduledTaskProvider {
    <#
        Correção Fase 2.1: $before era consultado incondicionalmente ANTES
        de checar $Action - no Undo isso lia o estado JÁ ALTERADO pelo Apply
        (mesmo bug dos outros providers). Agora só consulta "antes" de
        verdade dentro do ramo Apply; Undo exige BackupData.
    #>
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$TaskName,
        [string]$TaskPath = '\',
        [ValidateSet('Disable', 'Unregister')] [string]$ApplyMode = 'Disable',
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply',
        $BackupData = $null
    )
    $errorMsg = $null
    $changed = $false
    $referenceState = $null

    try {
        if ($Action -eq 'Apply') {
            $referenceState = Get-ScheduledTaskState -TaskName $TaskName -TaskPath $TaskPath
            if ($ApplyMode -eq 'Disable') { Set-ScheduledTaskEnabledState -TaskName $TaskName -TaskPath $TaskPath -Enabled $false }
            else { Unregister-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Confirm:$false -ErrorAction SilentlyContinue }
            $changed = $true
        } else {
            if (-not $BackupData) {
                throw "Undo de '$Id' requer BackupData persistido - não há como restaurar a tarefa '$TaskName' com segurança sem o estado original salvo."
            }
            $referenceState = $BackupData
            Restore-ScheduledTaskState -StateBefore $referenceState
            $changed = $true
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $after = Get-ScheduledTaskState -TaskName $TaskName -TaskPath $TaskPath
    $verifyOk = if ($errorMsg) { $false } elseif ($Action -eq 'Apply') {
        if ($ApplyMode -eq 'Disable') { $after.Exists -and $after.State -eq 'Disabled' } else { -not $after.Exists }
    } else {
        if ($referenceState.Exists) { $after.Exists -and ($after.State -ne 'Disabled') -eq ($referenceState.State -ne 'Disabled') } else { -not $after.Exists }
    }

    $expectedText = if ($Action -eq 'Apply') {
        if ($ApplyMode -eq 'Disable') { 'Exists=True; State=Disabled' } else { 'Exists=False' }
    } else {
        if ($referenceState -and $referenceState.Exists) { "Exists=True; Enabled=$($referenceState.State -ne 'Disabled')" } else { 'Exists=False' }
    }
    $actualText = "Exists=$($after.Exists); State=$($after.State)"
    $verifyCheck = [PSCustomObject]@{ Type = 'ScheduledTask'; Target = "$TaskPath$TaskName"; Expected = $expectedText; Actual = $actualText; Pass = [bool]$verifyOk }

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool](-not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore $referenceState -StateAfter $after `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = @($verifyCheck) }) `
        -Restart 'None' -ErrorMessage $errorMsg
}
