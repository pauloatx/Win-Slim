<#
    Win-Slim Suite - Catalog Runtime (FASE 6.5 R1)

    Runtime puro e indexado para o catalogo validado.
    Objetivos:
    - materializar o catalogo uma unica vez;
    - oferecer lookup O(1) por TweakId;
    - precomputar dependencies/dependents/conflicts/mutex/risk/position;
    - reduzir scans repetidos em hot paths da camada de presets;
    - preservar compatibilidade com Windows PowerShell 5.1.

    REGRA: este modulo NAO altera Windows e NAO executa Providers.
#>

$script:WinSlimCatalogRuntimeSchemaVersion = 1

function Get-WinSlimRuntimeProperty {
    param($InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        try { if ($InputObject.Contains($Name)) { return $InputObject[$Name] } } catch { }
        try { if ($InputObject.ContainsKey($Name)) { return $InputObject[$Name] } } catch { }
    }
    try {
        $p = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    } catch { }
    return $Default
}

function Test-WinSlimRuntimeMapKey {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $false }
    try { return [bool]$Map.ContainsKey($Key) } catch { }
    try { return [bool]$Map.Contains($Key) } catch { }
    return $false
}

function Get-WinSlimRuntimeTweakId {
    param($Tweak)
    if ($null -eq $Tweak) { return $null }
    $id = [string](Get-WinSlimRuntimeProperty $Tweak 'id' '')
    if ([string]::IsNullOrWhiteSpace($id)) { $id = [string](Get-WinSlimRuntimeProperty $Tweak 'Id' '') }
    if ([string]::IsNullOrWhiteSpace($id)) { return $null }
    return $id.Trim()
}

