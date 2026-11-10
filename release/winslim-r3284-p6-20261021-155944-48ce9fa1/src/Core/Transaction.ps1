<#
    Win-Slim Suite - Transaction Manager (Fase 3)

    Objetivos:
    - manter compatibilidade com New-Transaction/Add-TransactionStep/Invoke-TransactionRollback;
    - persistir cada transacao em disco para diagnostico e recuperacao;
    - rollback LIFO;
    - preservar o PRIMEIRO backup de cada tweak durante a transacao;
    - nunca declarar rollback completo se algum Undo/Verify falhar;
    - separar a orquestracao transacional da implementacao dos Providers;
    - continuar compativel com Windows PowerShell 5.1.
#>

$script:TransactionSchemaVersion = 4
$script:TransactionTerminalStates = @('Committed', 'CommittedWithErrors', 'RolledBack', 'RollbackFailed', 'PartiallyRolledBack', 'Simulated')
$script:TransactionLockHandle = $null

function Write-TransactionLog {
    param([string]$Message, [string]$Level = 'INFO')
    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log $Message $Level
    }
}

function ConvertTo-TransactionPlainValueInternal {
    <#
      R11: normalizador sem pipeline. O resultado e devolvido exclusivamente por
      [ref], evitando PSObject wrappers criados por Write-Output -NoEnumerate no
      Windows PowerShell 5.1. Isto e critico para arrays top-level e nested arrays.
    #>
    param(
        $InputObject,
        [Parameter(Mandatory)] [ref]$Output,
        [int]$Depth = 0
    )

    if ($Depth -gt 32) { throw 'ConvertTo-TransactionPlainValueInternal excedeu a profundidade maxima (32).' }
    if ($null -eq $InputObject) { $Output.Value = $null; return }

    if ($InputObject -is [byte[]]) {
        $Output.Value = [byte[]]$InputObject.Clone()
        return
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in @($InputObject.Keys)) {
            $child = $null
            ConvertTo-TransactionPlainValueInternal -InputObject $InputObject[$key] -Output ([ref]$child) -Depth ($Depth + 1)
            $copy[$key] = $child
        }
        $Output.Value = $copy
        return
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            $child = $null
            ConvertTo-TransactionPlainValueInternal -InputObject $item -Output ([ref]$child) -Depth ($Depth + 1)
            [void]$items.Add($child)
        }
        $Output.Value = [object[]]$items.ToArray()
        return
    }

    if ($InputObject -is [string] -or
        $InputObject -is [char] -or
        $InputObject -is [bool] -or
        $InputObject -is [byte] -or
        $InputObject -is [sbyte] -or
        $InputObject -is [int16] -or
        $InputObject -is [uint16] -or
        $InputObject -is [int32] -or
        $InputObject -is [uint32] -or
        $InputObject -is [int64] -or
        $InputObject -is [uint64] -or
        $InputObject -is [single] -or
        $InputObject -is [double] -or
        $InputObject -is [decimal] -or
        $InputObject -is [datetime] -or
        $InputObject -is [timespan] -or
        $InputObject -is [guid] -or
        $InputObject -is [System.Enum]) {

        $baseObject = $InputObject.PSObject.BaseObject
        $Output.Value = $(if ($null -ne $baseObject) { $baseObject } else { $InputObject })
        return
    }

    $props = @($InputObject.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($props.Count -gt 0) {
        $bag = [ordered]@{}
        foreach ($prop in $props) {
            $child = $null
            try {
                ConvertTo-TransactionPlainValueInternal -InputObject $prop.Value -Output ([ref]$child) -Depth ($Depth + 1)
                $bag[$prop.Name] = $child
            } catch {
                $bag[$prop.Name] = [string]$prop.Value
            }
        }
        $Output.Value = [PSCustomObject]$bag
        return
    }

    $Output.Value = [string]$InputObject
}

function Copy-TransactionObject {
    <#
      API de clone da Fase 3. R11 usa um normalizador interno por [ref] para que
      arrays vazios e nao-vazios nao dependam de Write-Output -NoEnumerate.
    #>
    param(
        $InputObject,
        [int]$Depth = 0
    )

    $result = $null
    ConvertTo-TransactionPlainValueInternal -InputObject $InputObject -Output ([ref]$result) -Depth $Depth

    # A virgula externa faz a funcao emitir o array como UM unico objeto sem criar
    # o wrapper ETS value/Count observado na R10.
    if ($result -is [System.Array]) { return ,$result }
    return $result
}

function Write-TransactionTrace {
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] [string]$Message
    )
    if (-not $Transaction.Persist) { return }
    try {
        if (-not (Test-Path -LiteralPath $Transaction.TransactionPath)) {
            New-Item -Path $Transaction.TransactionPath -ItemType Directory -Force | Out-Null
        }
        $line = '{0} | PID={1} | {2}{3}' -f (Get-Date -Format 'o'), $PID, $Message, [Environment]::NewLine
        [System.IO.File]::AppendAllText(
            (Join-Path $Transaction.TransactionPath 'trace.log'),
            $line,
            (New-Object System.Text.UTF8Encoding($false))
        )
    } catch { }
}

function Get-WinSlimTransactionRoot {
    param([string]$RootPath)
    if ($RootPath) { return $RootPath }
    $base = $null
    try { if ($ScriptRoot) { $base = $ScriptRoot } } catch { }
    if (-not $base) {
        try { if ($PSScriptRoot) { $base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } } catch { }
    }
    if (-not $base) { $base = (Get-Location).Path }
    return (Join-Path $base 'Transactions')
}

function Get-WinSlimTransactionBackupRoot {
    param([string]$RootPath)
    if ($RootPath) { return $RootPath }
    $base = $null
    try { if ($ScriptRoot) { $base = $ScriptRoot } } catch { }
    if (-not $base) {
        try { if ($PSScriptRoot) { $base = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } } catch { }
    }
    if (-not $base) { $base = (Get-Location).Path }
    return (Join-Path $base 'Backups')
}

function ConvertTo-TransactionJsonData {
    <#
      R11: compatibilidade publica para probes/testes. O clone real e produzido
      sem pipeline via ConvertTo-TransactionPlainValueInternal.
    #>
    param($Data)

    $copy = $null
    ConvertTo-TransactionPlainValueInternal -InputObject $Data -Output ([ref]$copy)
    if ($copy -is [System.Array]) { return ,$copy }
    return $copy
}

