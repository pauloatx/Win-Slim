<#
    Win-Slim Suite - Planner (Fase 4 R1)

    Responsabilidade desta camada:
    - transformar selecao/preset + catalogo + contexto em um ExecutionPlan puro;
    - expandir dependencias transitivas;
    - resolver ordem topologica de forma deterministica;
    - detectar dependencias ausentes/ciclos;
    - detectar conflicts e mutexGroup;
    - avaliar compatibilidade Windows/hardware/admin;
    - produzir preview estruturado (Skip/Blocked/Warnings/Risk/Restart);
    - entregar itens no formato aceito por Invoke-TransactionPlan.

    REGRA ARQUITETURAL: este arquivo NAO altera o Windows. Nao chama Provider,
    Engine, Registry, Service, BCD, PowerCfg, AppX, ScheduledTask ou comandos
    nativos de mutacao. Planner decide; Transaction Manager executa.

    Compatibilidade: Windows PowerShell 5.1.
#>

$script:PlannerSchemaVersion = 1

function Get-WinSlimPlannerProperty {
    param($InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        try { if ($InputObject.Contains($Name)) { return $InputObject[$Name] } } catch { }
    }
    try {
        $p = $InputObject.PSObject.Properties[$Name]
        if ($null -ne $p) { return $p.Value }
    } catch { }
    return $Default
}

function Test-WinSlimPlannerMapKey {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $false }
    try { return [bool]$Map.Contains($Key) } catch { }
    try { return [bool]$Map.ContainsKey($Key) } catch { }
    return $false
}

function ConvertTo-WinSlimPlannerPlainValueInternal {
    param($InputObject, [Parameter(Mandatory)][ref]$Output, [int]$Depth = 0)
    if ($Depth -gt 32) { throw 'Planner clone excedeu a profundidade maxima (32).' }
    if ($null -eq $InputObject) { $Output.Value = $null; return }

    if ($InputObject -is [byte[]]) {
        $Output.Value = [byte[]]$InputObject.Clone()
        return
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in @($InputObject.Keys)) {
            $child = $null
            ConvertTo-WinSlimPlannerPlainValueInternal -InputObject $InputObject[$key] -Output ([ref]$child) -Depth ($Depth + 1)
            $copy[$key] = $child
        }
        $Output.Value = $copy
        return
    }
    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $InputObject) {
            $child = $null
            ConvertTo-WinSlimPlannerPlainValueInternal -InputObject $item -Output ([ref]$child) -Depth ($Depth + 1)
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
        $base = $InputObject.PSObject.BaseObject
        $Output.Value = $(if ($null -ne $base) { $base } else { $InputObject })
        return
    }

    $props = @($InputObject.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($props.Count -gt 0) {
        $bag = [ordered]@{}
        foreach ($prop in $props) {
            $child = $null
            ConvertTo-WinSlimPlannerPlainValueInternal -InputObject $prop.Value -Output ([ref]$child) -Depth ($Depth + 1)
            $bag[$prop.Name] = $child
        }
        $Output.Value = [PSCustomObject]$bag
        return
    }
    $Output.Value = [string]$InputObject
}

function Copy-WinSlimPlannerObject {
    param($InputObject)
    $result = $null
    ConvertTo-WinSlimPlannerPlainValueInternal -InputObject $InputObject -Output ([ref]$result)
    if ($result -is [System.Array]) { return ,$result }
    return $result
}

function Get-WinSlimPlannerTweakId {
    param($Tweak)
    if ($null -eq $Tweak) { return $null }
    $id = Get-WinSlimPlannerProperty -InputObject $Tweak -Name 'id'
    if ([string]::IsNullOrWhiteSpace([string]$id)) { $id = Get-WinSlimPlannerProperty -InputObject $Tweak -Name 'Id' }
    if ([string]::IsNullOrWhiteSpace([string]$id)) { return $null }
    return ([string]$id).Trim()
}

function Get-WinSlimPlannerRiskRank {
    param([string]$Risk)
    switch -Regex ($Risk) {
        '^(Alto|High)$' { return 3 }
        '^(M[eé]dio|Medium)$' { return 2 }
        '^(Baixo|Low)$' { return 1 }
        default { return 0 }
    }
}

function Get-WinSlimPlannerFingerprint {
    param([string[]]$Tokens)
    $canonical = (@($Tokens) -join "`n")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally { $sha.Dispose() }
}

function Get-WinSlimPresetSelection {
    param(
        [Parameter(Mandatory)]$CatalogTweaks,
        [Parameter(Mandatory)][string]$PresetName
    )
    $ids = @()
    $levels = @{}
    foreach ($t in @($CatalogTweaks)) {
        $id = Get-WinSlimPlannerTweakId $t
        if (-not $id) { continue }
        $type = [string](Get-WinSlimPlannerProperty $t 'type' '')
        if ($type -eq 'multilevel') {
            $pl = Get-WinSlimPlannerProperty $t 'presetLevels'
            if ($pl -and ($pl.PSObject.Properties.Name -contains $PresetName)) {
                $lvl = [int]$pl.PSObject.Properties[$PresetName].Value
                # Compatibilidade com a UI atual: level 0 = estado base/no-op do preset.
                if ($lvl -gt 0) { $ids += $id; $levels[$id] = $lvl }
            }
        } else {
            $presets = @(Get-WinSlimPlannerProperty $t 'presets' @())
            if ($presets -contains $PresetName) { $ids += $id }
        }
    }
    return [PSCustomObject]@{ PresetName=$PresetName; SelectedIds=@($ids); LevelSelections=$levels }
}

