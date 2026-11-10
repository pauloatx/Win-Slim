# Win-Slim Suite - FASE 5 R2
# GPU Interrupt Affinity: DevicePolicy=4 + AssignmentSetOverride REG_BINARY.
# Nao usa a mascara referência técnica 0x14 como constante. A mascara e calculada a partir
# de dois nucleos fisicos distintos pela topologia; 0x14 aparece apenas
# quando o layout real leva naturalmente a esse resultado.

function Get-WinSlimGpuPciInstances {
    $ids=@()
    try {
        if (Get-Command Get-PnpDevice -ErrorAction SilentlyContinue) {
            foreach($d in @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop)) {
                if ($d.InstanceId -and [string]$d.InstanceId -like 'PCI\*') { $ids += [string]$d.InstanceId }
            }
        }
    } catch { }
    if ($ids.Count -eq 0) {
        try {
            foreach($d in @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)) {
                if ($d.PNPDeviceID -and [string]$d.PNPDeviceID -like 'PCI\*') { $ids += [string]$d.PNPDeviceID }
            }
        } catch { }
    }
    return @($ids | Select-Object -Unique)
}

function Test-WinSlimByteArrayEqual {
    param($A,$B)
    if ($null -eq $A -and $null -eq $B) { return $true }
    if ($null -eq $A -or $null -eq $B) { return $false }
    $aa=[byte[]]$A; $bb=[byte[]]$B
    if ($aa.Length -ne $bb.Length) { return $false }
    for($i=0;$i -lt $aa.Length;$i++){ if($aa[$i] -ne $bb[$i]){return $false} }
    return $true
}

function Get-WinSlimGpuAffinityPath {
    param([Parameter(Mandatory)][string]$RegistryRoot,[Parameter(Mandatory)][string]$InstanceId)
    return "$RegistryRoot\$InstanceId\Device Parameters\Interrupt Management\Affinity Policy"
}