function ConvertTo-TransactionJsonText {
    <#
      R12: serializer firewall para JSON top-level.

      Windows PowerShell 5.1 pode adaptar/envelopar arrays passados ao
      ConvertTo-Json e produzir objetos como {"value":[...],"Count":N}.
      Journals transacionais PRECISAM ser arrays JSON reais para recovery.

      Portanto, colecoes top-level sao escritas explicitamente como JSON array,
      serializando cada item individualmente. Objetos/escalares continuam usando
      ConvertTo-Json apos normalizacao ETS-safe.
    #>
    param(
        [AllowNull()] $Data,
        [int]$Depth = 32
    )

    if ($null -eq $Data) { return 'null' }

    $isTopLevelCollection = (
        ($Data -is [System.Collections.IEnumerable]) -and
        -not ($Data -is [string]) -and
        -not ($Data -is [System.Collections.IDictionary])
    )

    if ($isTopLevelCollection) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.Append('[')
        $first = $true

        foreach ($item in $Data) {
            if (-not $first) { [void]$sb.Append(',') }

            $normalizedItem = $null
            ConvertTo-TransactionPlainValueInternal -InputObject $item -Output ([ref]$normalizedItem)

            if ($null -eq $normalizedItem) {
                $itemJson = 'null'
            }
            elseif (($normalizedItem -is [System.Collections.IEnumerable]) -and
                    -not ($normalizedItem -is [string]) -and
                    -not ($normalizedItem -is [System.Collections.IDictionary])) {
                # Suporte defensivo para arrays aninhados em arrays top-level.
                $itemJson = ConvertTo-TransactionJsonText -Data $normalizedItem -Depth ([Math]::Max(1, $Depth - 1))
            }
            else {
                $itemJson = ConvertTo-Json -InputObject $normalizedItem -Depth ([Math]::Max(1, $Depth - 1)) -Compress
            }

            [void]$sb.Append($itemJson)
            $first = $false
        }

        [void]$sb.Append(']')
        return $sb.ToString()
    }

    $jsonData = $null
    ConvertTo-TransactionPlainValueInternal -InputObject $Data -Output ([ref]$jsonData)

    if ($null -eq $jsonData) { return 'null' }
    return (ConvertTo-Json -InputObject $jsonData -Depth $Depth -Compress)
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [AllowNull()] $Data,
        [int]$Depth = 32
    )
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    $bak = "$Path.bak"

    # R12: nao delegar arrays top-level ao ConvertTo-Json. O texto JSON e
    # produzido pelo serializer firewall acima, garantindo [] / [{...},{...}].
    $json = ConvertTo-TransactionJsonText -Data $Data -Depth $Depth

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmp, $json, $utf8Bom)
    try {
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tmp, $Path, $bak, $true)
                if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
            } catch {
                Move-Item -LiteralPath $tmp -Destination $Path -Force
            }
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Enter-WinSlimTransactionLock {
    param([string]$RootPath)
    if ($script:TransactionLockHandle) { return $script:TransactionLockHandle }
    $root = Get-WinSlimTransactionRoot -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $root)) { New-Item -Path $root -ItemType Directory -Force | Out-Null }
    $lockPath = Join-Path $root '.winslim-transaction.lock'
    try {
        $fs = New-Object System.IO.FileStream($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $meta = "PID=$PID`r`nStartedAt=$((Get-Date).ToString('o'))`r`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($meta)
        $fs.SetLength(0)
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)
        $script:TransactionLockHandle = $fs
        return $fs
    } catch {
        throw "Ja existe outra transacao Win-Slim em execucao ou o lock nao pode ser adquirido: $lockPath. $($_.Exception.Message)"
    }
}