function Test-WinSlimTweakApplicability {
    param(
        [Parameter(Mandatory)]$Tweak,
        $Context,
        [switch]$SkipApplicabilityChecks
    )
    $id = Get-WinSlimPlannerTweakId $Tweak
    if ($SkipApplicabilityChecks) {
        return [PSCustomObject]@{
            TweakId=$id; Decision='Apply'; ReasonCode='ChecksSkipped'; Reason=$null
            Windows=[PSCustomObject]@{ Applicable=$true; Reason=$null }
            Hardware=[PSCustomObject]@{ Applicable=$true; Reason=$null }
            Admin=[PSCustomObject]@{ Applicable=$true; Reason=$null }
        }
    }

    $win = [PSCustomObject]@{ Applicable=$true; Reason=$null }
    $hw  = [PSCustomObject]@{ Applicable=$true; Reason=$null }
    $adm = [PSCustomObject]@{ Applicable=$true; Reason=$null }

    $supported = @(Get-WinSlimPlannerProperty $Tweak 'windowsVersion' @())
    if ($supported.Count -gt 0) {
        $os = [string](Get-WinSlimPlannerProperty $Context 'OS' '')
        if ([string]::IsNullOrWhiteSpace($os)) {
            $win.Applicable = $null; $win.Reason = 'Context.OS ausente.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='MissingContextOS'; Reason=$win.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }
        if ($supported -notcontains $os) {
            $win.Applicable = $false; $win.Reason = "Tweak suporta Windows $($supported -join '/') e o contexto e Windows $os."
            return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='WindowsNotSupported'; Reason=$win.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }
    }

    $requiresAdmin = [bool](Get-WinSlimPlannerProperty $Tweak 'requiresAdmin' $false)
    if ($requiresAdmin) {
        $isAdminRaw = Get-WinSlimPlannerProperty $Context 'IsAdmin' $null
        if ($null -eq $isAdminRaw) {
            $adm.Applicable = $null; $adm.Reason = 'Context.IsAdmin ausente.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='AdminStateUnknown'; Reason=$adm.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }
        if (-not [bool]$isAdminRaw) {
            $adm.Applicable = $false; $adm.Reason = 'O tweak requer privilegios de administrador.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='RequiresAdmin'; Reason=$adm.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }
    }

    $rules = Get-WinSlimPlannerProperty $Tweak 'hardwareRules' $null
    if ($rules) {
        $known = @('requiresGPU','vendors','minRamGB','maxRamGB','storageTypes','requiresSSD','requiresTPM','requiresSecureBoot','requiresVBS','forbidVBS','requiresHVCI','forbidHVCI','requiresHyperV','forbidHyperV','requiresNetworkAdapter','cpuNameRegex','gpuNameRegex')
        $ruleProps = @($rules.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
        if ($rules -is [System.Collections.IDictionary]) {
            $ruleNames = @($rules.Keys | ForEach-Object { [string]$_ })
        } else {
            $ruleNames = @($ruleProps | Select-Object -ExpandProperty Name)
        }
        foreach ($rn in $ruleNames) {
            if ($known -notcontains $rn) {
                $hw.Applicable = $null; $hw.Reason = "hardwareRule nao suportada pelo Planner R1: $rn"
                return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='UnsupportedHardwareRule'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
            }
        }

        $gpus = @(Get-WinSlimPlannerProperty $Context 'GPU' @())
        $requiresGPU = [bool](Get-WinSlimPlannerProperty $rules 'requiresGPU' $false)
        if ($requiresGPU -and $gpus.Count -eq 0) {
            $hw.Applicable=$false; $hw.Reason='GPU compativel nao detectada.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='GpuRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }

        $vendors = @(Get-WinSlimPlannerProperty $rules 'vendors' @())
        if ($vendors.Count -gt 0) {
            if ($gpus.Count -eq 0) {
                $hw.Applicable=$false; $hw.Reason='Regra de fabricante de GPU definida, mas nenhuma GPU foi detectada.'
                return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='GpuVendorUnavailable'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
            }
            $vendorMatch = $false
            foreach ($gpu in $gpus) {
                foreach ($vendor in $vendors) {
                    if ([string]$gpu -match [regex]::Escape([string]$vendor)) { $vendorMatch=$true; break }
                }
                if ($vendorMatch) { break }
            }
            if (-not $vendorMatch) {
                $hw.Applicable=$false; $hw.Reason="GPU nao corresponde aos fabricantes permitidos: $($vendors -join ', ')."
                return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='GpuVendorMismatch'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
            }
        }

        $ram = Get-WinSlimPlannerProperty $Context 'RAM' $null
        $minRam = Get-WinSlimPlannerProperty $rules 'minRamGB' $null
        $maxRam = Get-WinSlimPlannerProperty $rules 'maxRamGB' $null
        if ($null -ne $minRam) {
            if ($null -eq $ram) { $hw.Applicable=$null; $hw.Reason='RAM desconhecida para avaliar minRamGB.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if ([double]$ram -lt [double]$minRam) { $hw.Applicable=$false; $hw.Reason="Requer pelo menos $minRam GB de RAM."; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='MinRamNotMet'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }
        if ($null -ne $maxRam) {
            if ($null -eq $ram) { $hw.Applicable=$null; $hw.Reason='RAM desconhecida para avaliar maxRamGB.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if ([double]$ram -gt [double]$maxRam) { $hw.Applicable=$false; $hw.Reason="Requer no maximo $maxRam GB de RAM."; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='MaxRamNotMet'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }

        $storageTypes = @(Get-WinSlimPlannerProperty $rules 'storageTypes' @())
        $requiresSSD = [bool](Get-WinSlimPlannerProperty $rules 'requiresSSD' $false)
        $storage = [string](Get-WinSlimPlannerProperty $Context 'Storage' '')
        if ($requiresSSD -and $storage -ne 'SSD') {
            $hw.Applicable=$false; $hw.Reason='Tweak requer SSD.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='SsdRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }
        if ($storageTypes.Count -gt 0 -and $storageTypes -notcontains $storage) {
            $hw.Applicable=$false; $hw.Reason="Storage '$storage' nao esta entre: $($storageTypes -join ', ')."
            return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='StorageMismatch'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }

        $requiresTPM = [bool](Get-WinSlimPlannerProperty $rules 'requiresTPM' $false)
        if ($requiresTPM) {
            $tpm = Get-WinSlimPlannerProperty $Context 'TPM' $null
            if ($null -eq $tpm) { $hw.Applicable=$null; $hw.Reason='Estado do TPM desconhecido.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if (-not [bool](Get-WinSlimPlannerProperty $tpm 'Present' $false)) { $hw.Applicable=$false; $hw.Reason='TPM requerido nao esta presente.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='TpmRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }

        $requiresSB = [bool](Get-WinSlimPlannerProperty $rules 'requiresSecureBoot' $false)
        if ($requiresSB) {
            $sb = Get-WinSlimPlannerProperty $Context 'SecureBoot' $null
            if ($null -eq $sb) { $hw.Applicable=$null; $hw.Reason='Estado do Secure Boot desconhecido.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if (-not [bool](Get-WinSlimPlannerProperty $sb 'Enabled' $false)) { $hw.Applicable=$false; $hw.Reason='Secure Boot requerido nao esta habilitado.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='SecureBootRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }

        foreach ($pair in @(
            [PSCustomObject]@{ Rule='requiresVBS'; Context='VBS'; Expected=$true; Code='VbsRequired' },
            [PSCustomObject]@{ Rule='forbidVBS'; Context='VBS'; Expected=$false; Code='VbsForbidden' },
            [PSCustomObject]@{ Rule='requiresHVCI'; Context='HVCI'; Expected=$true; Code='HvciRequired' },
            [PSCustomObject]@{ Rule='forbidHVCI'; Context='HVCI'; Expected=$false; Code='HvciForbidden' }
        )) {
            if ([bool](Get-WinSlimPlannerProperty $rules $pair.Rule $false)) {
                $actual = Get-WinSlimPlannerProperty $Context $pair.Context $null
                if ($null -eq $actual) { $hw.Applicable=$null; $hw.Reason="$($pair.Context) desconhecido."; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
                if ([bool]$actual -ne [bool]$pair.Expected) { $hw.Applicable=$false; $hw.Reason="Regra $($pair.Rule) nao atendida."; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode=$pair.Code; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            }
        }

        $requiresHV = [bool](Get-WinSlimPlannerProperty $rules 'requiresHyperV' $false)
        $forbidHV = [bool](Get-WinSlimPlannerProperty $rules 'forbidHyperV' $false)
        if ($requiresHV -or $forbidHV) {
            $hv = Get-WinSlimPlannerProperty $Context 'HyperV' $null
            if ($null -eq $hv) { $hw.Applicable=$null; $hw.Reason='Estado do Hyper-V desconhecido.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            $installed = Get-WinSlimPlannerProperty $hv 'FeatureInstalled' $null
            if ($null -eq $installed) { $hw.Applicable=$null; $hw.Reason='FeatureInstalled do Hyper-V desconhecido.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if ($requiresHV -and -not [bool]$installed) { $hw.Applicable=$false; $hw.Reason='Hyper-V requerido nao esta instalado.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='HyperVRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if ($forbidHV -and [bool]$installed) { $hw.Applicable=$false; $hw.Reason='Tweak requer Hyper-V ausente.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='HyperVForbidden'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }

        $requiresNet = [bool](Get-WinSlimPlannerProperty $rules 'requiresNetworkAdapter' $false)
        if ($requiresNet -and @(Get-WinSlimPlannerProperty $Context 'NetworkAdapters' @()).Count -eq 0) {
            $hw.Applicable=$false; $hw.Reason='Adaptador de rede ativo requerido nao foi detectado.'
            return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='NetworkAdapterRequired'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm }
        }

        $cpuRegex = [string](Get-WinSlimPlannerProperty $rules 'cpuNameRegex' '')
        if ($cpuRegex) {
            $cpu = [string](Get-WinSlimPlannerProperty $Context 'CPU' '')
            if (-not $cpu) { $hw.Applicable=$null; $hw.Reason='CPU desconhecida para cpuNameRegex.'; return [PSCustomObject]@{ TweakId=$id; Decision='Block'; ReasonCode='HardwareStateUnknown'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
            if ($cpu -notmatch $cpuRegex) { $hw.Applicable=$false; $hw.Reason='CPU nao corresponde a cpuNameRegex.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='CpuRuleMismatch'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }
        $gpuRegex = [string](Get-WinSlimPlannerProperty $rules 'gpuNameRegex' '')
        if ($gpuRegex) {
            $gm = $false
            foreach ($gpu in $gpus) { if ([string]$gpu -match $gpuRegex) { $gm=$true; break } }
            if (-not $gm) { $hw.Applicable=$false; $hw.Reason='GPU nao corresponde a gpuNameRegex.'; return [PSCustomObject]@{ TweakId=$id; Decision='Skip'; ReasonCode='GpuRuleMismatch'; Reason=$hw.Reason; Windows=$win; Hardware=$hw; Admin=$adm } }
        }
    }

    return [PSCustomObject]@{ TweakId=$id; Decision='Apply'; ReasonCode='Applicable'; Reason=$null; Windows=$win; Hardware=$hw; Admin=$adm }
}

function Find-WinSlimDependencyCycles {
    param([hashtable]$DependenciesById, [hashtable]$ActiveMap, [string[]]$OrderedIds)
    $state = @{}
    $stack = New-Object System.Collections.ArrayList
    $cycles = New-Object System.Collections.ArrayList
    $cycleKeys = @{}
    $visit = $null
    $visit = {
        param([string]$Id)
        $state[$Id] = 1
        [void]$stack.Add($Id)
        foreach ($dep in @($DependenciesById[$Id])) {
            if (-not (Test-WinSlimPlannerMapKey $ActiveMap $dep)) { continue }
            if (-not (Test-WinSlimPlannerMapKey $state $dep)) {
                & $visit $dep
            } elseif ([int]$state[$dep] -eq 1) {
                $start = -1
                for ($i=0; $i -lt $stack.Count; $i++) { if ([string]$stack[$i] -eq $dep) { $start=$i; break } }
                if ($start -ge 0) {
                    $nodes = @()
                    for ($j=$start; $j -lt $stack.Count; $j++) { $nodes += [string]$stack[$j] }
                    $key = (@($nodes | Sort-Object) -join '|')
                    if (-not (Test-WinSlimPlannerMapKey $cycleKeys $key)) {
                        $cycleKeys[$key] = $true
                        [void]$cycles.Add([PSCustomObject]@{ Nodes=@($nodes); Path=(($nodes + $dep) -join ' -> ') })
                    }
                }
            }
        }
        if ($stack.Count -gt 0) { $stack.RemoveAt($stack.Count-1) }
        $state[$Id] = 2
    }
    foreach ($id in @($OrderedIds)) {
        if ((Test-WinSlimPlannerMapKey $ActiveMap $id) -and -not (Test-WinSlimPlannerMapKey $state $id)) { & $visit $id }
    }
    return @($cycles.ToArray())
}

function New-WinSlimExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CatalogTweaks,
        [string[]]$SelectedIds = @(),
        $LevelSelections = $null,
        $Context = $null,
        [string]$PresetName,
        [ValidateSet('Block','PreferFirst')][string]$ConflictPolicy = 'Block',
        [switch]$SkipApplicabilityChecks
    )

    $catalog = @($CatalogTweaks)
    $index = [ordered]@{}
    $position = @{}
    $catalogIssues = @()
    $pos = 0
    foreach ($t in $catalog) {
        $id = Get-WinSlimPlannerTweakId $t
        if (-not $id) { $catalogIssues += [PSCustomObject]@{ Code='MissingCatalogId'; TweakId=$null; Message="Entrada de catalogo na posicao $pos nao possui id." }; $pos++; continue }
        if (Test-WinSlimPlannerMapKey $index $id) {
            $catalogIssues += [PSCustomObject]@{ Code='DuplicateCatalogId'; TweakId=$id; Message="ID duplicado no catalogo: $id" }
        } else {
            $index[$id] = $t
            $position[$id] = $pos
        }
        $pos++
    }

    $levelMap = @{}
    if ($LevelSelections) {
        if ($LevelSelections -is [System.Collections.IDictionary]) {
            foreach ($k in @($LevelSelections.Keys)) { $levelMap[[string]$k] = [int]$LevelSelections[$k] }
        } else {
            foreach ($p in @($LevelSelections.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })) { $levelMap[$p.Name] = [int]$p.Value }
        }
    }

    $rootSource = @{}
    $rootSet = @{}
    foreach ($id0 in @($SelectedIds)) {
        $id = ([string]$id0).Trim(); if (-not $id) { continue }
        $rootSet[$id] = $true; $rootSource[$id] = 'Selected'
    }

    if ($PresetName) {
        $preset = Get-WinSlimPresetSelection -CatalogTweaks $catalog -PresetName $PresetName
        foreach ($id in @($preset.SelectedIds)) {
            $rootSet[$id] = $true
            if (-not (Test-WinSlimPlannerMapKey $rootSource $id)) { $rootSource[$id] = 'Preset' }
        }
        foreach ($k in @($preset.LevelSelections.Keys)) {
            if (-not (Test-WinSlimPlannerMapKey $levelMap $k)) { $levelMap[$k] = [int]$preset.LevelSelections[$k] }
        }
    }

    foreach ($k in @($levelMap.Keys)) {
        if ([int]$levelMap[$k] -gt 0) {
            $rootSet[$k] = $true
            if (-not (Test-WinSlimPlannerMapKey $rootSource $k)) { $rootSource[$k] = 'LevelSelection' }
        }
    }

    $allCatalogIds = @($index.Keys)
    $rootsKnown = @($allCatalogIds | Where-Object { Test-WinSlimPlannerMapKey $rootSet $_ })
    $rootsUnknown = @($rootSet.Keys | Where-Object { -not (Test-WinSlimPlannerMapKey $index ([string]$_)) } | Sort-Object)

    $blockedMap = @{}
    $skippedMap = @{}
    $warnings = @()
    $conflicts = @()
    $mutexDecisions = @()

    foreach ($ci in @($catalogIssues)) {
        if ($ci.TweakId) { $blockedMap[$ci.TweakId] = [PSCustomObject]@{ TweakId=$ci.TweakId; ReasonCode=$ci.Code; Reason=$ci.Message; Source='Catalog' } }
        else { $warnings += [PSCustomObject]@{ Code=$ci.Code; TweakId=$null; Message=$ci.Message } }
    }
    foreach ($id in $rootsUnknown) {
        $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='UnknownTweak'; Reason="Tweak '$id' nao existe no catalogo."; Source='Selection' }
    }

    # Expansao transitiva de dependencias (somente leitura do catalogo).
    $candidateMap = @{}
    $sourceMap = @{}
    $depsById = @{}
    $dependentsById = @{}
    $queue = New-Object System.Collections.ArrayList
    foreach ($id in $rootsKnown) { if (-not (Test-WinSlimPlannerMapKey $candidateMap $id)) { $candidateMap[$id]=$true; $sourceMap[$id]=$rootSource[$id]; [void]$queue.Add($id) } }
    for ($qi=0; $qi -lt $queue.Count; $qi++) {
        $id = [string]$queue[$qi]
        $t = $index[$id]
        $deps = @()
        foreach ($d0 in @(Get-WinSlimPlannerProperty $t 'dependencies' @())) {
            $d = ([string]$d0).Trim(); if (-not $d) { continue }
            $deps += $d
            if (-not (Test-WinSlimPlannerMapKey $dependentsById $d)) { $dependentsById[$d] = @() }
            if (@($dependentsById[$d]) -notcontains $id) { $dependentsById[$d] = @($dependentsById[$d]) + $id }
            if (-not (Test-WinSlimPlannerMapKey $index $d)) {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='MissingDependency'; Reason="Dependencia '$d' de '$id' nao existe no catalogo."; Source=$sourceMap[$id]; Dependency=$d }
                continue
            }
            if (-not (Test-WinSlimPlannerMapKey $candidateMap $d)) {
                $candidateMap[$d]=$true; $sourceMap[$d]='Dependency'; [void]$queue.Add($d)
            }
        }
        $depsById[$id] = @($deps)
    }
    foreach ($id in @($candidateMap.Keys)) { if (-not (Test-WinSlimPlannerMapKey $depsById $id)) { $depsById[$id]=@() } }

    $candidateOrdered = @($allCatalogIds | Where-Object { Test-WinSlimPlannerMapKey $candidateMap $_ })

    # Aplicabilidade e validacao de nivel.
    $windowsApplicability = @()
    $hardwareApplicability = @()
    $adminApplicability = @()
    foreach ($id in $candidateOrdered) {
        if (Test-WinSlimPlannerMapKey $blockedMap $id) { continue }
        $t = $index[$id]
        $app = Test-WinSlimTweakApplicability -Tweak $t -Context $Context -SkipApplicabilityChecks:$SkipApplicabilityChecks
        $windowsApplicability += [PSCustomObject]@{ TweakId=$id; Applicable=$app.Windows.Applicable; Reason=$app.Windows.Reason }
        $hardwareApplicability += [PSCustomObject]@{ TweakId=$id; Applicable=$app.Hardware.Applicable; Reason=$app.Hardware.Reason }
        $adminApplicability += [PSCustomObject]@{ TweakId=$id; Applicable=$app.Admin.Applicable; Reason=$app.Admin.Reason }
        if ($app.Decision -eq 'Skip') {
            $skippedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode=$app.ReasonCode; Reason=$app.Reason; Source=$sourceMap[$id] }
            continue
        }
        if ($app.Decision -eq 'Block') {
            $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode=$app.ReasonCode; Reason=$app.Reason; Source=$sourceMap[$id] }
            continue
        }
        $type = [string](Get-WinSlimPlannerProperty $t 'type' '')
        if ($type -eq 'multilevel') {
            $lvl = if (Test-WinSlimPlannerMapKey $levelMap $id) { [int]$levelMap[$id] } else { -1 }
            $levels = @(Get-WinSlimPlannerProperty $t 'levels' @())
            if ($lvl -ge $levels.Count) {
                $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='InvalidLevel'; Reason="Nivel $lvl fora do intervalo do tweak ($($levels.Count) niveis)."; Source=$sourceMap[$id] }
            }
        }
    }

    function Propagate-WinSlimDependencyBlocks {
        $changed = $true
        while ($changed) {
            $changed = $false
            foreach ($id in $candidateOrdered) {
                if ((Test-WinSlimPlannerMapKey $blockedMap $id) -or (Test-WinSlimPlannerMapKey $skippedMap $id)) { continue }
                foreach ($dep in @($depsById[$id])) {
                    if ((Test-WinSlimPlannerMapKey $blockedMap $dep) -or (Test-WinSlimPlannerMapKey $skippedMap $dep)) {
                        $blockedMap[$id] = [PSCustomObject]@{ TweakId=$id; ReasonCode='DependencyUnavailable'; Reason="Dependencia '$dep' nao esta disponivel para execucao."; Source=$sourceMap[$id]; Dependency=$dep }
                        $changed = $true
                        break
                    }
                }
            }
        }
    }
    Propagate-WinSlimDependencyBlocks

    # Conflitos declarados. Um unico lado declarando conflict ja e suficiente.
    $pairSeen = @{}
    foreach ($id in $candidateOrdered) {
        if ((Test-WinSlimPlannerMapKey $blockedMap $id) -or (Test-WinSlimPlannerMapKey $skippedMap $id)) { continue }
        $t = $index[$id]
        foreach ($other0 in @(Get-WinSlimPlannerProperty $t 'conflicts' @())) {
            $other = [string]$other0
            if (-not (Test-WinSlimPlannerMapKey $candidateMap $other)) { continue }
            if ((Test-WinSlimPlannerMapKey $blockedMap $other) -or (Test-WinSlimPlannerMapKey $skippedMap $other)) { continue }
            $a=$id; $b=$other
            if ([string]::Compare($a,$b,$true) -gt 0) { $tmp=$a; $a=$b; $b=$tmp }
            $key="$a|$b"
            if (Test-WinSlimPlannerMapKey $pairSeen $key) { continue }
            $pairSeen[$key]=$true
            $winner=$null; $loser=$null; $decision='Blocked'
            if ($ConflictPolicy -eq 'PreferFirst') {
                if ([int]$position[$id] -le [int]$position[$other]) { $winner=$id; $loser=$other } else { $winner=$other; $loser=$id }
                $skippedMap[$loser]=[PSCustomObject]@{ TweakId=$loser; ReasonCode='ConflictLoser'; Reason="Conflita com '$winner'; PreferFirst manteve '$winner'."; Source=$sourceMap[$loser] }
                $decision='PreferFirst'
            } else {
                $blockedMap[$id]=[PSCustomObject]@{ TweakId=$id; ReasonCode='Conflict'; Reason="Conflita com '$other'."; Source=$sourceMap[$id]; ConflictWith=$other }
                $blockedMap[$other]=[PSCustomObject]@{ TweakId=$other; ReasonCode='Conflict'; Reason="Conflita com '$id'."; Source=$sourceMap[$other]; ConflictWith=$id }
            }
            $conflicts += [PSCustomObject]@{ Type='Conflict'; A=$id; B=$other; Policy=$ConflictPolicy; Decision=$decision; Winner=$winner; Loser=$loser }
        }
    }
    Propagate-WinSlimDependencyBlocks

    # mutexGroup: mais de um ativo no mesmo grupo exige decisao explicita.
    $groups = @{}
    foreach ($id in $candidateOrdered) {
        if ((Test-WinSlimPlannerMapKey $blockedMap $id) -or (Test-WinSlimPlannerMapKey $skippedMap $id)) { continue }
        $g=[string](Get-WinSlimPlannerProperty $index[$id] 'mutexGroup' '')
        if (-not $g) { continue }
        if (-not (Test-WinSlimPlannerMapKey $groups $g)) { $groups[$g]=@() }
        $groups[$g]=@($groups[$g])+$id
    }
    foreach ($g in @($groups.Keys | Sort-Object)) {
        $members=@($groups[$g])
        if ($members.Count -lt 2) { continue }
        $winner=$null; $losers=@(); $decision='Blocked'
        if ($ConflictPolicy -eq 'PreferFirst') {
            $winner=@($candidateOrdered | Where-Object { $members -contains $_ } | Select-Object -First 1)[0]
            $losers=@($members | Where-Object { $_ -ne $winner })
            foreach ($loser in $losers) { $skippedMap[$loser]=[PSCustomObject]@{ TweakId=$loser; ReasonCode='MutexLoser'; Reason="mutexGroup '$g' manteve '$winner'."; Source=$sourceMap[$loser] } }
            $decision='PreferFirst'
        } else {
            foreach ($m in $members) { $blockedMap[$m]=[PSCustomObject]@{ TweakId=$m; ReasonCode='MutexConflict'; Reason="Mais de um tweak ativo no mutexGroup '$g'."; Source=$sourceMap[$m]; MutexGroup=$g } }
        }
        $mutexDecisions += [PSCustomObject]@{ Group=$g; Candidates=@($members); Policy=$ConflictPolicy; Decision=$decision; Winner=$winner; Losers=@($losers) }
    }
    Propagate-WinSlimDependencyBlocks

    # Ciclos sao falha estrutural do catalogo; nunca tentamos escolher uma ordem arbitraria.
    $activeMap=@{}
    foreach ($id in $candidateOrdered) { if (-not (Test-WinSlimPlannerMapKey $blockedMap $id) -and -not (Test-WinSlimPlannerMapKey $skippedMap $id)) { $activeMap[$id]=$true } }
    $cycles = @(Find-WinSlimDependencyCycles -DependenciesById $depsById -ActiveMap $activeMap -OrderedIds $candidateOrdered)
    foreach ($cycle in $cycles) {
        foreach ($id in @($cycle.Nodes)) { $blockedMap[$id]=[PSCustomObject]@{ TweakId=$id; ReasonCode='DependencyCycle'; Reason="Ciclo de dependencias: $($cycle.Path)"; Source=$sourceMap[$id] } }
    }
    Propagate-WinSlimDependencyBlocks

    # Ordenacao topologica estavel: empates seguem a ordem do catalogo.
    $activeMap=@{}
    foreach ($id in $candidateOrdered) { if (-not (Test-WinSlimPlannerMapKey $blockedMap $id) -and -not (Test-WinSlimPlannerMapKey $skippedMap $id)) { $activeMap[$id]=$true } }
    $indegree=@{}
    foreach ($id in @($activeMap.Keys)) {
        $n=0; foreach ($dep in @($depsById[$id])) { if (Test-WinSlimPlannerMapKey $activeMap $dep) { $n++ } }; $indegree[$id]=$n
    }
    $orderedIds=@()
    while ($orderedIds.Count -lt $activeMap.Count) {
        $next=@($candidateOrdered | Where-Object { (Test-WinSlimPlannerMapKey $activeMap $_) -and ($orderedIds -notcontains $_) -and [int]$indegree[$_] -eq 0 } | Select-Object -First 1)
        if ($next.Count -eq 0) { break }
        $n=[string]$next[0]; $orderedIds += $n
        foreach ($depender in @($dependentsById[$n])) { if (Test-WinSlimPlannerMapKey $indegree $depender) { $indegree[$depender]=[int]$indegree[$depender]-1 } }
    }
    if ($orderedIds.Count -lt $activeMap.Count) {
        foreach ($id in $candidateOrdered) {
            if ((Test-WinSlimPlannerMapKey $activeMap $id) -and $orderedIds -notcontains $id) {
                $blockedMap[$id]=[PSCustomObject]@{ TweakId=$id; ReasonCode='TopologicalSortFailed'; Reason='Nao foi possivel produzir ordem topologica segura.'; Source=$sourceMap[$id] }
            }
        }
        $orderedIds=@($orderedIds | Where-Object { -not (Test-WinSlimPlannerMapKey $blockedMap $_) })
    }

    $execution=@()
    $seq=0
    foreach ($id in $orderedIds) {
        $seq++
        $t=$index[$id]
        $lvl=if (Test-WinSlimPlannerMapKey $levelMap $id) { [int]$levelMap[$id] } else { -1 }
        $execution += [PSCustomObject]@{
            Sequence=$seq; TweakId=$id; Level=$lvl; SelectionSource=$sourceMap[$id]
            Dependencies=@($depsById[$id]); Risk=[string](Get-WinSlimPlannerProperty $t 'risk' '')
            RequiresRestart=[bool](Get-WinSlimPlannerProperty $t 'requiresRestart' $false)
            RestartScope=[string](Get-WinSlimPlannerProperty $t 'restartScope' 'None')
            Tweak=(Copy-WinSlimPlannerObject $t)
        }
    }

    $riskLow=0; $riskMedium=0; $riskHigh=0; $highest='None'; $highestRank=0
    $restartIds=@(); $scopes=@(); $reboot=$false
    foreach ($item in $execution) {
        $rank=Get-WinSlimPlannerRiskRank $item.Risk
        if ($rank -eq 1) { $riskLow++ } elseif ($rank -eq 2) { $riskMedium++ } elseif ($rank -eq 3) { $riskHigh++ }
        if ($rank -gt $highestRank) { $highestRank=$rank; $highest=$item.Risk }
        if ($item.RequiresRestart -or ($item.RestartScope -and $item.RestartScope -ne 'None')) {
            $restartIds += $item.TweakId
            if ($item.RestartScope -and $item.RestartScope -ne 'None' -and $scopes -notcontains $item.RestartScope) { $scopes += $item.RestartScope }
            if ($item.RequiresRestart -or $item.RestartScope -eq 'Reboot') { $reboot=$true }
        }
    }

    $expanded=@($candidateOrdered | Where-Object { -not (Test-WinSlimPlannerMapKey $rootSet $_) })
    $blocked=@($blockedMap.Values | Sort-Object @{Expression={ if (Test-WinSlimPlannerMapKey $position $_.TweakId) { [int]$position[$_.TweakId] } else { [int]::MaxValue } }}, TweakId)
    $skipped=@($skippedMap.Values | Sort-Object @{Expression={ if (Test-WinSlimPlannerMapKey $position $_.TweakId) { [int]$position[$_.TweakId] } else { [int]::MaxValue } }}, TweakId)

    if ([bool](Get-WinSlimPlannerProperty $Context 'PendingReboot' $false)) { $warnings += [PSCustomObject]@{ Code='PendingReboot'; TweakId=$null; Message='O Windows ja possui reinicializacao pendente antes deste plano.' } }

    $tokens=@("schema=$script:PlannerSchemaVersion", "preset=$PresetName", "policy=$ConflictPolicy")
    foreach ($id in @($rootsKnown)) { $tokens += "selected=$id" }
    foreach ($item in $execution) { $tokens += "exec=$($item.TweakId):$($item.Level)" }
    foreach ($b in $blocked) { $tokens += "blocked=$($b.TweakId):$($b.ReasonCode)" }
    foreach ($s in $skipped) { $tokens += "skipped=$($s.TweakId):$($s.ReasonCode)" }
    $tokens += "os=$([string](Get-WinSlimPlannerProperty $Context 'OS' ''))"
    $tokens += "admin=$([string](Get-WinSlimPlannerProperty $Context 'IsAdmin' ''))"
    $fingerprint=Get-WinSlimPlannerFingerprint -Tokens $tokens

    $plan=[PSCustomObject]@{
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
            Required=($restartIds.Count -gt 0); RebootRequired=$reboot; Scopes=@($scopes); TweakIds=@($restartIds)
            PendingRebootBeforePlan=[bool](Get-WinSlimPlannerProperty $Context 'PendingReboot' $false)
        }
        CanExecute=($blocked.Count -eq 0)
        HasWork=($execution.Count -gt 0)
        Summary=[PSCustomObject]@{ Selected=$rootsKnown.Count; Dependencies=$expanded.Count; Executable=$execution.Count; Skipped=$skipped.Count; Blocked=$blocked.Count; Conflicts=$conflicts.Count; Mutex=$mutexDecisions.Count }
    }
    return $plan
}

function Get-WinSlimTransactionItemsFromPlan {
    param([Parameter(Mandatory)]$Plan)
    if (-not [bool]$Plan.CanExecute) {
        $ids=@($Plan.BlockedTweaks | Select-Object -ExpandProperty TweakId)
        throw "ExecutionPlan bloqueado; resolva os itens antes da transacao: $($ids -join ', ')"
    }
    return @($Plan.ExecutionOrder)
}

function Test-WinSlimPlannerCatalog {
    param([Parameter(Mandatory)]$CatalogTweaks)
    $ids=@{}; $issues=@()
    foreach ($t in @($CatalogTweaks)) {
        $id=Get-WinSlimPlannerTweakId $t
        if (-not $id) { $issues += [PSCustomObject]@{ Severity='Error'; Code='MissingId'; TweakId=$null; Reference=$null }; continue }
        if (Test-WinSlimPlannerMapKey $ids $id) { $issues += [PSCustomObject]@{ Severity='Error'; Code='DuplicateId'; TweakId=$id; Reference=$null } } else { $ids[$id]=$true }
    }
    foreach ($t in @($CatalogTweaks)) {
        $id=Get-WinSlimPlannerTweakId $t; if (-not $id) { continue }
        foreach ($d in @(Get-WinSlimPlannerProperty $t 'dependencies' @())) { if (-not (Test-WinSlimPlannerMapKey $ids ([string]$d))) { $issues += [PSCustomObject]@{ Severity='Error'; Code='MissingDependencyReference'; TweakId=$id; Reference=[string]$d } } }
        foreach ($c in @(Get-WinSlimPlannerProperty $t 'conflicts' @())) { if (-not (Test-WinSlimPlannerMapKey $ids ([string]$c))) { $issues += [PSCustomObject]@{ Severity='Warning'; Code='MissingConflictReference'; TweakId=$id; Reference=[string]$c } } }
    }
    return [PSCustomObject]@{ Valid=(@($issues | Where-Object { $_.Severity -eq 'Error' }).Count -eq 0); Count=@($CatalogTweaks).Count; Issues=@($issues) }
}

# ---------------------------------------------------------------------------
# Compatibilidade temporaria com a GUI atual (Fase 3): comportamento legado.
# A integracao Run-Batch -> Planner -> Transaction Manager pertence ao proximo
# subgate e nao e ativada silenciosamente nesta entrega.
# ---------------------------------------------------------------------------
function Resolve-Conflicts {
    param([string[]]$SelectedIds)
    $final=@(); $skipped=@()
    foreach ($id in @($SelectedIds)) {
        $tweak=$AllTweaks | Where-Object { $_.id -eq $id } | Select-Object -First 1
        if (-not $tweak) { continue }
        $conflict=@($tweak.conflicts) | Where-Object { $final -contains $_ }
        if ($conflict) { $skipped += "$id (conflita com $($conflict -join ', '))"; continue }
        $final += $id
    }
    if ($skipped -and (Get-Command Write-Log -ErrorAction SilentlyContinue)) { Write-Log "Itens ignorados por conflito: $($skipped -join '; ')" 'WARN' }
    return @($final)
}
