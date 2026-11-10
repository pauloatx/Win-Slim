#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
trap {Write-Host ('[ERRO] Edge: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;Write-Host $_.ScriptStackTrace;exit 1}
. (Join-Path $Root 'src/UI/Native/R3_2_83/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$script:checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] Edge: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}
function Copy-Data($Object){ConvertTo-Json -InputObject $Object -Depth 32 | ConvertFrom-Json}
$script:environment=[pscustomobject]@{Windows=[pscustomobject]@{Build=22631;Edition='Core';InstallationType='Client'};EdgeMajor=120}
$script:admin=$true
function Get-WinSlimEdgePolicyEnvironment {$script:environment}
function Test-WinSlimRestoreAdministrator {$script:admin}
$ids=@('EDGE-001','EDGE-002')
$plan=[pscustomobject]@{CanExecute=$true;Fingerprint='edge-fixture';ExecutionOrder=@($ids | ForEach-Object {[pscustomobject]@{TweakId=$_;Tweak=$script:PresetRuntime.CatalogRuntime.ById[$_]}})}
foreach($os in @('10','11')){
 $planned=New-WinSlimExecutionPlan -CatalogTweaks $script:AllTweaks -SelectedIds $ids -Context @{OS=$os;IsAdmin=$true} -ConflictPolicy Block
 Check ($planned.CanExecute -and (Get-WinSlimRegistryApplyScope $planned).Targets.Count -eq 2) ('Planner real autoriza o lote no Windows '+$os)
}
$scope=Get-WinSlimRegistryApplyScope $plan
Check ($scope.Targets.Count -eq 2 -and $scope.Excluded.Count -eq 0) 'dois contratos do catalogo real liberados'
foreach($t in $scope.Targets){Check ($t.Hive -ceq 'LocalMachine' -and $t.SubPath -ieq 'SOFTWARE\Policies\Microsoft\Edge' -and $t.Desired.Kind -ceq 'DWord' -and $t.Desired.Value -ceq '0') ('destino e DWORD revisados: '+$t.TweakId)}
$mixed=Copy-Data $plan
$mixed.ExecutionOrder+= [pscustomobject]@{TweakId='UI-007';Tweak=$script:PresetRuntime.CatalogRuntime.ById['UI-007']}
$mixedScope=Get-WinSlimRegistryApplyScope $mixed
Check ($mixedScope.Targets.Count -eq 3 -and @($mixedScope.Targets | Where-Object {$_.Hive -ceq 'LocalMachine'}).Count -eq 2 -and @($mixedScope.Targets | Where-Object {$_.Hive -ceq 'CurrentUser'}).Count -eq 1) 'lote misto preserva o hive de cada contrato'
$bad=Copy-Data $mixed;$bad.ExecutionOrder[2].Tweak.registry[0].Path='HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Reject {Get-WinSlimRegistryApplyScope $bad} 'novo lote nao autoriza HKLM para os contratos anteriores'
foreach($index in @(0,1)){
 foreach($field in @('Path','Name','Type','Value')){
  $bad=Copy-Data $plan;$bad.ExecutionOrder[$index].Tweak.registry[0].$field='Unauthorized'
  Reject {Get-WinSlimRegistryApplyScope $bad} ('alteracao de contrato bloqueada '+$index+' '+$field)
 }
 $bad=Copy-Data $plan;$bad.ExecutionOrder[$index].Tweak.registry[0].Path='HKCU:\SOFTWARE\Policies\Microsoft\Edge'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('troca de hive bloqueada '+$index)
 $bad=Copy-Data $plan;$bad.ExecutionOrder[$index].Tweak.requiresAdmin=$false
 Reject {Get-WinSlimRegistryApplyScope $bad} ('contrato de permissao bloqueado '+$index)
 $bad=Copy-Data $plan;$bad.ExecutionOrder[$index].Tweak.restartScope='None'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('escopo de reinicio bloqueado '+$index)
}
$script:environment.EdgeMajor=77
$limited=Get-WinSlimRegistryApplyScope $plan
Check ($limited.Targets.Count -eq 1 -and $limited.Targets[0].TweakId -ceq 'EDGE-002' -and $limited.Excluded.Count -eq 1) 'versao 77 aceita apenas BackgroundMode'
foreach($version in @(0,76)){$script:environment.EdgeMajor=$version;Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) ('Edge ausente/antigo excluido: '+$version)}
$script:environment.EdgeMajor=88;Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 2) 'versao minima 88 aceita Startup Boost'
$script:environment.Windows.InstallationType='Server';Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'Server nao confirmado excluido'
$script:environment.Windows.InstallationType='Client';$script:environment.Windows.Build=9600;Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'Windows anterior ao 10 excluido'
$script:environment.Windows.Build=22631;$script:environment.Windows | Add-Member NoteProperty DetectionError 'fixture'
Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'falha de deteccao exclui os ajustes'
$script:environment.Windows.PSObject.Properties.Remove('DetectionError')
$script:admin=$false;Check ((Get-WinSlimRegistryApplyScope $plan).Targets.Count -eq 0) 'falta de elevacao exclui politicas de maquina';$script:admin=$true
# Full production authorization/backup/apply/restore flow, with only Registry IO replaced by a dictionary.
$script:identity=[pscustomobject]@{ComputerName='EdgeFixture';MachineGuid='EdgeFixture';UserSid='EdgeFixture';OSVersion='10.0';RegistryView='Registry64'}
function Get-WinSlimBackupIdentity {$script:identity}
function Get-WinSlimCustomValidationReport {param($Request) [pscustomobject]@{Plan=(Copy-Data $plan);PresetName='EdgeFixture'}}
$script:absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
$script:enabled=[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='1'}
$script:original=@{StartupBoostEnabled=(Copy-Data $script:absent);BackgroundModeEnabled=(Copy-Data $script:enabled)}
$script:db=Copy-Data ([pscustomobject]$script:original);$script:writes=0;$script:failRead=$false;$script:failOnce=$false;$script:failBackup=$false
function Read-WinSlimPreviewRegistry {
 param($Operation)
 if($script:failRead){throw 'fixture read failed'}
 $state=$script:db.([string]$Operation.Name)
 if($null -eq $state){throw 'fixture target unknown'}
 [pscustomobject]@{Exists=$state.Exists;Kind=$state.Kind;Value=(ConvertFrom-WinSlimRestoreValue $state)}
}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 # No writes are accepted unless a complete verified backup has actually been persisted.
 $found=Get-WinSlimBackupInventory (Join-Path $script:WinSlimBridgeRoot 'Backups/UI')
 if(@($found.Items).Count -lt 1){throw 'BACKUP REQUIRED BEFORE WRITE'}
 $script:writes++;$script:db.([string]$Target.Name)=Copy-Data $State
 if($script:failOnce -and $Target.TweakId -ceq 'EDGE-002'){$script:failOnce=$false;throw 'fixture partial write failure'}
}
$script:originalDataWriter=${function:Write-WinSlimBackupDataFile}
function Write-WinSlimBackupDataFile {param([string]$Path,[string]$Text) if($script:failBackup){throw 'fixture backup persistence failed'};& $script:originalDataWriter $Path $Text}
function Authorize-Edge {
 $script:RegistryPreviewSession=[pscustomobject]@{Token='edge-preview';CreatedUtc=[DateTime]::UtcNow;Request=[pscustomobject]@{selectedIds=$ids};Fingerprint=$plan.Fingerprint}
 New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken='edge-preview'})
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimEdgeFixture-'+[Guid]::NewGuid().ToString('N'));$script:WinSlimBridgeRoot=$temp
try{
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token='missing'})} 'sem autorizacao nao aplica'
 $preview=Authorize-Edge
 Check ($preview.count -eq 2 -and $preview.machinePolicyCount -eq 2 -and $preview.changes -eq 2) 'previa indica duas politicas de maquina'
 $script:environment.EdgeMajor=0
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token;EdgeMajor=999})} 'compatibilidade e repetida antes da escrita; versao enviada pelo cliente ignorada'
 Check ($script:writes -eq 0) 'nenhuma escrita apos perder compatibilidade'
 $script:environment.EdgeMajor=120;$preview=Authorize-Edge;$script:failRead=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'falha de leitura impede escrita';$script:failRead=$false
 $preview=Authorize-Edge;$script:failBackup=$true
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'backup nao persistido impede aplicacao';$script:failBackup=$false
 Check ($script:writes -eq 0) 'backup com falha nao escreve politicas'
 $preview=Authorize-Edge
 $result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token;Path='HKLM:\Unauthorized';Value=1})
 Check ($result.verified -and $result.changed -eq 2 -and $result.errors.Count -eq 0) 'lote aplicado e verificado'
 $firstBackup=$result.backupId
 $saved=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $firstBackup)
 Check ($saved.Verified -and $saved.Snapshot.CapturedCount -eq 2 -and $saved.Snapshot.ExcludedCount -eq 0) 'backup completo verificado em disco'
 $back=@(Get-WinSlimRestoreTargets $saved.Snapshot $script:PresetRuntime.CatalogRuntime.ById $script:identity)
 Check ($back.Count -eq 2 -and -not $back[0].Desired.Exists -and $back[1].Desired.Kind -ceq 'DWord' -and $back[1].Desired.Value -ceq '1') 'backup guarda ausencia e DWORD 1 originais'
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'autorizacao consumida nao reutilizavel'
 $before=$script:writes;$preview=Authorize-Edge;$same=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})
 Check ($same.verified -and $same.changed -eq 0 -and $same.unchanged -eq 2 -and $script:writes -eq $before) 'reaplicar nao escreve estados iguais'
 $rp=New-WinSlimRestorePreview ([pscustomobject]@{backupId=$firstBackup})
 $restored=Invoke-WinSlimBackupRestore ([pscustomobject]@{backupId=$firstBackup;token=$rp.token})
 Check ($restored.verified -and $restored.changed -eq 2) 'restauracao real do motor verifica ambos os destinos simulados'
 foreach($name in $script:original.Keys){Check (Test-WinSlimRestoreEqual $script:db.$name $script:original[$name]) ('estado original restaurado '+$name)}
 $preview=Authorize-Edge;$script:failOnce=$true
 $failed=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})
 Check (-not $failed.verified -and $failed.recovered) 'falha parcial apos escrever provoca recuperacao'
 foreach($name in $script:original.Keys){Check (Test-WinSlimRestoreEqual $script:db.$name $script:original[$name]) ('recuperacao devolve estado original '+$name)}
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host ('Edge: '+$script:checks+' verificacoes; Registro simulado, nenhum ajuste de producao aplicado.')