function Get-WinSlimRuntimeFingerprint {
    param([string[]]$Tokens)
    $canonical = (@($Tokens) -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function New-WinSlimCatalogRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CatalogTweaks)

    $catalog = @($CatalogTweaks)
    $ids = New-Object System.Collections.ArrayList
    $byId = @{}
    $position = @{}
    $dependenciesById = @{}
    $dependentsById = @{}
    $conflictsById = @{}
    $mutexGroups = @{}
    $riskById = @{}
    $windowsById = @{}
    $issues = New-Object System.Collections.ArrayList

    $ordinal = 0
    foreach ($tweak in $catalog) {
        $id = Get-WinSlimRuntimeTweakId $tweak
        if (-not $id) {
            [void]$issues.Add([PSCustomObject]@{
                Severity='Error'; Code='MissingId'; TweakId=$null; Reference=$null
                Message="Entrada de catalogo na posicao $ordinal nao possui id."
            })
            $ordinal++
            continue
        }
        if (Test-WinSlimRuntimeMapKey $byId $id) {
            [void]$issues.Add([PSCustomObject]@{
                Severity='Error'; Code='DuplicateId'; TweakId=$id; Reference=$null
                Message="ID duplicado no catalogo: $id"
            })
            $ordinal++
            continue
        }
        $byId[$id] = $tweak
        $position[$id] = $ordinal
        [void]$ids.Add($id)
        $riskById[$id] = [string](Get-WinSlimRuntimeProperty $tweak 'risk' '')
        $windowsById[$id] = @(Get-WinSlimRuntimeProperty $tweak 'windowsVersion' @())
        $ordinal++
    }

    $dependencyEdges = 0
    $conflictEdges = 0
    foreach ($id in @($ids.ToArray())) {
        $tweak = $byId[$id]

        $deps = New-Object System.Collections.ArrayList
        $depSeen = @{}
        foreach ($dep0 in @(Get-WinSlimRuntimeProperty $tweak 'dependencies' @())) {
            $dep = ([string]$dep0).Trim()
            if (-not $dep -or (Test-WinSlimRuntimeMapKey $depSeen $dep)) { continue }
            $depSeen[$dep] = $true
            [void]$deps.Add($dep)
            $dependencyEdges++
            if (-not (Test-WinSlimRuntimeMapKey $byId $dep)) {
                [void]$issues.Add([PSCustomObject]@{
                    Severity='Error'; Code='MissingDependencyReference'; TweakId=$id; Reference=$dep
                    Message="Dependencia '$dep' de '$id' nao existe no catalogo."
                })
            }
            if (-not (Test-WinSlimRuntimeMapKey $dependentsById $dep)) {
                $dependentsById[$dep] = New-Object System.Collections.ArrayList
            }
            $list = $dependentsById[$dep]
            if (-not (@($list) -contains $id)) { [void]$list.Add($id) }
        }
        $dependenciesById[$id] = [object[]]$deps.ToArray()

        $conf = New-Object System.Collections.ArrayList
        $confSeen = @{}
        foreach ($other0 in @(Get-WinSlimRuntimeProperty $tweak 'conflicts' @())) {
            $other = ([string]$other0).Trim()
            if (-not $other -or (Test-WinSlimRuntimeMapKey $confSeen $other)) { continue }
            $confSeen[$other] = $true
            [void]$conf.Add($other)
            $conflictEdges++
            if (-not (Test-WinSlimRuntimeMapKey $byId $other)) {
                [void]$issues.Add([PSCustomObject]@{
                    Severity='Warning'; Code='MissingConflictReference'; TweakId=$id; Reference=$other
                    Message="Conflito '$other' de '$id' nao existe no catalogo."
                })
            }
        }
        $conflictsById[$id] = [object[]]$conf.ToArray()

        $group = [string](Get-WinSlimRuntimeProperty $tweak 'mutexGroup' '')
        if (-not [string]::IsNullOrWhiteSpace($group)) {
            if (-not (Test-WinSlimRuntimeMapKey $mutexGroups $group)) {
                $mutexGroups[$group] = New-Object System.Collections.ArrayList
            }
            [void]$mutexGroups[$group].Add($id)
        }
    }

    foreach ($id in @($ids.ToArray())) {
        if (-not (Test-WinSlimRuntimeMapKey $dependentsById $id)) {
            $dependentsById[$id] = @()
        } elseif ($dependentsById[$id] -is [System.Collections.ArrayList]) {
            $dependentsById[$id] = [object[]]$dependentsById[$id].ToArray()
        }
    }
    foreach ($group in @($mutexGroups.Keys)) {
        if ($mutexGroups[$group] -is [System.Collections.ArrayList]) {
            $mutexGroups[$group] = [object[]]$mutexGroups[$group].ToArray()
        }
    }

    $errorCount = 0
    $warningCount = 0
    foreach ($issue in @($issues.ToArray())) {
        if ([string]$issue.Severity -eq 'Error') { $errorCount++ }
        elseif ([string]$issue.Severity -eq 'Warning') { $warningCount++ }
    }

    $tokens = New-Object System.Collections.ArrayList
    [void]$tokens.Add("schema=$script:WinSlimCatalogRuntimeSchemaVersion")
    foreach ($id in @($ids.ToArray())) {
        [void]$tokens.Add("id=$id")
        [void]$tokens.Add("risk=${id}:$($riskById[$id])")
        [void]$tokens.Add("deps=${id}:$(@($dependenciesById[$id]) -join ',')")
        [void]$tokens.Add("conf=${id}:$(@($conflictsById[$id]) -join ',')")
        $group = [string](Get-WinSlimRuntimeProperty $byId[$id] 'mutexGroup' '')
        [void]$tokens.Add("mutex=${id}:$group")
        [void]$tokens.Add("win=${id}:$(@($windowsById[$id]) -join ',')")
    }
    $fingerprint = Get-WinSlimRuntimeFingerprint -Tokens ([string[]]$tokens.ToArray())

    return [PSCustomObject]@{
        SchemaVersion = $script:WinSlimCatalogRuntimeSchemaVersion
        Fingerprint = $fingerprint
        Count = $ids.Count
        Tweaks = @($catalog)
        Ids = [object[]]$ids.ToArray()
        ById = $byId
        Position = $position
        DependenciesById = $dependenciesById
        DependentsById = $dependentsById
        ConflictsById = $conflictsById
        MutexGroups = $mutexGroups
        RiskById = $riskById
        WindowsById = $windowsById
        Valid = ($errorCount -eq 0)
        Issues = [object[]]$issues.ToArray()
        Stats = [PSCustomObject]@{
            Tweaks = $ids.Count
            DependencyEdges = $dependencyEdges
            ConflictEdges = $conflictEdges
            MutexGroups = $mutexGroups.Count
            Errors = $errorCount
            Warnings = $warningCount
        }
    }
}

function Get-WinSlimRuntimeTweak {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CatalogRuntime,
        [Parameter(Mandatory)][string]$TweakId
    )
    if (-not [bool](Get-WinSlimRuntimeProperty $CatalogRuntime 'Valid' $false)) {
        throw 'CatalogRuntime invalido.'
    }
    $map = Get-WinSlimRuntimeProperty $CatalogRuntime 'ById' $null
    if (-not (Test-WinSlimRuntimeMapKey $map $TweakId)) { return $null }
    return $map[$TweakId]
}