function Exit-WinSlimTransactionLock {
    if ($script:TransactionLockHandle) {
        $lockPath = $null
        try { $lockPath = $script:TransactionLockHandle.Name } catch { }
        try { $script:TransactionLockHandle.Dispose() } catch { }
        $script:TransactionLockHandle = $null
        # O FileStream/Share.None e a autoridade do lock. O arquivo fisico e apenas
        # metadado; removemos quando possivel para nao deixar um falso "lock ativo".
        if ($lockPath) {
            try { Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

function New-Transaction {
    param(
        [ValidateSet('Apply', 'Undo', 'Recovery')] [string]$Mode = 'Apply',
        [ValidateSet('RollbackTransaction', 'Stop', 'Continue')] [string]$FailurePolicy = 'RollbackTransaction',
        [string]$RootPath,
        [string]$BackupRootPath,
        $Plan = @(),
        [switch]$NoPersist
    )

    $id = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $txRoot = Get-WinSlimTransactionRoot -RootPath $RootPath
    $backupRoot = Get-WinSlimTransactionBackupRoot -RootPath $BackupRootPath
    $txPath = Join-Path $txRoot $id
    $backupPath = Join-Path $backupRoot $id
    if (-not $NoPersist) {
        New-Item -Path $txPath -ItemType Directory -Force | Out-Null
        New-Item -Path $backupPath -ItemType Directory -Force | Out-Null
    }

    $tx = [PSCustomObject]@{
        SchemaVersion   = $script:TransactionSchemaVersion
        Id              = $id
        Mode            = $Mode
        FailurePolicy   = $FailurePolicy
        Status          = 'Created'
        CreatedAt       = (Get-Date -Format 'o')
        UpdatedAt       = (Get-Date -Format 'o')
        CompletedAt     = $null
        ProcessId       = $PID
        PowerShell      = $PSVersionTable.PSVersion.ToString()
        TransactionPath = $txPath
        BackupPath      = $backupPath
        Persist         = (-not $NoPersist)
        Plan            = @($Plan)
        Steps           = @()
        StatusHistory   = @([PSCustomObject]@{ Status = 'Created'; At = (Get-Date -Format 'o'); Detail = $null })
        RestartRequired = $false
        RestartScopes   = @()
        Failure         = $null
        Recovery        = [PSCustomObject]@{ Required = $false; LastKnownStep = $null }
    }
    if ($tx.Persist) { Save-Transaction -Transaction $tx }
    return $tx
}

function Get-TransactionMetadataSnapshot {
    <#
      transaction.json passa a ser somente o envelope/metaestado da transacao.
      Plan e Steps ficam nos sidecars plan.json/operations.json. Isso elimina a
      serializacao monolitica do grafo vivo e reduz muito a superficie de bugs
      do ConvertTo-Json no Windows PowerShell 5.1.
    #>
    param([Parameter(Mandatory)] $Transaction)
    return [PSCustomObject]@{
        SchemaVersion   = $Transaction.SchemaVersion
        Id              = $Transaction.Id
        Mode            = $Transaction.Mode
        FailurePolicy   = $Transaction.FailurePolicy
        Status          = $Transaction.Status
        CreatedAt       = $Transaction.CreatedAt
        UpdatedAt       = $Transaction.UpdatedAt
        CompletedAt     = $Transaction.CompletedAt
        ProcessId       = $Transaction.ProcessId
        PowerShell      = $Transaction.PowerShell
        TransactionPath = $Transaction.TransactionPath
        BackupPath      = $Transaction.BackupPath
        Persist         = [bool]$Transaction.Persist
        StatusHistory   = Copy-TransactionObject -InputObject @($Transaction.StatusHistory)
        RestartRequired = [bool]$Transaction.RestartRequired
        RestartScopes   = Copy-TransactionObject -InputObject @($Transaction.RestartScopes)
        Failure         = Copy-TransactionObject -InputObject $Transaction.Failure
        Recovery        = Copy-TransactionObject -InputObject $Transaction.Recovery
    }
}

function Get-TransactionStepPersistenceSnapshot {
    <#
      R6: operations.json e um JOURNAL compacto para recovery, nao um dump do
      objeto Step vivo. Resultados detalhados (ApplyResult/VerifyResult,
      StateBefore/StateAfter e UndoResult) sao mantidos em memoria e nos
      artefatos finais, mas nao sao reserializados a cada checkpoint.

      Motivo: no Windows PowerShell 5.1, a serializacao repetida do grafo Step
      apos Verify pode prender ConvertTo-Json. Para recovery precisamos apenas
      da identidade do tweak, estado transacional e referencia ao backup ja
      persistido antes do Apply.
    #>
    param([Parameter(Mandatory)] $Step)

    return [PSCustomObject]@{
        Sequence       = [int]$Step.Sequence
        TweakId        = [string]$Step.TweakId
        Level          = [int]$Step.Level
        Status         = [string]$Step.Status
        StartedAt      = $Step.StartedAt
        CompletedAt    = $Step.CompletedAt
        Changed        = [bool]$Step.Changed
        Tweak          = Copy-TransactionObject -InputObject $Step.Tweak
        BackupFile     = $Step.BackupFile
        Restart        = [string]$Step.Restart
        RollbackStatus = [string]$Step.RollbackStatus
        Warning        = $Step.Warning
        Error          = $Step.Error
    }
}

function Get-TransactionOperationsPersistenceSnapshot {
    param([Parameter(Mandatory)] $Transaction)
    # R11: emitir Steps individualmente. O caller materializa com @(...), evitando
    # tanto o colapso de [] quanto wrappers PSObject de Write-Output -NoEnumerate.
    foreach ($step in @($Transaction.Steps)) {
        Get-TransactionStepPersistenceSnapshot -Step $step
    }
}

function Get-TransactionVerificationPersistenceSnapshot {
    <#
      R7: nunca persistir o objeto Verification vivo. Guardamos apenas o que o
      Transaction Manager precisa para auditoria: aplicabilidade, resultado e
      contagem de checks. Isso evita reintroduzir grafos arbitrarios no JSON.
    #>
    param($Verification)
    if ($null -eq $Verification) { return $null }

    $checks = @()
    if ($Verification.PSObject.Properties.Name -contains 'Checks' -and $null -ne $Verification.Checks) {
        $checks = @($Verification.Checks)
    }
    $failed = @($checks | Where-Object {
        $_ -and $_.PSObject.Properties.Name -contains 'Pass' -and -not [bool]$_.Pass
    }).Count

    return [PSCustomObject]@{
        Applicable = $(if ($Verification.PSObject.Properties.Name -contains 'Applicable') { [bool]$Verification.Applicable } else { $true })
        Success    = $(if ($Verification.PSObject.Properties.Name -contains 'Success') { [bool]$Verification.Success } else { $false })
        CheckCount = [int]$checks.Count
        FailedCount = [int]$failed
    }
}

function Get-TransactionProviderResultPersistenceSnapshot {
    <#
      R7 serialization firewall: ProviderResult completo permanece em memoria,
      mas journals persistentes recebem somente campos escalares e um resumo do
      Verify. StateBefore/StateAfter/BackupData continuam fora deste snapshot.
    #>
    param($Result)
    if ($null -eq $Result) { return $null }

    $verification = $null
    if ($Result.PSObject.Properties.Name -contains 'Verification') {
        $verification = Get-TransactionVerificationPersistenceSnapshot -Verification $Result.Verification
    }

    return [PSCustomObject]@{
        Id           = $(if ($Result.PSObject.Properties.Name -contains 'Id') { [string]$Result.Id } else { $null })
        Success      = $(if ($Result.PSObject.Properties.Name -contains 'Success') { [bool]$Result.Success } else { $false })
        Changed      = $(if ($Result.PSObject.Properties.Name -contains 'Changed') { [bool]$Result.Changed } else { $false })
        Restart      = $(if ($Result.PSObject.Properties.Name -contains 'Restart') { [string]$Result.Restart } else { 'None' })
        Warning      = $(if ($Result.PSObject.Properties.Name -contains 'Warning') { $Result.Warning } else { $null })
        Error        = $(if ($Result.PSObject.Properties.Name -contains 'Error') { $Result.Error } else { $null })
        Verification = $verification
    }
}

function Get-TransactionRollbackPersistenceSnapshot {
    <# R11: journal compacto; emissao item-a-item para o caller capturar com @(...). #>
    param([Parameter(Mandatory)] $Transaction)
    foreach ($step in @($Transaction.Steps | Where-Object { $_.Changed -or $_.RollbackStatus -ne 'NotRequired' })) {
        [PSCustomObject]@{
            Sequence       = [int]$step.Sequence
            TweakId        = [string]$step.TweakId
            Status         = [string]$step.Status
            RollbackStatus = [string]$step.RollbackStatus
            BackupFile     = $step.BackupFile
            Undo           = Get-TransactionProviderResultPersistenceSnapshot -Result $step.UndoResult
            Warning        = $step.Warning
            Error          = $step.Error
        }
    }
}

function Get-TransactionStateBeforePersistenceSnapshot {
    param([Parameter(Mandatory)] $Transaction)
    foreach ($step in @($Transaction.Steps)) {
        [PSCustomObject]@{
            Sequence   = [int]$step.Sequence
            TweakId    = [string]$step.TweakId
            Status     = [string]$step.Status
            HasBackup  = [bool]($null -ne $step.BackupData -or [bool]$step.BackupFile)
            BackupFile = $step.BackupFile
        }
    }
}

function Get-TransactionStateAfterPersistenceSnapshot {
    param([Parameter(Mandatory)] $Transaction)
    foreach ($step in @($Transaction.Steps)) {
        $verify = $null
        if ($null -ne $step.VerifyResult) {
            $verify = Get-TransactionVerificationPersistenceSnapshot -Verification $step.VerifyResult
        }
        [PSCustomObject]@{
            Sequence     = [int]$step.Sequence
            TweakId      = [string]$step.TweakId
            Status       = [string]$step.Status
            Changed      = [bool]$step.Changed
            Restart      = [string]$step.Restart
            Verification = $verify
            Warning      = $step.Warning
            Error        = $step.Error
        }
    }
}

function Restore-TransactionStepRuntimeFields {
    <#
      Reidrata campos que nao vivem em operations.json. BackupData e lido do
      arquivo imutavel criado ANTES do Apply. Os demais campos detalhados podem
      ficar nulos durante recovery; eles nao sao necessarios para Undo.
    #>
    param([Parameter(Mandatory)] $Step)

    foreach ($name in @('StateBefore','StateAfter','BackupData','ApplyResult','VerifyResult','UndoResult')) {
        if ($Step.PSObject.Properties.Name -notcontains $name) {
            Add-Member -InputObject $Step -NotePropertyName $name -NotePropertyValue $null -Force
        }
    }

    if ($Step.BackupFile -and (Test-Path -LiteralPath ([string]$Step.BackupFile))) {
        try {
            $Step.BackupData = Read-TransactionBackupFile -Path ([string]$Step.BackupFile)
        } catch {
            throw "Falha ao reidratar BackupData do passo '$($Step.TweakId)': $($_.Exception.Message)"
        }
    }
    return $Step
}

function Save-Transaction {
    param([Parameter(Mandatory)] $Transaction)
    if (-not $Transaction.Persist) { return }
    $Transaction.UpdatedAt = (Get-Date -Format 'o')
    if (-not (Test-Path -LiteralPath $Transaction.TransactionPath)) { New-Item -Path $Transaction.TransactionPath -ItemType Directory -Force | Out-Null }

    $meta = Get-TransactionMetadataSnapshot -Transaction $Transaction
    $plan = @($Transaction.Plan)
    $steps = @(Get-TransactionOperationsPersistenceSnapshot -Transaction $Transaction)
    $rb = @(Get-TransactionRollbackPersistenceSnapshot -Transaction $Transaction)

    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / transaction.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'transaction.json') -Data $meta
    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / transaction.json AFTER'

    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / plan.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'plan.json') -Data $plan
    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / plan.json AFTER'

    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / operations.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'operations.json') -Data $steps
    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / operations.json AFTER'

    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / rollback.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'rollback.json') -Data $rb
    Write-TransactionTrace -Transaction $Transaction -Message 'SAVE / rollback.json AFTER'
}