function Invoke-GpuInterruptAffinityProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('Apply','Undo')][string]$Action='Apply',
        [string[]]$InstanceIds=@(),
        [string]$RegistryRoot='HKLM:\SYSTEM\CurrentControlSet\Enum',
        [Nullable[UInt64]]$AssignmentMask=$null,
        $Topology=$null,
        $BackupData=$null
    )

    $errorMsg=$null; $warningMsg=$null; $changed=$false; $referenceState=@(); $after=@(); $maskDecision=$null
    try {
        if ($Action -eq 'Apply') {
            if (-not $Topology) { $Topology=Get-WinSlimProcessorTopology }
            $logical=if($Topology.PSObject.Properties.Name -contains 'LogicalProcessorCount'){[int]$Topology.LogicalProcessorCount}else{0}
            if($logical -lt 8){
                return New-ProviderResult -Id $Id -Action $Action -Success $true -Changed $false -StateBefore @() -StateAfter @() `
                    -Verification ([PSCustomObject]@{Applicable=$false;Success=$true;Checks=@([PSCustomObject]@{Type='GpuInterruptAffinity';Target='CPU topology';Expected='>=8 logical processors';Actual=$logical;Pass=$true})}) `
                    -Restart 'None' -WarningMessage 'Menos de 8 processadores logicos; afinidade de interrupcao da GPU ignorada.'
            }
            if($null -eq $AssignmentMask){
                $maskDecision=Get-WinSlimSuggestedGpuInterruptMask -Topology $Topology
                if(-not $maskDecision.Applicable){
                    return New-ProviderResult -Id $Id -Action $Action -Success $true -Changed $false -StateBefore @() -StateAfter @() `
                        -Verification ([PSCustomObject]@{Applicable=$false;Success=$true;Checks=@([PSCustomObject]@{Type='GpuInterruptAffinity';Target='CPU topology';Expected='mascara deterministica';Actual=$maskDecision.Reason;Pass=$true})}) `
                        -Restart 'None' -WarningMessage $maskDecision.Reason
                }
                [UInt64]$mask=[UInt64]$maskDecision.Mask
            } else { [UInt64]$mask=[UInt64]$AssignmentMask.Value }
            if($mask -eq 0){ throw 'AssignmentSetOverride nao pode ser mascara zero.' }
            $maskBytes=[BitConverter]::GetBytes($mask)

            $ids=@($InstanceIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            if($ids.Count -eq 0){ $ids=@(Get-WinSlimGpuPciInstances) }
            if($ids.Count -eq 0){
                return New-ProviderResult -Id $Id -Action $Action -Success $true -Changed $false -StateBefore @() -StateAfter @() `
                    -Verification ([PSCustomObject]@{Applicable=$false;Success=$true;Checks=@([PSCustomObject]@{Type='GpuInterruptAffinity';Target='Display PCI';Expected='GPU PCI detectavel';Actual='nenhuma';Pass=$true})}) `
                    -Restart 'None' -WarningMessage 'Nenhuma GPU PCI detectavel; tweak ignorado.'
            }

            foreach($instance in $ids){
                $path=Get-WinSlimGpuAffinityPath -RegistryRoot $RegistryRoot -InstanceId $instance
                $bPolicy=Backup-RegistryValue -Path $path -Name 'DevicePolicy'
                $bMask=Backup-RegistryValue -Path $path -Name 'AssignmentSetOverride'
                $referenceState += [PSCustomObject]@{InstanceId=$instance;Path=$path;DevicePolicy=$bPolicy;AssignmentSetOverride=$bMask}
                $needPolicy=(-not $bPolicy.Exists) -or ([int64]$bPolicy.Value -ne 4)
                $needMask=(-not $bMask.Exists) -or (-not (Test-WinSlimByteArrayEqual $bMask.Value $maskBytes))
                if($needPolicy){ Set-RegistryValue -Path $path -Name 'DevicePolicy' -Value 4 -Type 'DWord'; $changed=$true }
                if($needMask){ Set-RegistryValue -Path $path -Name 'AssignmentSetOverride' -Value $maskBytes -Type 'Binary'; $changed=$true }
            }
        } else {
            if(-not $BackupData){ throw "Undo de '$Id' requer BackupData persistido." }
            $referenceState=@($BackupData)
            foreach($entry in $referenceState){
                Restore-RegistryValue -StateBefore $entry.DevicePolicy
                Restore-RegistryValue -StateBefore $entry.AssignmentSetOverride
                $changed=$true
            }
        }
    } catch { $errorMsg=$_.Exception.Message }

    $checks=@()
    try {
        if($Action -eq 'Apply'){
            [UInt64]$expectedMask=if($null -ne $AssignmentMask){[UInt64]$AssignmentMask.Value}else{[UInt64]$maskDecision.Mask}
            $expectedBytes=[BitConverter]::GetBytes($expectedMask)
            foreach($entry in @($referenceState)){
                $p=Get-RegistryState -Path $entry.Path -Name 'DevicePolicy'
                $m=Get-RegistryState -Path $entry.Path -Name 'AssignmentSetOverride'
                $after += [PSCustomObject]@{InstanceId=$entry.InstanceId;Path=$entry.Path;DevicePolicy=$p;AssignmentSetOverride=$m}
                $pPass=$p.Exists -and ([int64]$p.Value -eq 4)
                $mPass=$m.Exists -and (Test-WinSlimByteArrayEqual $m.Value $expectedBytes)
                $checks += [PSCustomObject]@{Type='Registry';Target="$($entry.Path)\DevicePolicy";Expected=4;Actual=$(if($p.Exists){$p.Value}else{'<ausente>'});Pass=$pPass}
                $checks += [PSCustomObject]@{Type='Registry';Target="$($entry.Path)\AssignmentSetOverride";Expected=('0x{0:X}' -f $expectedMask);Actual=$(if($m.Exists){[BitConverter]::ToString([byte[]]$m.Value)}else{'<ausente>'});Pass=$mPass}
            }
        } else {
            foreach($entry in @($referenceState)){
                $p=Get-RegistryState -Path $entry.Path -Name 'DevicePolicy'
                $m=Get-RegistryState -Path $entry.Path -Name 'AssignmentSetOverride'
                $after += [PSCustomObject]@{InstanceId=$entry.InstanceId;Path=$entry.Path;DevicePolicy=$p;AssignmentSetOverride=$m}
                $pPass=if($entry.DevicePolicy.Exists){$p.Exists -and ([string]$p.Type -eq [string]$entry.DevicePolicy.Type) -and ([string]$p.Value -eq [string]$entry.DevicePolicy.Value)}else{-not $p.Exists}
                $mPass=if($entry.AssignmentSetOverride.Exists){$m.Exists -and ([string]$m.Type -eq [string]$entry.AssignmentSetOverride.Type) -and (Test-WinSlimByteArrayEqual $m.Value $entry.AssignmentSetOverride.Value)}else{-not $m.Exists}
                $checks += [PSCustomObject]@{Type='Registry';Target="$($entry.Path)\DevicePolicy";Expected='estado original';Actual=$(if($p.Exists){$p.Value}else{'<ausente>'});Pass=$pPass}
                $checks += [PSCustomObject]@{Type='Registry';Target="$($entry.Path)\AssignmentSetOverride";Expected='bytes originais';Actual=$(if($m.Exists){[BitConverter]::ToString([byte[]]$m.Value)}else{'<ausente>'});Pass=$mPass}
            }
        }
    } catch { if(-not $errorMsg){$errorMsg=$_.Exception.Message} }

    $verifyOk=(-not $errorMsg) -and @($checks).Count -gt 0 -and (-not (@($checks)|Where-Object{-not $_.Pass}))
    return New-ProviderResult -Id $Id -Action $Action -Success ([bool]$verifyOk) -Changed $changed -StateBefore @($referenceState) -StateAfter @($after) `
        -Verification ([PSCustomObject]@{Applicable=$true;Success=[bool]$verifyOk;Checks=@($checks)}) -Restart 'Reboot' -WarningMessage $warningMsg -ErrorMessage $errorMsg
}
