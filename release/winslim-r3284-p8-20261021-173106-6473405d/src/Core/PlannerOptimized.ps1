<#
    Win-Slim Suite - Planner Optimized Runtime (FASE 6.5 R2)

    Shadow implementation used to validate the structural/performance refactor
    before promoting it over Planner.ps1.

    Goals:
    - reuse CatalogRuntime indexes instead of rebuilding catalog maps per plan;
    - eliminate repeated Where-Object/-notcontains scans from topology hot paths;
    - use stable Kahn ordering via System.Collections.SortedList;
    - use ArrayList/hash lookups instead of repeated array concatenation where useful;
    - preserve Planner R1 decisions, output shape and Fingerprint.

    IMPORTANT:
    - Planner.ps1 remains the authoritative legacy comparator in this subgate;
    - this module is pure and never mutates Windows;
    - Windows PowerShell 5.1 compatible.
#>

$script:WinSlimPlannerRuntimeSchemaVersion = 2

function Get-WinSlimPlannerR2Property {
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

function Test-WinSlimPlannerR2MapKey {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $false }
    try { return [bool]$Map.ContainsKey($Key) } catch { }
    try { return [bool]$Map.Contains($Key) } catch { }
    return $false
}

function New-WinSlimPlannerRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CatalogRuntime)

    if ($null -eq (Get-Command Get-WinSlimPlannerTweakId -ErrorAction SilentlyContinue)) {
        throw 'Planner.ps1 deve estar carregado antes de PlannerOptimized.ps1.'
    }

    $ids = @(Get-WinSlimPlannerR2Property $CatalogRuntime 'Ids' @())
    $byId = Get-WinSlimPlannerR2Property $CatalogRuntime 'ById' $null
    if ($null -eq $byId) { throw 'CatalogRuntime.ById ausente.' }

    $typeById = @{}
    $levelsCountById = @{}
    $mutexById = @{}
    $requiresRestartById = @{}
    $restartScopeById = @{}

    foreach ($id0 in $ids) {
        $id = [string]$id0
        $t = $byId[$id]
        $typeById[$id] = [string](Get-WinSlimPlannerR2Property $t 'type' '')
        $levelsCountById[$id] = @(Get-WinSlimPlannerR2Property $t 'levels' @()).Count
        $mutexById[$id] = [string](Get-WinSlimPlannerR2Property $t 'mutexGroup' '')
        $requiresRestartById[$id] = [bool](Get-WinSlimPlannerR2Property $t 'requiresRestart' $false)
        $restartScopeById[$id] = [string](Get-WinSlimPlannerR2Property $t 'restartScope' 'None')
    }

    return [PSCustomObject]@{
        SchemaVersion = $script:WinSlimPlannerRuntimeSchemaVersion
        CatalogRuntime = $CatalogRuntime
        CatalogFingerprint = [string](Get-WinSlimPlannerR2Property $CatalogRuntime 'Fingerprint' '')
        Count = $ids.Count
        TypeById = $typeById
        LevelsCountById = $levelsCountById
        MutexById = $mutexById
        RequiresRestartById = $requiresRestartById
        RestartScopeById = $restartScopeById
    }
}

