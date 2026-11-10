#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
trap {Write-Host ('[ERRO] EndTask: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;exit 1}
. (Join-Path $Root 'src/UI/Native/R3_2_75/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$script:checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] EndTask: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Copy-Data($x){ConvertTo-Json -InputObject $x -Depth 32 | ConvertFrom-Json}
$script:environment=[pscustomobject]@{Build=22631;Edition='Core';InstallationType='Client'}
function Get-WinSlimRegistryEnvironment {$script:environment}
$plan=[pscustomobject]@{CanExecute=$true;Fingerprint='endtask-fixture';ExecutionOrder=@([pscustomobject]@{TweakId='UI-006';Tweak=$script:PresetRuntime.CatalogRuntime.ById['UI-006']})}
$scope=Get-WinSlimRegistryApplyScope $plan
Check ($scope.Targets.Count -eq 1 -and $scope.Targets[0].Hive -ceq 'CurrentUser' -and $scope.Targets[0].Name -ceq 'TaskbarEndTask' -and $scope.Targets[0].Desired.Value -ceq '1') 'contrato real HKCU DWORD 1'
foreach($field in @('Path','Name','Type','Value')){
 $bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.registry[0].$field='Unauthorized'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('adulteracao bloqueada '+$field)
}
$bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.registry[0].Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
Reject {Get-WinSlimRegistryApplyScope $bad} 'troca para HKLM rejeitada'
foreach($build in @(19045,22000,22621,22630,22631,26100,26200)){
 $script:environment.Build=$build;$actual=Get-WinSlimRegistryApplyScope $plan
 Check ($actual.Targets.Count -eq [int]($build -ge 22631)) ('limite conservador build '+$build)
 if($build -lt 22631){Check ($actual.Excluded.Count -eq 1 -and $actual.Excluded[0].Reason.Contains('22631')) 'exclusao explica compatibilidade'}
}
$script:environment.Build=22631;$script:environment.InstallationType='Server'
Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'Server excluido'
$script:environment.InstallationType='Client';$script:environment | Add-Member NoteProperty DetectionError 'fixture'
Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'deteccao falha excluida'
$script:environment=$null
Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'deteccao ausente excluida'
$script:environment=[pscustomobject]@{Build=22631;Edition='Core';InstallationType='Client'}
foreach($os in @('10','11')){
 $real=New-WinSlimExecutionPlan -CatalogTweaks $script:AllTweaks -SelectedIds @('UI-006') -Context @{OS=$os;IsAdmin=$true} -ConflictPolicy Block
 Check ((Get-WinSlimRegistryApplyScope $real).Targets.Count -eq [int]($os -eq '11')) ('Planner real Windows '+$os)
}
$script:identity=[pscustomobject]@{ComputerName='Fixture';MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'}
function Get-WinSlimBackupIdentity {Copy-Data $script:identity}
function Test-WinSlimRestoreAdministrator {$true}
function Get-WinSlimCustomValidationReport {param($Request) [pscustomobject]@{Plan=(Copy-Data $plan);PresetName='EndTask fixture'}}
$absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
$off=[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='0'}
$script:state=Copy-Data $absent;$script:writes=0;$script:failRead=$false;$script:failOnce=$false;$script:failBackup=$false
function Read-WinSlimPreviewRegistry {
 param($Operation)
 if($script:failRead){throw 'fixture read failed'}
 if($Operation.Name -cne 'TaskbarEndTask'){throw 'unexpected destination'}
 [pscustomobject]@{Exists=$script:state.Exists;Kind=$script:state.Kind;Value=(ConvertFrom-WinSlimRestoreValue $script:state)}
}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 $inventory=@(Get-WinSlimBackupInventory (Join-Path $script:WinSlimBridgeRoot 'Backups/UI'))
 if($inventory.Count -lt 1 -or $inventory[0].Items.Count -lt 1){throw 'verified backup missing'}
 $script:writes++;$script:state=Copy-Data $State
 if($script:failOnce){$script:failOnce=$false;throw 'partial write'}
}
$script:originalWriter=${function:Write-WinSlimBackupDataFile}
function Write-WinSlimBackupDataFile {param([string]$Path,[string]$Text) if($script:failBackup){throw 'disk failed'};& $script:originalWriter $Path $Text}
function Authorize {
 $script:RegistryPreviewSession=[pscustomobject]@{Token='fixture';CreatedUtc=[DateTime]::UtcNow;Request=[pscustomobject]@{selectedIds=@('UI-006')};Fingerprint=$plan.Fingerprint}
 New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken='fixture'})
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimEndTask-'+[guid]::NewGuid().ToString('N'));$script:WinSlimBridgeRoot=$temp
try{
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token='missing'})} 'sem token rejeitado'
 $p=Authorize;$script:environment.Build=19045
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token;Build=26200})} 'rechecagem local ignora build enviada pelo cliente'
 Check ($script:writes -eq 0) 'incompatibilidade nao escreve'
 $script:environment.Build=22631;$p=Authorize;$script:failRead=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'falha de leitura bloqueia';$script:failRead=$false
 $p=Authorize;$script:failBackup=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'falha de backup bloqueia';$script:failBackup=$false
 Check ($script:writes -eq 0) 'falhas antes da escrita preservam estado'
 foreach($original in @($absent,$off)){
  $script:state=Copy-Data $original;$p=Authorize
  Check ($p.count -eq 1 -and $p.machinePolicyCount -eq 0) 'previa identifica preferencia individual'
  $result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check ($result.verified -and $result.changed -eq 1 -and $script:state.Kind -ceq 'DWord' -and $script:state.Value -ceq '1') 'Apply e Verify reais com IO simulado'
  $saved=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $result.backupId)
  $back=@(Get-WinSlimRestoreTargets $saved.Snapshot $script:PresetRuntime.CatalogRuntime.ById $script:identity)
  Check ($saved.Verified -and $back.Count -eq 1 -and (Test-WinSlimRestoreEqual $back[0].Desired $original)) 'snapshot preserva existencia tipo e valor'
  Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'token nao reutilizavel'
  $before=$script:writes;$p=Authorize;$same=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check ($same.verified -and $same.changed -eq 0 -and $same.unchanged -eq 1 -and $script:writes -eq $before) 'idempotencia sem escrita'
  $rp=New-WinSlimRestorePreview ([pscustomobject]@{backupId=$result.backupId})
  $undo=Invoke-WinSlimBackupRestore ([pscustomobject]@{backupId=$result.backupId;token=$rp.token})
  Check ($undo.verified -and (Test-WinSlimRestoreEqual $script:state $original)) 'Undo restaura estado original exato'
  $p=Authorize;$script:failOnce=$true;$failed=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check (-not $failed.verified -and $failed.recovered -and (Test-WinSlimRestoreEqual $script:state $original)) 'escrita parcial recupera original'
 }
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host ('EndTask: '+$script:checks+' verificacoes. IO de Registro simulado; nenhuma alteracao no Windows.')
