<#
    Win-Slim Suite - Game/Workload Priority Provider (Fase 5 R1)

    Parametriza o mecanismo IFEO\PerfOptions recuperado do backend Seal:
      CpuPriorityClass = DWORD 3 (High)

    O provider NAO faz backup próprio: delega integralmente ao
    RegistryProvider, que já passou no gate de conformidade da Fase 2.1B e
    restaura existência/tipo/valor originais no Undo.
#>

function Get-WinSlimGamePriorityRegistryOps {
    param(
        [Parameter(Mandatory)][string[]]$Executables,
        [string]$BasePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )

    $ops = @()
    foreach ($exe in @($Executables)) {
        if ([string]::IsNullOrWhiteSpace([string]$exe)) { continue }
        $leaf = ([string]$exe).Trim()
        $ops += [PSCustomObject]@{
            Path  = (($BasePath.TrimEnd('\')) + '\' + $leaf + '\PerfOptions')
            Name  = 'CpuPriorityClass'
            Value = 3
            Type  = 'DWord'
        }
    }
    return @($ops)
}

function Invoke-GamePriorityProvider {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string[]]$Executables,
        [ValidateSet('Apply','Undo')][string]$Action = 'Apply',
        $BackupData = $null,
        [string]$BasePath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    )

    $ops = @(Get-WinSlimGamePriorityRegistryOps -Executables $Executables -BasePath $BasePath)
    if ($ops.Count -eq 0) {
        return New-ProviderResult -Id $Id -Action $Action -Success $false -Changed $false `
            -Verification ([PSCustomObject]@{ Success=$false; Checks=@() }) `
            -WarningMessage 'Nenhum executável válido foi informado ao GamePriorityProvider.' `
            -ErrorMessage 'Operação IFEO vazia.'
    }

    return Invoke-RegistryProvider -Id $Id -RegistryOps $ops -Action $Action -BackupData $BackupData
}
