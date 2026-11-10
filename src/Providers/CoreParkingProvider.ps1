# Win-Slim Suite - FASE 5 R2
# Provider dedicado para CPMINCORES (Core Parking minimum cores).
# Usa a mesma API powercfg ja validada na Fase 2.1B, mas com contrato
# especifico, idempotencia, applicability explicita e seam de teste seguro.

$script:WinSlimCoreParkingSubgroupGuid = '54533251-82be-4824-96c1-47b60b740d00'
$script:WinSlimCoreParkingSettingGuid   = '0cc5b647-c1df-4637-891a-dec35c318583'

function Get-CoreParkingState {
    param(
        [scriptblock]$StateReader = $null,
        [string]$SubgroupGuid = $script:WinSlimCoreParkingSubgroupGuid,
        [string]$SettingGuid = $script:WinSlimCoreParkingSettingGuid
    )
    if ($StateReader) { return (& $StateReader $SubgroupGuid $SettingGuid) }
    return Get-PowerSettingIndex -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
}

function Set-CoreParkingState {
    param(
        [Parameter(Mandatory)][int]$AcValue,
        [Parameter(Mandatory)][int]$DcValue,
        [scriptblock]$StateWriter = $null,
        [string]$SubgroupGuid = $script:WinSlimCoreParkingSubgroupGuid,
        [string]$SettingGuid = $script:WinSlimCoreParkingSettingGuid
    )
    if ($StateWriter) {
        & $StateWriter $SubgroupGuid $SettingGuid $AcValue $DcValue
        return
    }
    Set-PowerSettingIndex -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid -AcValue $AcValue -DcValue $DcValue
}

function Invoke-CoreParkingProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('Apply','Undo')][string]$Action = 'Apply',
        [ValidateRange(0,100)][int]$TargetAc = 100,
        [ValidateRange(0,100)][int]$TargetDc = 100,
        $BackupData = $null,
        [scriptblock]$StateReader = $null,
        [scriptblock]$StateWriter = $null,
        [string]$SubgroupGuid = $script:WinSlimCoreParkingSubgroupGuid,
        [string]$SettingGuid = $script:WinSlimCoreParkingSettingGuid
    )

    $errorMsg = $null
    $warningMsg = $null
    $changed = $false
    $referenceState = $null
    $after = $null

    try {
        if ($Action -eq 'Apply') {
            $referenceState = Get-CoreParkingState -StateReader $StateReader -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
            if (-not $referenceState -or -not [bool]$referenceState.Queryable) {
                $verification = [PSCustomObject]@{
                    Applicable = $false
                    Success = $true
                    Checks = @([PSCustomObject]@{ Type='PowerCfg'; Target='CPMINCORES'; Expected='AC/DC consultaveis'; Actual='indeterminado'; Pass=$true })
                }
                return New-ProviderResult -Id $Id -Action $Action -Success $true -Changed $false -StateBefore $referenceState -StateAfter $referenceState `
                    -Verification $verification -Restart 'None' -WarningMessage 'CPMINCORES nao pode ser consultado neste plano/sistema; tweak ignorado com seguranca.'
            }
            if ([int64]$referenceState.AC -ne $TargetAc -or [int64]$referenceState.DC -ne $TargetDc) {
                Set-CoreParkingState -AcValue $TargetAc -DcValue $TargetDc -StateWriter $StateWriter -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
                $changed = $true
            }
        } else {
            if (-not $BackupData) { throw "Undo de '$Id' requer BackupData persistido para restaurar AC/DC originais de CPMINCORES." }
            $referenceState = $BackupData
            if (-not [bool]$referenceState.Queryable) { throw "Backup de '$Id' nao contem indices CPMINCORES restauraveis." }
            $current = Get-CoreParkingState -StateReader $StateReader -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
            if (-not $current -or -not [bool]$current.Queryable -or [int64]$current.AC -ne [int64]$referenceState.AC -or [int64]$current.DC -ne [int64]$referenceState.DC) {
                Set-CoreParkingState -AcValue ([int]$referenceState.AC) -DcValue ([int]$referenceState.DC) -StateWriter $StateWriter -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid
                $changed = $true
            }
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    try { $after = Get-CoreParkingState -StateReader $StateReader -SubgroupGuid $SubgroupGuid -SettingGuid $SettingGuid } catch { $after = $null; if (-not $errorMsg) { $errorMsg = $_.Exception.Message } }

    $expAc = if ($Action -eq 'Apply') { $TargetAc } else { [int]$referenceState.AC }
    $expDc = if ($Action -eq 'Apply') { $TargetDc } else { [int]$referenceState.DC }
    $verifyOk = (-not $errorMsg) -and $after -and [bool]$after.Queryable -and ([int64]$after.AC -eq $expAc) -and ([int64]$after.DC -eq $expDc)
    $verification = [PSCustomObject]@{
        Applicable = $true
        Success = [bool]$verifyOk
        Checks = @([PSCustomObject]@{
            Type='PowerCfg'; Target="CPMINCORES ($SettingGuid)"; Expected="AC=$expAc;DC=$expDc"
            Actual=$(if ($after) { "AC=$($after.AC);DC=$($after.DC)" } else { '<indeterminado>' }); Pass=[bool]$verifyOk
        })
    }

    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]$verifyOk) -Changed $changed `
        -StateBefore $referenceState -StateAfter $after -Verification $verification -Restart 'None' `
        -WarningMessage $warningMsg -ErrorMessage $errorMsg
}