function Set-TransactionStatus {
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] [string]$Status,
        [string]$Detail,
        [switch]$Force
    )
    if (-not $Force -and ($script:TransactionTerminalStates -contains [string]$Transaction.Status) -and $Transaction.Status -ne $Status) {
        throw "Transacao '$($Transaction.Id)' ja esta em estado terminal '$($Transaction.Status)' e nao pode mudar para '$Status'."
    }
    $Transaction.Status = $Status
    $Transaction.UpdatedAt = (Get-Date -Format 'o')
    if ($script:TransactionTerminalStates -contains $Status) { $Transaction.CompletedAt = (Get-Date -Format 'o') }
    $Transaction.StatusHistory += [PSCustomObject]@{ Status = $Status; At = (Get-Date -Format 'o'); Detail = $Detail }
    Save-Transaction -Transaction $Transaction
}

function Set-TransactionPlan {
    param([Parameter(Mandatory)] $Transaction, [Parameter(Mandatory)] $Plan)
    $Transaction.Plan = @($Plan)
    Set-TransactionStatus -Transaction $Transaction -Status 'Planned' -Detail "$(@($Plan).Count) operacao(oes) planejada(s)."
}

function Write-TransactionBackupAtomic {
    <#
      R8: BackupData autoritativo usa CliXml/PSSerializer, nao JSON.
      Motivo: backup de Provider pode conter arrays, byte[], objetos adaptados e
      outros tipos que o ConvertTo-Json do Windows PowerShell 5.1 trata de forma
      imprevisivel. Os journals continuam JSON; o snapshot de rollback precisa
      priorizar fidelidade de tipo e recovery cross-process.
    #>
    param(
        [Parameter(Mandatory)] [string]$Path,
        [AllowNull()] $Data
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    $bak = "$Path.bak"
    try {
        # R10: nunca entregar o objeto vivo do Provider ao PSSerializer.
        # Primeiro passa pela firewall de dados para remover ETS, handles e
        # propriedades adaptadas; depois serializa somente o snapshot limpo.
        $snapshot = $null
        ConvertTo-TransactionPlainValueInternal -InputObject $Data -Output ([ref]$snapshot)
        $xml = [System.Management.Automation.PSSerializer]::Serialize($snapshot, 16)
        $utf8Bom = New-Object System.Text.UTF8Encoding($true)
        [System.IO.File]::WriteAllText($tmp, $xml, $utf8Bom)
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tmp, $Path, $bak, $true)
                if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue }
            } catch {
                Move-Item -LiteralPath $tmp -Destination $Path -Force
            }
        } else {
            Move-Item -LiteralPath $tmp -Destination $Path -Force
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Read-TransactionBackupFile {
    param([Parameter(Mandatory)] [string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Backup nao encontrado: $Path" }

    # Compatibilidade com transactions R3-R7 que persistiam BackupData em JSON.
    if ([System.IO.Path]::GetExtension($Path) -ieq '.json') {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    }

    $xml = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return [System.Management.Automation.PSSerializer]::Deserialize($xml)
}

function Get-TransactionFirstBackup {
    param([Parameter(Mandatory)] $Transaction, [Parameter(Mandatory)] [string]$TweakId)

    # Procurar primeiro pela REFERENCIA de backup, sem tocar no grafo BackupData.
    $prior = @($Transaction.Steps | Where-Object {
        $_.TweakId -eq $TweakId -and ($_.BackupFile -or $null -ne $_.BackupData)
    } | Sort-Object Sequence | Select-Object -First 1)

    if ($prior.Count -eq 0) { return $null }
    $p = $prior[0]

    if ($p.BackupFile -and (Test-Path -LiteralPath ([string]$p.BackupFile))) {
        return Read-TransactionBackupFile -Path ([string]$p.BackupFile)
    }
    if ($null -ne $p.BackupData) {
        return Copy-TransactionObject -InputObject $p.BackupData
    }
    return $null
}

function Save-TransactionBackup {
    param([Parameter(Mandatory)] $Transaction, [Parameter(Mandatory)] $Step, $BackupData)
    if ($null -eq $BackupData) { return }

    Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / ENTER"

    # Imutabilidade: se o mesmo TweakId ja possui snapshot, reutilizar o PRIMEIRO.
    $priorStep = @($Transaction.Steps | Where-Object {
        $_.TweakId -eq $Step.TweakId -and $_.Sequence -lt $Step.Sequence -and ($_.BackupFile -or $null -ne $_.BackupData)
    } | Sort-Object Sequence | Select-Object -First 1)

    if ($priorStep.Count -gt 0) {
        Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / REUSE FIRST BEFORE"
        $first = Get-TransactionFirstBackup -Transaction $Transaction -TweakId $Step.TweakId
        $Step.BackupData = $first
        $Step.BackupFile = $priorStep[0].BackupFile
        Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / REUSE FIRST AFTER"
    } elseif ($Transaction.Persist) {
        $safeId = ($Step.TweakId -replace '[^A-Za-z0-9_.-]', '_')
        $file = '{0:D4}-{1}.clixml' -f [int]$Step.Sequence, $safeId
        $path = Join-Path $Transaction.BackupPath $file

        Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / CLIXML WRITE BEFORE"
        Write-TransactionBackupAtomic -Path $path -Data $BackupData
        Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / CLIXML WRITE AFTER"

        # A copia em memoria vem do snapshot persistido: uma unica fonte de verdade.
        $Step.BackupFile = $path
        $Step.BackupData = Read-TransactionBackupFile -Path $path
        Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / REHYDRATE AFTER"
    } else {
        $Step.BackupData = Copy-TransactionObject -InputObject $BackupData
    }

    Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / SAVE TX BEFORE"
    Save-Transaction -Transaction $Transaction
    Write-TransactionTrace -Transaction $Transaction -Message "BACKUP $($Step.Sequence) $($Step.TweakId) / SAVE TX AFTER"
}

function Add-TransactionStep {
    <# Compatibilidade com a API antiga + metadados completos da Fase 3. #>
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] $Tweak,
        [int]$Level = -1,
        [string]$Status = 'Pending'
    )
    $id = if ($Tweak.PSObject.Properties.Name -contains 'id') { [string]$Tweak.id } else { [string]$Tweak.Id }
    $step = [PSCustomObject]@{
        Sequence        = @($Transaction.Steps).Count + 1
        TweakId         = $id
        Level           = $Level
        Status          = $Status
        StartedAt       = $null
        CompletedAt     = $null
        Changed         = $false
        Tweak            = Copy-TransactionObject $Tweak
        StateBefore     = $null
        StateAfter      = $null
        BackupData      = $null
        BackupFile      = $null
        ApplyResult     = $null
        VerifyResult    = $null
        Restart         = 'None'
        RollbackStatus  = 'NotRequired'
        UndoResult      = $null
        Warning         = $null
        Error           = $null
    }
    $Transaction.Steps += $step
    Save-Transaction -Transaction $Transaction
    return $step
}

function Get-EngineRollbackBackup {
    param([string]$TweakId)
    try {
        if ($RollbackData -and $RollbackData.ContainsKey($TweakId)) {
            return Copy-TransactionObject $RollbackData[$TweakId]
        }
    } catch { }
    return $null
}

function Set-EngineRollbackBackup {
    param([string]$TweakId, $BackupData)
    try {
        if ($null -ne $RollbackData -and $null -ne $BackupData) {
            $RollbackData[$TweakId] = Copy-TransactionObject $BackupData
            if (Get-Command Save-Rollback -ErrorAction SilentlyContinue) { Save-Rollback }
        }
    } catch { }
}

function Test-TransactionApplyResult {
    param($Result)
    if ($null -eq $Result) { return $false }
    if (-not [bool]$Result.Success) { return $false }
    if ($Result.PSObject.Properties.Name -contains 'Verification' -and $Result.Verification) {
        if ($Result.Verification.PSObject.Properties.Name -contains 'Applicable' -and -not [bool]$Result.Verification.Applicable) { return $true }
        if ($Result.Verification.PSObject.Properties.Name -contains 'Success' -and -not [bool]$Result.Verification.Success) { return $false }
    }
    return $true
}

function Invoke-TransactionStep {
    param(
        [Parameter(Mandatory)] $Transaction,
        [Parameter(Mandatory)] $Step,
        $Context = $null,
        [scriptblock]$ApplyHandler,
        [scriptblock]$BackupHandler
    )
    if (-not $ApplyHandler) {
        $ApplyHandler = {
            param($Tweak, $Level, $Context)
            Invoke-Tweak -Tweak $Tweak -Action 'Apply' -Level $Level -Context $Context -StrictVerify
        }
    }

    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BEGIN"

    # Fase 3 R2: quando houver BackupHandler, o estado original e persistido ANTES
    # da mutacao. Isso fecha a janela de crash existente entre Apply e backup.
    $preBackup = Get-TransactionFirstBackup -Transaction $Transaction -TweakId $Step.TweakId
    if ($null -eq $preBackup -and $BackupHandler) {
        $Step.Status = 'BackingUp'
        Set-TransactionStatus -Transaction $Transaction -Status 'BackingUp' -Detail "Backup pre-apply de $($Step.TweakId)."
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP-HANDLER BEFORE"
        try {
            $preBackup = & $BackupHandler $Step.Tweak $Step.Level $Context $Step
        } catch {
            $Step.Status = 'Failed'
            $Step.Error = "Backup pre-apply falhou: $($_.Exception.Message)"
            $Step.CompletedAt = (Get-Date -Format 'o')
            $Transaction.Failure = [PSCustomObject]@{ TweakId=$Step.TweakId; Sequence=$Step.Sequence; At=(Get-Date -Format 'o'); Error=$Step.Error; Warning=$null }
            Save-Transaction -Transaction $Transaction
            Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP-HANDLER ERROR: $($Step.Error)"
            return [PSCustomObject]@{ Success=$false; Changed=$false; StateBefore=$null; StateAfter=$null; Verification=$null; Restart='None'; Warning=$null; Error=$Step.Error }
        }
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP-HANDLER AFTER"
        if ($null -eq $preBackup) {
            $Step.Status = 'Failed'
            $Step.Error = 'Backup pre-apply retornou null; Apply bloqueado para preservar rollback.'
            $Step.CompletedAt = (Get-Date -Format 'o')
            $Transaction.Failure = [PSCustomObject]@{ TweakId=$Step.TweakId; Sequence=$Step.Sequence; At=(Get-Date -Format 'o'); Error=$Step.Error; Warning=$null }
            Save-Transaction -Transaction $Transaction
            Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP NULL - APPLY BLOCKED"
            return [PSCustomObject]@{ Success=$false; Changed=$false; StateBefore=$null; StateAfter=$null; Verification=$null; Restart='None'; Warning=$null; Error=$Step.Error }
        }
    }

    if ($null -ne $preBackup) {
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP PERSIST BEFORE"
        Save-TransactionBackup -Transaction $Transaction -Step $Step -BackupData $preBackup
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / BACKUP PERSIST AFTER"
    }

    $Step.Status = 'Applying'
    $Step.StartedAt = (Get-Date -Format 'o')
    # A partir daqui um crash pode ter ocorrido durante uma mutacao; recovery deve
    # permanecer marcado ate Commit/Rollback.
    $Transaction.Recovery.Required = $true
    $Transaction.Recovery.LastKnownStep = $Step.Sequence
    Set-TransactionStatus -Transaction $Transaction -Status 'Applying' -Detail "Aplicando $($Step.TweakId)."

    $result = $null
    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / APPLY BEFORE"
    try {
        $result = & $ApplyHandler $Step.Tweak $Step.Level $Context
    } catch {
        $result = [PSCustomObject]@{ Success=$false; Changed=$false; StateBefore=$null; StateAfter=$null; Verification=$null; Restart='None'; Warning=$null; Error=$_.Exception.Message }
    }
    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / APPLY AFTER"

    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / RESULT COPY BEFORE"
    $Step.ApplyResult = Copy-TransactionObject -InputObject $result
    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / RESULT COPY AFTER"

    $Step.Changed = [bool]$result.Changed
    if ($result.PSObject.Properties.Name -contains 'StateBefore') { $Step.StateBefore = Copy-TransactionObject -InputObject $result.StateBefore }
    if ($result.PSObject.Properties.Name -contains 'StateAfter') { $Step.StateAfter = Copy-TransactionObject -InputObject $result.StateAfter }
    if ($result.PSObject.Properties.Name -contains 'Verification') { $Step.VerifyResult = Copy-TransactionObject -InputObject $result.Verification }
    if ($result.PSObject.Properties.Name -contains 'Restart' -and $result.Restart) { $Step.Restart = [string]$result.Restart }
    if ($result.PSObject.Properties.Name -contains 'Warning') { $Step.Warning = $result.Warning }
    if ($result.PSObject.Properties.Name -contains 'Error') { $Step.Error = $result.Error }

    # Compatibilidade: se nao havia BackupHandler, ainda aceitamos StateBefore do
    # Provider/Engine. Para integracao real da Fase 3.1 o modo recomendado e pre-backup.
    if ($null -eq $Step.BackupData) {
        $backup = $null
        if ($null -ne $Step.StateBefore) { $backup = $Step.StateBefore }
        if ($null -eq $backup) { $backup = Get-EngineRollbackBackup -TweakId $Step.TweakId }
        if ($null -ne $backup) {
            Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / FALLBACK BACKUP BEFORE"
            Save-TransactionBackup -Transaction $Transaction -Step $Step -BackupData $backup
            Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / FALLBACK BACKUP AFTER"
        }
    }

    $ok = Test-TransactionApplyResult -Result $result
    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / VERIFY RESULT=$ok CHANGED=$($Step.Changed)"
    if ($ok) {
        $Step.Status = if ($Step.Changed) { 'Verified' } else { 'NoChange' }
        $Step.CompletedAt = (Get-Date -Format 'o')
        if ($Step.Changed) { $Step.RollbackStatus = 'Pending' }
        if ($Step.Restart -and $Step.Restart -ne 'None') {
            $Transaction.RestartRequired = $true
            if ($Transaction.RestartScopes -notcontains $Step.Restart) { $Transaction.RestartScopes += $Step.Restart }
        }
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / SAVE VERIFIED BEFORE"
        Save-Transaction -Transaction $Transaction
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / SAVE VERIFIED AFTER"
        Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / COMPLETE $($Step.Status)"
        return $result
    }

    $Step.Status = 'Failed'
    $Step.CompletedAt = (Get-Date -Format 'o')
    $Transaction.Failure = [PSCustomObject]@{ TweakId=$Step.TweakId; Sequence=$Step.Sequence; At=(Get-Date -Format 'o'); Error=$Step.Error; Warning=$Step.Warning }
    Save-Transaction -Transaction $Transaction
    Write-TransactionTrace -Transaction $Transaction -Message "STEP $($Step.Sequence) $($Step.TweakId) / FAILED"
    return $result
}

function Invoke-TransactionRollback {
    param(
        [Parameter(Mandatory)] $Transaction,
        $Context = $null,
        [scriptblock]$UndoHandler
    )
    if (-not $UndoHandler) {
        $UndoHandler = {
            param($Tweak, $Level, $Context, $BackupData, $Step)
            if ($null -ne $BackupData) { Set-EngineRollbackBackup -TweakId $Step.TweakId -BackupData $BackupData }
            Invoke-Tweak -Tweak $Tweak -Action 'Undo' -Level $Level -Context $Context -StrictVerify
        }
    }

    Set-TransactionStatus -Transaction $Transaction -Status 'RollingBack' -Detail 'Rollback LIFO iniciado.' -Force
    Write-TransactionLog "[TRANSAÇÃO $($Transaction.Id)] Rollback LIFO iniciado." 'WARN'
    $recoveryWasRequired = [bool]$Transaction.Recovery.Required
    $candidates = @($Transaction.Steps | Where-Object { $_.Changed -and $_.RollbackStatus -ne 'RolledBack' } | Sort-Object Sequence -Descending)

    # R11: recovery pendente nunca pode virar RolledBack com zero candidatos.
    # Esse era o falso positivo do TEST 05 na R10 quando operations.json foi
    # importado como wrapper {value,Count}.
    if ($recoveryWasRequired -and $candidates.Count -eq 0) {
        $Transaction.Recovery.Required = $true
        Set-TransactionStatus -Transaction $Transaction -Status 'RollbackFailed' -Detail 'Recovery exigia rollback, mas nenhum passo alterado valido foi reidratado.' -Force
        Save-TransactionResult -Transaction $Transaction
        return $false
    }

    $failed = 0
    foreach ($step in $candidates) {
        $step.RollbackStatus = 'RollingBack'
        Save-Transaction -Transaction $Transaction
        $undo = $null
        try {
            if ($null -eq $step.BackupData) {
                throw "BackupData ausente para rollback do passo '$($step.TweakId)'."
            }
            $undo = & $UndoHandler $step.Tweak $step.Level $Context $step.BackupData $step
        } catch {
            $undo = [PSCustomObject]@{ Success=$false; Changed=$false; Verification=$null; Warning=$null; Error=$_.Exception.Message }
        }
        $step.UndoResult = Copy-TransactionObject $undo
        $undoOk = Test-TransactionApplyResult -Result $undo
        if ($undoOk) {
            $step.RollbackStatus = 'RolledBack'
            $step.Status = 'RolledBack'
            Write-TransactionLog "[TRANSAÇÃO $($Transaction.Id)] $($step.TweakId) revertido e verificado." 'OK'
        } else {
            $failed++
            $step.RollbackStatus = 'RollbackFailed'
            $step.Status = 'RollbackFailed'
            Write-TransactionLog "[TRANSAÇÃO $($Transaction.Id)] FALHA no rollback de $($step.TweakId)." 'ERROR'
        }
        Save-Transaction -Transaction $Transaction
    }

    $Transaction.Recovery.Required = ($failed -gt 0)
    if ($failed -eq 0) {
        Set-TransactionStatus -Transaction $Transaction -Status 'RolledBack' -Detail 'Todos os passos alterados foram restaurados.' -Force
    } elseif ($failed -lt $candidates.Count) {
        Set-TransactionStatus -Transaction $Transaction -Status 'PartiallyRolledBack' -Detail "$failed rollback(s) falharam." -Force
    } else {
        Set-TransactionStatus -Transaction $Transaction -Status 'RollbackFailed' -Detail 'Nenhum passo alterado pôde ser restaurado.' -Force
    }
    Save-TransactionResult -Transaction $Transaction
    return ($failed -eq 0)
}

function Save-TransactionResult {
    param([Parameter(Mandatory)] $Transaction)
    if (-not $Transaction.Persist) { return }
    $result = [PSCustomObject]@{
        TransactionId   = $Transaction.Id
        Status          = $Transaction.Status
        CreatedAt       = $Transaction.CreatedAt
        CompletedAt     = $Transaction.CompletedAt
        RestartRequired = $Transaction.RestartRequired
        RestartScopes   = @($Transaction.RestartScopes)
        Failure         = $Transaction.Failure
        Summary         = [PSCustomObject]@{
            Total          = @($Transaction.Steps).Count
            Verified       = @($Transaction.Steps | Where-Object { $_.Status -eq 'Verified' }).Count
            NoChange       = @($Transaction.Steps | Where-Object { $_.Status -eq 'NoChange' }).Count
            Failed         = @($Transaction.Steps | Where-Object { $_.Status -eq 'Failed' }).Count
            RolledBack     = @($Transaction.Steps | Where-Object { $_.RollbackStatus -eq 'RolledBack' }).Count
            RollbackFailed = @($Transaction.Steps | Where-Object { $_.RollbackStatus -eq 'RollbackFailed' }).Count
        }
    }
    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / result.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'result.json') -Data $result
    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / result.json AFTER'

    # R7: os estados completos nao sao reserializados aqui. O estado original
    # autoritativo ja vive nos arquivos de backup imutaveis por Step.
    $before = Get-TransactionStateBeforePersistenceSnapshot -Transaction $Transaction
    $after = Get-TransactionStateAfterPersistenceSnapshot -Transaction $Transaction

    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / state-before.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'state-before.json') -Data $before
    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / state-before.json AFTER'

    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / state-after.json BEFORE'
    Write-JsonAtomic -Path (Join-Path $Transaction.TransactionPath 'state-after.json') -Data $after
    Write-TransactionTrace -Transaction $Transaction -Message 'RESULT / state-after.json AFTER'
}