function New-WinSlimExecutionPlanOptimized {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PlannerRuntime,
        [string[]]$SelectedIds = @(),
        $LevelSelections = $null,
        $Context = $null,
        [string]$PresetName,
        [ValidateSet('Block','PreferFirst')][string]$ConflictPolicy = 'Block',
        [switch]$SkipApplicabilityChecks
    )

    $catalogRuntime = Get-WinSlimPlannerR2Property $PlannerRuntime 'CatalogRuntime' $null
    if ($null -eq $catalogRuntime) { throw 'PlannerRuntime.CatalogRuntime ausente.' }

    $catalog = @(Get-WinSlimPlannerR2Property $catalogRuntime 'Tweaks' @())
    $allCatalogIds = @(Get-WinSlimPlannerR2Property $catalogRuntime 'Ids' @())
    $index = Get-WinSlimPlannerR2Property $catalogRuntime 'ById' $null
    $position = Get-WinSlimPlannerR2Property $catalogRuntime 'Position' $null
    $runtimeDeps = Get-WinSlimPlannerR2Property $catalogRuntime 'DependenciesById' $null
    $runtimeDependents = Get-WinSlimPlannerR2Property $catalogRuntime 'DependentsById' $null
    $runtimeConflicts = Get-WinSlimPlannerR2Property $catalogRuntime 'ConflictsById' $null

    $typeById = Get-WinSlimPlannerR2Property $PlannerRuntime 'TypeById' @{}
    $levelsCountById = Get-WinSlimPlannerR2Property $PlannerRuntime 'LevelsCountById' @{}
    $mutexById = Get-WinSlimPlannerR2Property $PlannerRuntime 'MutexById' @{}
    $requiresRestartById = Get-WinSlimPlannerR2Property $PlannerRuntime 'RequiresRestartById' @{}
    $restartScopeById = Get-WinSlimPlannerR2Property $PlannerRuntime 'RestartScopeById' @{}

    $levelMap = @{}
    if ($LevelSelections) {
        if ($LevelSelections -is [System.Collections.IDictionary]) {
            foreach ($k in @($LevelSelections.Keys)) { $levelMap[[string]$k] = [int]$LevelSelections[$k] }
        } else {
            foreach ($p in @($LevelSelections.PSObject.Properties)) {
                if ($p.MemberType -eq 'NoteProperty') { $levelMap[$p.Name] = [int]$p.Value }
            }
        }
    }

    $rootSource = @{}
    $rootSet = @{}
    foreach ($id0 in @($SelectedIds)) {
        $id = ([string]$id0).Trim()
        if (-not $id) { continue }
        $rootSet[$id] = $true
        $rootSource[$id] = 'Selected'
    }

    if ($PresetName) {
        $preset = Get-WinSlimPresetSelection -CatalogTweaks $catalog -PresetName $PresetName
        foreach ($id0 in @($preset.SelectedIds)) {
            $id = [string]$id0
            $rootSet[$id] = $true
            if (-not (Test-WinSlimPlannerR2MapKey $rootSource $id)) { $rootSource[$id] = 'Preset' }
        }
        foreach ($k in @($preset.LevelSelections.Keys)) {
            if (-not (Test-WinSlimPlannerR2MapKey $levelMap ([string]$k))) { $levelMap[[string]$k] = [int]$preset.LevelSelections[$k] }
        }
    }

    foreach ($k0 in @($levelMap.Keys)) {
        $k = [string]$k0
        if ([int]$levelMap[$k] -gt 0) {
            $rootSet[$k] = $true
            if (-not (Test-WinSlimPlannerR2MapKey $rootSource $k)) { $rootSource[$k] = 'LevelSelection' }
        }
    }

    $rootsKnownList = New-Object System.Collections.ArrayList
    foreach ($id0 in $allCatalogIds) {
        $id = [string]$id0
        if (Test-WinSlimPlannerR2MapKey $rootSet $id) { [void]$rootsKnownList.Add($id) }
    }
    $rootsKnown = [object[]]$rootsKnownList.ToArray()

    $rootsUnknownList = New-Object System.Collections.ArrayList
    foreach ($id0 in @($rootSet.Keys)) {
        $id = [string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $index $id)) { [void]$rootsUnknownList.Add($id) }
    }
    $rootsUnknown = @($rootsUnknownList.ToArray() | Sort-Object)

    $blockedMap = @{}
    $skippedMap = @{}
    $warningsList = New-Object System.Collections.ArrayList
    $conflictsList = New-Object System.Collections.ArrayList
    $mutexDecisionsList = New-Object System.Collections.ArrayList

    # Map only the catalog issues that New-WinSlimExecutionPlan historically emitted.
    foreach ($issue in @(Get-WinSlimPlannerR2Property $catalogRuntime 'Issues' @())) {
        $code = [string](Get-WinSlimPlannerR2Property $issue 'Code' '')
        $tid = [string](Get-WinSlimPlannerR2Property $issue 'TweakId' '')
        if ($code -eq 'MissingId') {
            [void]$warningsList.Add([PSCustomObject]@{ Code='MissingCatalogId'; TweakId=$null; Message=[string](Get-WinSlimPlannerR2Property $issue 'Message' 'Entrada de catalogo sem id.') })
        } elseif ($code -eq 'DuplicateId' -and $tid) {
            $blockedMap[$tid] = [PSCustomObject]@{ TweakId=$tid; ReasonCode='DuplicateCatalogId'; Reason="ID duplicado no catalogo: $tid"; Source='Catalog' }
        }
    }

    foreach ($id0 in $rootsUnknown) {
        $id = [string]$id0
        $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='UnknownTweak'; Reason="Tweak '$id' nao existe no catalogo."; Source='Selection' }
    }

    # Dependency expansion using precomputed O(1) maps.
    $candidateMap = @{}
    $sourceMap = @{}
    $depsById = @{}
    $queue = New-Object System.Collections.ArrayList
    foreach ($id0 in $rootsKnown) {
        $id = [string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $candidateMap $id)) {
            $candidateMap[$id] = $true
            $sourceMap[$id] = $rootSource[$id]
            [void]$queue.Add($id)
        }
    }

    for ($qi=0; $qi -lt $queue.Count; $qi++) {
        $id = [string]$queue[$qi]
        $deps = @(if (Test-WinSlimPlannerR2MapKey $runtimeDeps $id) { $runtimeDeps[$id] } else { @() })
        $depsById[$id] = @($deps)
        foreach ($d0 in $deps) {
            $d = ([string]$d0).Trim()
            if (-not $d) { continue }
            if (-not (Test-WinSlimPlannerR2MapKey $index $d)) {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='MissingDependency'; Reason="Dependencia '$d' de '$id' nao existe no catalogo."; Source=$sourceMap[$id]; Dependency=$d }
                continue
            }
            if (-not (Test-WinSlimPlannerR2MapKey $candidateMap $d)) {
                $candidateMap[$d] = $true
                $sourceMap[$d] = 'Dependency'
                [void]$queue.Add($d)
            }
        }
    }
    foreach ($id0 in @($candidateMap.Keys)) {
        $id = [string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $depsById $id)) { $depsById[$id] = @() }
    }

    $candidateOrderedList = New-Object System.Collections.ArrayList
    foreach ($id0 in $allCatalogIds) {
        $id = [string]$id0
        if (Test-WinSlimPlannerR2MapKey $candidateMap $id) { [void]$candidateOrderedList.Add($id) }
    }
    $candidateOrdered = [object[]]$candidateOrderedList.ToArray()

    # Applicability and multilevel validation.
    $windowsApplicabilityList = New-Object System.Collections.ArrayList
    $hardwareApplicabilityList = New-Object System.Collections.ArrayList
    $adminApplicabilityList = New-Object System.Collections.ArrayList
    foreach ($id0 in $candidateOrdered) {
        $id = [string]$id0
        if (Test-WinSlimPlannerR2MapKey $blockedMap $id) { continue }
        $t = $index[$id]
        $app = Test-WinSlimTweakApplicability -Tweak $t -Context $Context -SkipApplicabilityChecks:$SkipApplicabilityChecks
        [void]$windowsApplicabilityList.Add([PSCustomObject]@{ TweakId=$id; Applicable=$app.Windows.Applicable; Reason=$app.Windows.Reason })
        [void]$hardwareApplicabilityList.Add([PSCustomObject]@{ TweakId=$id; Applicable=$app.Hardware.Applicable; Reason=$app.Hardware.Reason })
        [void]$adminApplicabilityList.Add([PSCustomObject]@{ TweakId=$id; Applicable=$app.Admin.Applicable; Reason=$app.Admin.Reason })

        if ($app.Decision -eq 'Skip') {
            $skippedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode=$app.ReasonCode; Reason=$app.Reason; Source=$sourceMap[$id] }
            continue
        }
        if ($app.Decision -eq 'Block') {
            $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode=$app.ReasonCode; Reason=$app.Reason; Source=$sourceMap[$id] }
            continue
        }

        if ([string]$typeById[$id] -eq 'multilevel') {
            $lvl = if (Test-WinSlimPlannerR2MapKey $levelMap $id) { [int]$levelMap[$id] } else { -1 }
            $levelsCount = [int]$levelsCountById[$id]
            if ($lvl -ge $levelsCount) {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='InvalidLevel'; Reason="Nivel $lvl fora do intervalo do tweak ($levelsCount niveis)."; Source=$sourceMap[$id] }
            }
        }
    }

    function Invoke-WinSlimPlannerR2DependencyPropagation {
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($id0 in $candidateOrdered) {
                $id = [string]$id0
                if ((Test-WinSlimPlannerR2MapKey $blockedMap $id) -or (Test-WinSlimPlannerR2MapKey $skippedMap $id)) { continue }
                foreach ($dep0 in @($depsById[$id])) {
                    $dep = [string]$dep0
                    if ((Test-WinSlimPlannerR2MapKey $blockedMap $dep) -or (Test-WinSlimPlannerR2MapKey $skippedMap $dep)) {
                        $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='DependencyUnavailable'; Reason="Dependencia '$dep' nao esta disponivel para execucao."; Source=$sourceMap[$id]; Dependency=$dep }
                        $changed = $true
                        break
                    }
                }
            }
        }
    }
    Invoke-WinSlimPlannerR2DependencyPropagation

    # Declared conflicts using precomputed conflict adjacency.
    $pairSeen = @{}
    foreach ($id0 in $candidateOrdered) {
        $id = [string]$id0
        if ((Test-WinSlimPlannerR2MapKey $blockedMap $id) -or (Test-WinSlimPlannerR2MapKey $skippedMap $id)) { continue }
        foreach ($other0 in @(if (Test-WinSlimPlannerR2MapKey $runtimeConflicts $id) { $runtimeConflicts[$id] } else { @() })) {
            $other = [string]$other0
            if (-not (Test-WinSlimPlannerR2MapKey $candidateMap $other)) { continue }
            if ((Test-WinSlimPlannerR2MapKey $blockedMap $other) -or (Test-WinSlimPlannerR2MapKey $skippedMap $other)) { continue }
            $a = $id; $b = $other
            if ([string]::Compare($a,$b,$true) -gt 0) { $tmp=$a; $a=$b; $b=$tmp }
            $key = "$a|$b"
            if (Test-WinSlimPlannerR2MapKey $pairSeen $key) { continue }
            $pairSeen[$key] = $true
            $winner=$null; $loser=$null; $decision='Blocked'
            if ($ConflictPolicy -eq 'PreferFirst') {
                if ([int]$position[$id] -le [int]$position[$other]) { $winner=$id; $loser=$other } else { $winner=$other; $loser=$id }
                $skippedMap[$loser] = [PSCustomObject]@{ TweakId=$loser; ReasonCode='ConflictLoser'; Reason="Conflita com '$winner'; PreferFirst manteve '$winner'."; Source=$sourceMap[$loser] }
                $decision='PreferFirst'
            } else {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='Conflict'; Reason="Conflita com '$other'."; Source=$sourceMap[$id]; ConflictWith=$other }
                $blockedMap[$other] = [PSCustomObject]@{ TweakId=$other; ReasonCode='Conflict'; Reason="Conflita com '$id'."; Source=$sourceMap[$other]; ConflictWith=$id }
            }
            [void]$conflictsList.Add([PSCustomObject]@{ Type='Conflict'; A=$id; B=$other; Policy=$ConflictPolicy; Decision=$decision; Winner=$winner; Loser=$loser })
        }
    }
    Invoke-WinSlimPlannerR2DependencyPropagation

    # Mutex groups. Candidate order is already catalog-stable.
    $groups = @{}
    foreach ($id0 in $candidateOrdered) {
        $id = [string]$id0
        if ((Test-WinSlimPlannerR2MapKey $blockedMap $id) -or (Test-WinSlimPlannerR2MapKey $skippedMap $id)) { continue }
        $g = [string]$mutexById[$id]
        if (-not $g) { continue }
        if (-not (Test-WinSlimPlannerR2MapKey $groups $g)) { $groups[$g] = New-Object System.Collections.ArrayList }
        [void]$groups[$g].Add($id)
    }
    foreach ($g0 in @($groups.Keys | Sort-Object)) {
        $g = [string]$g0
        $members = @($groups[$g].ToArray())
        if ($members.Count -lt 2) { continue }
        $winner=$null; $losers=@(); $decision='Blocked'
        if ($ConflictPolicy -eq 'PreferFirst') {
            $winner = [string]$members[0]
            if ($members.Count -gt 1) { $losers = @($members[1..($members.Count-1)]) }
            foreach ($loser0 in $losers) {
                $loser=[string]$loser0
                $skippedMap[$loser] = [PSCustomObject]@{ TweakId=$loser; ReasonCode='MutexLoser'; Reason="mutexGroup '$g' manteve '$winner'."; Source=$sourceMap[$loser] }
            }
            $decision='PreferFirst'
        } else {
            foreach ($m0 in $members) {
                $m=[string]$m0
                $blockedMap[$m] = [PSCustomObject]@{ TweakId=$m; ReasonCode='MutexConflict'; Reason="Mais de um tweak ativo no mutexGroup '$g'."; Source=$sourceMap[$m]; MutexGroup=$g }
            }
        }
        [void]$mutexDecisionsList.Add([PSCustomObject]@{ Group=$g; Candidates=@($members); Policy=$ConflictPolicy; Decision=$decision; Winner=$winner; Losers=@($losers) })
    }
    Invoke-WinSlimPlannerR2DependencyPropagation

    # Cycle detection reuses the validated DFS contract, with indexed dependencies.
    $activeMap = @{}
    foreach ($id0 in $candidateOrdered) {
        $id=[string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $blockedMap $id) -and -not (Test-WinSlimPlannerR2MapKey $skippedMap $id)) { $activeMap[$id]=$true }
    }
    $cycles = @(Find-WinSlimDependencyCycles -DependenciesById $depsById -ActiveMap $activeMap -OrderedIds ([string[]]$candidateOrdered))
    foreach ($cycle in $cycles) {
        foreach ($id0 in @($cycle.Nodes)) {
            $id=[string]$id0
            $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='DependencyCycle'; Reason="Ciclo de dependencias: $($cycle.Path)"; Source=$sourceMap[$id] }
        }
    }
    Invoke-WinSlimPlannerR2DependencyPropagation

    # Stable Kahn sort. SortedList key is catalog position, reproducing legacy tie-breaking.
    $activeMap = @{}
    $indegree = @{}
    $activeCount = 0
    foreach ($id0 in $candidateOrdered) {
        $id=[string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $blockedMap $id) -and -not (Test-WinSlimPlannerR2MapKey $skippedMap $id)) {
            $activeMap[$id]=$true
            $activeCount++
        }
    }
    foreach ($id0 in $candidateOrdered) {
        $id=[string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $activeMap $id)) { continue }
        $n=0
        foreach ($dep0 in @($depsById[$id])) {
            $dep=[string]$dep0
            if (Test-WinSlimPlannerR2MapKey $activeMap $dep) { $n++ }
        }
        $indegree[$id]=$n
    }

    $ready = New-Object System.Collections.SortedList
    foreach ($id0 in $candidateOrdered) {
        $id=[string]$id0
        if ((Test-WinSlimPlannerR2MapKey $activeMap $id) -and [int]$indegree[$id] -eq 0) {
            $ready.Add([int]$position[$id], $id)
        }
    }

    $orderedIdsList = New-Object System.Collections.ArrayList
    $orderedSet = @{}
    while ($ready.Count -gt 0) {
        $n = [string]$ready.GetByIndex(0)
        $ready.RemoveAt(0)
        if (Test-WinSlimPlannerR2MapKey $orderedSet $n) { continue }
        $orderedSet[$n]=$true
        [void]$orderedIdsList.Add($n)
        foreach ($depender0 in @(if (Test-WinSlimPlannerR2MapKey $runtimeDependents $n) { $runtimeDependents[$n] } else { @() })) {
            $depender=[string]$depender0
            if (-not (Test-WinSlimPlannerR2MapKey $indegree $depender)) { continue }
            $indegree[$depender] = [int]$indegree[$depender] - 1
            if ([int]$indegree[$depender] -eq 0 -and -not (Test-WinSlimPlannerR2MapKey $orderedSet $depender)) {
                $p=[int]$position[$depender]
                if (-not $ready.ContainsKey($p)) { $ready.Add($p,$depender) }
            }
        }
    }
    $orderedIds = [object[]]$orderedIdsList.ToArray()

    if ($orderedIds.Count -lt $activeCount) {
        foreach ($id0 in $candidateOrdered) {
            $id=[string]$id0
            if ((Test-WinSlimPlannerR2MapKey $activeMap $id) -and -not (Test-WinSlimPlannerR2MapKey $orderedSet $id)) {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='TopologicalSortFailed'; Reason='Nao foi possivel produzir ordem topologica segura.'; Source=$sourceMap[$id] }
            }
        }
        $filtered = New-Object System.Collections.ArrayList
        foreach ($id0 in $orderedIds) {
            $id=[string]$id0
            if (-not (Test-WinSlimPlannerR2MapKey $blockedMap $id)) { [void]$filtered.Add($id) }
        }
        $orderedIds = [object[]]$filtered.ToArray()
    }

    $executionList = New-Object System.Collections.ArrayList
    $seq=0
    foreach ($id0 in $orderedIds) {
        $id=[string]$id0
        $seq++
        $t=$index[$id]
        $lvl=if (Test-WinSlimPlannerR2MapKey $levelMap $id) { [int]$levelMap[$id] } else { -1 }
        $riskValue=[string]$catalogRuntime.RiskById[$id]
        [void]$executionList.Add([PSCustomObject]@{
            Sequence=$seq
            TweakId=$id
            Level=$lvl
            SelectionSource=$sourceMap[$id]
            Dependencies=@($depsById[$id])
            Risk=$riskValue
            RequiresRestart=[bool]$requiresRestartById[$id]
            RestartScope=[string]$restartScopeById[$id]
            Tweak=(Copy-WinSlimPlannerObject $t)
        })
    }
    $execution = [object[]]$executionList.ToArray()

    $riskLow=0; $riskMedium=0; $riskHigh=0; $highest='None'; $highestRank=0
    $restartIdsList=New-Object System.Collections.ArrayList
    $scopeList=New-Object System.Collections.ArrayList
    $scopeSet=@{}
    $reboot=$false
    foreach ($item in $execution) {
        $rank=Get-WinSlimPlannerRiskRank $item.Risk
        if ($rank -eq 1) { $riskLow++ } elseif ($rank -eq 2) { $riskMedium++ } elseif ($rank -eq 3) { $riskHigh++ }
        if ($rank -gt $highestRank) { $highestRank=$rank; $highest=$item.Risk }
        if ($item.RequiresRestart -or ($item.RestartScope -and $item.RestartScope -ne 'None')) {
            [void]$restartIdsList.Add($item.TweakId)
            if ($item.RestartScope -and $item.RestartScope -ne 'None' -and -not (Test-WinSlimPlannerR2MapKey $scopeSet $item.RestartScope)) {
                $scopeSet[$item.RestartScope]=$true
                [void]$scopeList.Add($item.RestartScope)
            }
            if ($item.RequiresRestart -or $item.RestartScope -eq 'Reboot') { $reboot=$true }
        }
    }

    $expandedList=New-Object System.Collections.ArrayList
    foreach ($id0 in $candidateOrdered) {
        $id=[string]$id0
        if (-not (Test-WinSlimPlannerR2MapKey $rootSet $id)) { [void]$expandedList.Add($id) }
    }
    $expanded=[object[]]$expandedList.ToArray()

    $blocked=@($blockedMap.Values | Sort-Object @{Expression={ if (Test-WinSlimPlannerR2MapKey $position ([string]$_.TweakId)) { [int]$position[[string]$_.TweakId] } else { [int]::MaxValue } }}, TweakId)
    $skipped=@($skippedMap.Values | Sort-Object @{Expression={ if (Test-WinSlimPlannerR2MapKey $position ([string]$_.TweakId)) { [int]$position[[string]$_.TweakId] } else { [int]::MaxValue } }}, TweakId)

    if ([bool](Get-WinSlimPlannerR2Property $Context 'PendingReboot' $false)) {
        [void]$warningsList.Add([PSCustomObject]@{ Code='PendingReboot'; TweakId=$null; Message='O Windows ja possui reinicializacao pendente antes deste plano.' })
    }

    $tokens=New-Object System.Collections.ArrayList
    [void]$tokens.Add("schema=$script:PlannerSchemaVersion")
    [void]$tokens.Add("preset=$PresetName")
    [void]$tokens.Add("policy=$ConflictPolicy")
    foreach ($id0 in $rootsKnown) { [void]$tokens.Add("selected=$([string]$id0)") }
    foreach ($item in $execution) { [void]$tokens.Add("exec=$($item.TweakId):$($item.Level)") }
    foreach ($b in $blocked) { [void]$tokens.Add("blocked=$($b.TweakId):$($b.ReasonCode)") }
    foreach ($s in $skipped) { [void]$tokens.Add("skipped=$($s.TweakId):$($s.ReasonCode)") }
    [void]$tokens.Add("os=$([string](Get-WinSlimPlannerR2Property $Context 'OS' ''))")
    [void]$tokens.Add("admin=$([string](Get-WinSlimPlannerR2Property $Context 'IsAdmin' ''))")
    $fingerprint=Get-WinSlimPlannerFingerprint -Tokens ([string[]]$tokens.ToArray())

    $warnings=[object[]]$warningsList.ToArray()
    $conflicts=[object[]]$conflictsList.ToArray()
    $mutexDecisions=[object[]]$mutexDecisionsList.ToArray()
    $windowsApplicability=[object[]]$windowsApplicabilityList.ToArray()
    $hardwareApplicability=[object[]]$hardwareApplicabilityList.ToArray()
    $adminApplicability=[object[]]$adminApplicabilityList.ToArray()
    $restartIds=[object[]]$restartIdsList.ToArray()
    $scopes=[object[]]$scopeList.ToArray()

    return [PSCustomObject]@{
        SchemaVersion=$script:PlannerSchemaVersion
        Fingerprint=$fingerprint
        PresetName=$PresetName
        ConflictPolicy=$ConflictPolicy
        SelectedTweaks=@($rootsKnown)
        ExpandedDependencies=@($expanded)
        ExecutionOrder=@($execution)
        SkippedTweaks=@($skipped)
        BlockedTweaks=@($blocked)
        Conflicts=@($conflicts)
        MutexDecisions=@($mutexDecisions)
        DependencyCycles=@($cycles)
        Warnings=@($warnings)
        WindowsApplicability=@($windowsApplicability)
        HardwareApplicability=@($hardwareApplicability)
        AdminApplicability=@($adminApplicability)
        RiskSummary=[PSCustomObject]@{ Low=$riskLow; Medium=$riskMedium; High=$riskHigh; Highest=$highest }
        RestartRequirements=[PSCustomObject]@{
            Required=($restartIds.Count -gt 0)
            RebootRequired=$reboot
            Scopes=@($scopes)
            TweakIds=@($restartIds)
            PendingRebootBeforePlan=[bool](Get-WinSlimPlannerR2Property $Context 'PendingReboot' $false)
        }
        CanExecute=($blocked.Count -eq 0)
        HasWork=($execution.Count -gt 0)
        Summary=[PSCustomObject]@{
            Selected=$rootsKnown.Count
            Dependencies=$expanded.Count
            Executable=$execution.Count
            Skipped=$skipped.Count
            Blocked=$blocked.Count
            Conflicts=$conflicts.Count
            Mutex=$mutexDecisions.Count
        }
    }
}