function Invoke-TransactionPlan {
    param(
        [Parameter(Mandatory)] $Items,
        $Context = $null,
        [ValidateSet('RollbackTransaction', 'Stop', 'Continue')] [string]$FailurePolicy = 'RollbackTransaction',
        [string]$RootPath,
        [string]$BackupRootPath,
        [scriptblock]$ApplyHandler,
        [scriptblock]$BackupHandler,
        [scriptblock]$UndoHandler,
        [scriptblock]$OnProgress,
        [switch]$NoPersist
    )
    $lock = $null
    try {
        if (-not $NoPersist) { $lock = Enter-WinSlimTransactionLock -RootPath $RootPath }
        $plan = @()
        foreach ($item in @($Items)) {
            $t = if ($item.PSObject.Properties.Name -contains 'Tweak') { $item.Tweak } else { $item }
            $lvl = if ($item.PSObject.Properties.Name -contains 'Level') { [int]$item.Level } else { -1 }
            $tid = if ($t.PSObject.Properties.Name -contains 'id') { [string]$t.id } else { [string]$t.Id }
            $plan += [PSCustomObject]@{ Sequence=@($plan).Count+1; TweakId=$tid; Level=$lvl }
        }
        $tx = New-Transaction -Mode Apply -FailurePolicy $FailurePolicy -RootPath $RootPath -BackupRootPath $BackupRootPath -Plan $plan -NoPersist:$NoPersist
        Set-TransactionPlan -Transaction $tx -Plan $plan
        $total = @($Items).Count
        $index = 0
        $hadFailure = $false
        foreach ($item in @($Items)) {
            $index++
            $t = if ($item.PSObject.Properties.Name -contains 'Tweak') { $item.Tweak } else { $item }
            $lvl = if ($item.PSObject.Properties.Name -contains 'Level') { [int]$item.Level } else { -1 }
            $step = Add-TransactionStep -Transaction $tx -Tweak $t -Level $lvl
            $r = Invoke-TransactionStep -Transaction $tx -Step $step -Context $Context -ApplyHandler $ApplyHandler -BackupHandler $BackupHandler
            if ($OnProgress) { & $OnProgress $index $total $step $r $tx }
            if (-not (Test-TransactionApplyResult -Result $r)) {
                $hadFailure = $true
                Set-TransactionStatus -Transaction $tx -Status 'Failed' -Detail "Falha em $($step.TweakId)." -Force
                if ($FailurePolicy -eq 'RollbackTransaction') {
                    [void](Invoke-TransactionRollback -Transaction $tx -Context $Context -UndoHandler $UndoHandler)
                    return $tx
                }
                if ($FailurePolicy -eq 'Stop') {
                    $tx.Recovery.Required = (@($tx.Steps | Where-Object { $_.Changed -and $_.RollbackStatus -ne 'RolledBack' }).Count -gt 0)
                    Save-Transaction -Transaction $tx
                    Save-TransactionResult -Transaction $tx
                    return $tx
                }
            }
        }
        Set-TransactionStatus -Transaction $tx -Status 'Applied' -Detail 'Todas as operacoes foram processadas.' -Force
        $tx.Recovery.Required = $false
        if ($hadFailure -and $FailurePolicy -eq 'Continue') {
            Set-TransactionStatus -Transaction $tx -Status 'CommittedWithErrors' -Detail 'Transacao concluida com uma ou mais falhas aceitas pela policy Continue.' -Force
        } else {
            Set-TransactionStatus -Transaction $tx -Status 'Committed' -Detail 'Transacao confirmada.' -Force
        }
        Save-TransactionResult -Transaction $tx
        return $tx
    } catch {
        if ($tx) {
            $tx.Failure = [PSCustomObject]@{ TweakId=$null; Sequence=$null; At=(Get-Date -Format 'o'); Error=$_.Exception.Message; Warning=$null }
            try { Set-TransactionStatus -Transaction $tx -Status 'Interrupted' -Detail $_.Exception.Message -Force } catch { }
            $tx.Recovery.Required = $true
            try { Save-Transaction -Transaction $tx; Save-TransactionResult -Transaction $tx } catch { }
        }
        throw
    } finally {
        if ($lock) { Exit-WinSlimTransactionLock }
    }
}

function ConvertFrom-TransactionJournalCollection {
    <#
      R11: aceita arrays JSON normais e reconhece o wrapper legado {value,Count}
      produzido pelas revisoes R5-R10. O wrapper e apenas compatibilidade; novos
      journals R11 sempre sao arrays JSON top-level.
    #>
    param($Data)
    if ($null -eq $Data) { return @() }

    $names = @($Data.PSObject.Properties.Name)
    if (($names -contains 'value') -and ($names -contains 'Count') -and
        ($names -notcontains 'TweakId') -and ($names -notcontains 'Sequence')) {
        return @($Data.value)
    }
    return @($Data)
}

function Import-WinSlimTransaction {
    param([Parameter(Mandatory)] [string]$Path)
    $file = if ((Test-Path -LiteralPath $Path -PathType Container)) { Join-Path $Path 'transaction.json' } else { $Path }
    if (-not (Test-Path -LiteralPath $file)) { throw "transaction.json nao encontrado: $file" }

    $tx = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    $dir = Split-Path -Parent $file
    $planFile = Join-Path $dir 'plan.json'
    $opsFile = Join-Path $dir 'operations.json'

    # R3: transaction.json e metadata-only. Para compatibilidade com snapshots R2,
    # use os campos embutidos se existirem; caso contrario carregue os sidecars.
    if ($tx.PSObject.Properties.Name -contains 'Plan' -and $null -ne $tx.Plan) {
        $tx.Plan = @($tx.Plan)
    } elseif (Test-Path -LiteralPath $planFile) {
        $planData = Get-Content -LiteralPath $planFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $planItems = @(ConvertFrom-TransactionJournalCollection -Data $planData)
        Add-Member -InputObject $tx -NotePropertyName Plan -NotePropertyValue $planItems -Force
    } else {
        Add-Member -InputObject $tx -NotePropertyName Plan -NotePropertyValue @() -Force
    }

    if ($tx.PSObject.Properties.Name -contains 'Steps' -and $null -ne $tx.Steps) {
        $loadedSteps = @($tx.Steps)
    } elseif (Test-Path -LiteralPath $opsFile) {
        $opsData = Get-Content -LiteralPath $opsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $loadedSteps = @(ConvertFrom-TransactionJournalCollection -Data $opsData)
    } else {
        $loadedSteps = @()
    }

    $hydratedSteps = @()
    foreach ($step in @($loadedSteps)) {
        if ($null -eq $step -or
            $step.PSObject.Properties.Name -notcontains 'TweakId' -or
            [string]::IsNullOrWhiteSpace([string]$step.TweakId) -or
            $step.PSObject.Properties.Name -notcontains 'Sequence' -or
            [int]$step.Sequence -le 0) {
            throw "operations.json invalido/corrompido em '$opsFile': passo sem Sequence/TweakId valido."
        }
        $hydratedSteps += ,(Restore-TransactionStepRuntimeFields -Step $step)
    }
    Add-Member -InputObject $tx -NotePropertyName Steps -NotePropertyValue $hydratedSteps -Force

    $tx.StatusHistory = @($tx.StatusHistory)
    $tx.RestartScopes = @($tx.RestartScopes)
    return $tx
}