function Invoke-WinSlimPresetRuntimePlannerValidationR2 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$PresetRuntime,
        [Parameter(Mandatory)]$PlannerRuntime,
        [Parameter(Mandatory)][ValidateSet('Balanceado','Gamer','Extremo')][string]$PresetName,
        [string[]]$ConditionalProfiles = @(),
        [switch]$AllowHighRiskConditional,
        $Context = $null,
        [switch]$SkipApplicabilityChecks
    )

    if ($null -eq $Context) {
        if (Get-Command New-WinSlimSyntheticPlannerContext -ErrorAction SilentlyContinue) {
            $Context = New-WinSlimSyntheticPlannerContext -OS '11' -IsAdmin $true
        } else {
            throw 'Context ausente e New-WinSlimSyntheticPlannerContext nao esta carregado.'
        }
    }

    $presetCatalogFingerprint = [string]$PresetRuntime.CatalogRuntime.Fingerprint
    $plannerCatalogFingerprint = [string]$PlannerRuntime.CatalogRuntime.Fingerprint
    if ($presetCatalogFingerprint -ne $plannerCatalogFingerprint) {
        throw 'PresetRuntime e PlannerRuntime foram criados sobre CatalogRuntime diferentes.'
    }

    $policy = Resolve-WinSlimPresetRuntimeSelection `
        -PresetRuntime $PresetRuntime `
        -PresetName $PresetName `
        -ConditionalProfiles @($ConditionalProfiles) `
        -AllowHighRiskConditional:$AllowHighRiskConditional

    if (-not [bool]$policy.CanResolve) {
        return [PSCustomObject]@{
            SchemaVersion = 1
            Stage = 'Policy'
            PresetName = $PresetName
            ConditionalProfiles = @($policy.EnabledConditionalProfiles)
            PolicyFingerprint = [string]$policy.Fingerprint
            PlannerFingerprint = $null
            Policy = $policy
            Plan = $null
            CanResolve = $false
            CanExecute = $false
            HasWork = $false
            SelectedCount = @($policy.SelectedIds).Count
            DependencyCount = 0
            ExecutableCount = 0
            SkippedCount = 0
            BlockedCount = @($policy.BlockedRequests).Count
            RiskSummary = [PSCustomObject]@{ Low=0; Medium=0; High=0; Highest='None' }
            RestartRequirements = [PSCustomObject]@{ Required=$false; RebootRequired=$false; Scopes=@(); TweakIds=@(); PendingRebootBeforePlan=$false }
        }
    }

    $plan = New-WinSlimExecutionPlanOptimized `
        -PlannerRuntime $PlannerRuntime `
        -SelectedIds @($policy.SelectedIds) `
        -LevelSelections $policy.LevelSelections `
        -Context $Context `
        -ConflictPolicy 'Block' `
        -SkipApplicabilityChecks:$SkipApplicabilityChecks

    return [PSCustomObject]@{
        SchemaVersion = 1
        Stage = 'Planner'
        PresetName = $PresetName
        ConditionalProfiles = @($policy.EnabledConditionalProfiles)
        PolicyFingerprint = [string]$policy.Fingerprint
        PlannerFingerprint = [string]$plan.Fingerprint
        Policy = $policy
        Plan = $plan
        CanResolve = $true
        CanExecute = [bool]$plan.CanExecute
        HasWork = [bool]$plan.HasWork
        SelectedCount = @($plan.SelectedTweaks).Count
        DependencyCount = @($plan.ExpandedDependencies).Count
        ExecutableCount = @($plan.ExecutionOrder).Count
        SkippedCount = @($plan.SkippedTweaks).Count
        BlockedCount = @($plan.BlockedTweaks).Count
        RiskSummary = $plan.RiskSummary
        RestartRequirements = $plan.RestartRequirements
    }
}