function Get-WinSlimIncompleteTransactions {
    param([string]$RootPath)
    $root = Get-WinSlimTransactionRoot -RootPath $RootPath
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $out = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $file = Join-Path $dir.FullName 'transaction.json'
        if (-not (Test-Path -LiteralPath $file)) { continue }
        try {
            $tx = Import-WinSlimTransaction -Path $file
            if ($script:TransactionTerminalStates -notcontains [string]$tx.Status -or [bool]$tx.Recovery.Required) { $out += $tx }
        } catch { }
    }
    return @($out)
}

function Invoke-WinSlimTransactionRecovery {
    param(
        [Parameter(Mandatory)] [string]$Path,
        $Context = $null,
        [scriptblock]$UndoHandler,
        [string]$RootPath
    )
    $lock = $null
    try {
        $lock = Enter-WinSlimTransactionLock -RootPath $RootPath
        $tx = Import-WinSlimTransaction -Path $Path
        if ($tx.Status -eq 'Committed' -and -not [bool]$tx.Recovery.Required) {
            throw "Transacao '$($tx.Id)' ja esta committed e nao requer recovery."
        }
        Set-TransactionStatus -Transaction $tx -Status 'RecoveryRequired' -Detail 'Recovery manual iniciado.' -Force
        [void](Invoke-TransactionRollback -Transaction $tx -Context $Context -UndoHandler $UndoHandler)
        return $tx
    } finally {
        if ($lock) { Exit-WinSlimTransactionLock }
    }
}
