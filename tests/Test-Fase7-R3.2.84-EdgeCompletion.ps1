#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[ValidateSet('All','Identity','Forms','Services','Diagnostics','Sleep')][string]$Batch='All')
$ErrorActionPreference='Stop'
trap {Write-Host ('[FAIL] EdgeCompletion: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;exit 1}
. (Join-Path $Root 'src/UI/Native/R3_2_84/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$script:checks=0
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Text}
function Copy-Data($x){ConvertTo-Json -InputObject $x -Depth 50 | ConvertFrom-Json}
# Independent oracle transcribed from official Microsoft policy contracts, not generated from implementation.
$oracle=@(
 @('EDGE-007','AutoDiscardSleepingTabsEnabled',1,120),@('EDGE-009','SyncDisabled',1,77),
 @('EDGE-010','BrowserSignin',0,77),@('EDGE-013','ShowMicrosoftRewards',0,88),
 @('EDGE-014','AutofillAddressEnabled',0,77),@('EDGE-015','AutofillCreditCardEnabled',0,77),
 @('EDGE-017','WebToBrowserSignInEnabled',0,133),@('EDGE-018','UrlDiagnosticDataEnabled',0,122),
 @('EDGE-021','Microsoft365CopilotChatIconEnabled',0,139),@('EDGE-022','NetworkPredictionOptions',2,77),
 @('EDGE-023','NewTabPagePrerenderEnabled',0,85),@('EDGE-026','TextPredictionEnabled',0,104),
 @('EDGE-027','VisualSearchEnabled',0,95),@('EDGE-028','AutofillMembershipsEnabled',0,110),
 @('EDGE-029','MicrosoftEditorProofingEnabled',0,105),@('EDGE-030','PaymentMethodQueryEnabled',0,80),
 @('EDGE-031','DiagnosticData',1,122)
)
$ids=@($oracle | ForEach-Object {$_[0]})
$advertised=@((Invoke-WinSlimBridgeAction -Name handshake).registryApplicationIds)
Check (@($ids | Where-Object {$_ -notin $advertised}).Count -eq 0) 'UI handshake advertises every reviewed new contract'
if($Batch -ne 'All'){
 $selected=switch($Batch){'Identity'{@('EDGE-009','EDGE-010','EDGE-017')};'Forms'{@('EDGE-014','EDGE-015','EDGE-028','EDGE-030')};'Services'{@('EDGE-013','EDGE-021','EDGE-022','EDGE-023','EDGE-026','EDGE-027','EDGE-029')};'Diagnostics'{@('EDGE-018','EDGE-031')};'Sleep'{@('EDGE-007')}}
 $oracle=@($oracle | Where-Object {$_[0] -in $selected});$ids=@($oracle | ForEach-Object {$_[0]})
}
$expectedCount=$ids.Count+$(if($ids -contains 'EDGE-007'){1}else{0})
$script:edge=[pscustomobject]@{Windows=[pscustomobject]@{Build=22631;Edition='Professional';InstallationType='Client'};EdgeMajor=155}
$script:admin=$true
function Get-WinSlimEdgePolicyEnvironment {$script:edge}
function Test-WinSlimRestoreAdministrator {$script:admin}
function New-Plan($Selected){
 $expanded=@($Selected)
 if($expanded -contains 'EDGE-007' -and $expanded -notcontains 'EDGE-006'){$expanded=@('EDGE-006')+$expanded}
 [pscustomobject]@{CanExecute=$true;Fingerprint=($expanded -join ',');ExecutionOrder=@($expanded | ForEach-Object {[pscustomobject]@{TweakId=$_;Tweak=(Copy-Data $script:PresetRuntime.CatalogRuntime.ById[$_])}})}
}
$script:plan=New-Plan $ids
$scope=Get-WinSlimRegistryApplyScope $script:plan
Check ($scope.Targets.Count -eq $expectedCount -and $scope.Excluded.Count -eq 0) 'selected new contracts and any explicit sleeping-tabs dependency are reviewed'
foreach($entry in $oracle){
 $id=$entry[0];$one=New-Plan @($id);$contract=@(Get-WinSlimRegistryContract $id)
 Check ($contract[1] -ceq $entry[1] -and $contract[2] -ceq 'DWord' -and [int]$contract[3] -eq $entry[2] -and $contract[5] -ceq 'LocalMachine') ('pinned HKLM type/value '+$id)
 $script:edge.EdgeMajor=$entry[3]-1;Check (-not (Test-WinSlimEdgePolicySupport $id $script:edge)) ('below documented minimum excluded '+$id)
 $script:edge.EdgeMajor=$entry[3];Check (Test-WinSlimEdgePolicySupport $id $script:edge) ('minimum accepted '+$id)
 $script:edge.EdgeMajor=155
 foreach($field in @('Path','Name','Type','Value')){
  $bad=Copy-Data $one;$t=@($bad.ExecutionOrder | Where-Object TweakId -eq $id)[0];$t.Tweak.registry[0].$field='tampered'
  Reject {Get-WinSlimRegistryApplyScope $bad} ('unauthorized destination rejected '+$id+' '+$field)
 }
 $bad=Copy-Data $one;$t=@($bad.ExecutionOrder | Where-Object TweakId -eq $id)[0];$t.Tweak.requiresAdmin=$false
 Reject {Get-WinSlimRegistryApplyScope $bad} ('admin metadata pinned '+$id)
 $bad=Copy-Data $one;$t=@($bad.ExecutionOrder | Where-Object TweakId -eq $id)[0];$t.Tweak.risk='forged'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('risk metadata pinned '+$id)
 $bad=Copy-Data $one;$t=@($bad.ExecutionOrder | Where-Object TweakId -eq $id)[0];$t.Tweak.dependencies=@('PERF-001')
 Reject {Get-WinSlimRegistryApplyScope $bad} ('extra dependency rejected '+$id)
 $bad=Copy-Data $one;$t=@($bad.ExecutionOrder | Where-Object TweakId -eq $id)[0];$t.Tweak.conflicts=@('PERF-001')
 Reject {Get-WinSlimRegistryApplyScope $bad} ('extra conflict rejected '+$id)
}
foreach($id in @('EDGE-014','EDGE-015')){
 $script:edge.EdgeMajor=156;Check (-not (Test-WinSlimEdgePolicySupport $id $script:edge)) ('deprecated policy requires new review after validated major '+$id)
}
$script:edge.EdgeMajor=155
$missing=New-Plan @('EDGE-007');$missing.ExecutionOrder=@($missing.ExecutionOrder | Where-Object TweakId -ne 'EDGE-006')
Reject {Get-WinSlimRegistryApplyScope $missing} 'sleeping tabs dependency cannot be omitted'
$script:admin=$false;Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'no elevation excludes new policies';$script:admin=$true
$savedEdge=$script:edge;$script:edge=$null;Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'unavailable browser excludes all';$script:edge=$savedEdge
$script:edge.Windows.InstallationType='Server';Check ((Get-WinSlimRegistryApplyScope $script:plan).Targets.Count -eq 0) 'server excluded';$script:edge.Windows.InstallationType='Client'
$script:identity=[pscustomobject]@{ComputerName='Fixture';MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'}
function Get-WinSlimBackupIdentity {Copy-Data $script:identity}
function Get-WinSlimCustomValidationReport {param($Request) [pscustomobject]@{Plan=(Copy-Data $script:plan);PresetName='Edge completion fixture'}}
function Target-Key($Target){$Target.Hive+'|'+$Target.SubPath+'|'+$Target.Name}
$script:db=@{};$script:original=@{};$script:writes=0;$script:failRead=$false;$script:failBackup=$false;$script:failAt=-1;$script:attempts=0
$i=0
foreach($target in $scope.Targets){
 $state=if(($i%2)-eq 0){[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}}else{[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='9'}}
 $key=Target-Key $target;$script:db[$key]=Copy-Data $state;$script:original[$key]=Copy-Data $state;$i++
}
$script:db['sentinel']='preserved'
function Read-WinSlimPreviewRegistry {
 param($Operation)
 if($script:failRead){throw 'fixture unavailable read'}
 $path=Resolve-WinSlimPreviewRegistryPath ([string]$Operation.Path);$key=$path.Hive.ToString()+'|'+$path.SubPath+'|'+$Operation.Name
 if(-not $script:db.ContainsKey($key)){throw 'unexpected read destination'}
 $state=$script:db[$key];[pscustomobject]@{Exists=$state.Exists;Kind=$state.Kind;Value=(ConvertFrom-WinSlimRestoreValue $state)}
}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 $key=Target-Key $Target;if(-not $script:original.ContainsKey($key)){throw 'unexpected write destination'}
 if(@(Get-WinSlimBackupInventory (Join-Path $script:WinSlimBridgeRoot 'Backups/UI')).Count -eq 0){throw 'verified backup missing'}
 $script:writes++;$script:attempts++;$script:db[$key]=Copy-Data $State
 if($script:attempts -eq $script:failAt){$script:failAt=-1;throw 'partial write failure'}
}
$script:writer=${function:Write-WinSlimBackupDataFile}
function Write-WinSlimBackupDataFile {param([string]$Path,[string]$Text) if($script:failBackup){throw 'backup unavailable'};& $script:writer $Path $Text}
function Authorize {
 $script:RegistryPreviewSession=[pscustomobject]@{Token='fixture';CreatedUtc=[DateTime]::UtcNow;Request=[pscustomobject]@{selectedIds=$ids};Fingerprint=$script:plan.Fingerprint}
 New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken='fixture'})
}
function Original {
 foreach($key in $script:original.Keys){Check (Test-WinSlimRestoreEqual $script:db[$key] $script:original[$key]) ('exact original '+$key)}
 Check ($script:db['sentinel'] -ceq 'preserved') 'unrelated state preserved'
}
$tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath());$temp=Join-Path $tempBase ('WinSlimEdgeCompletion-'+[Guid]::NewGuid().ToString('N'))
$script:WinSlimBridgeRoot=$temp;$passed=$false
try {
 $p=Authorize;$expectedRisk=if(@($ids | Where-Object {$_ -in @('EDGE-009','EDGE-010','EDGE-014','EDGE-015','EDGE-028','EDGE-029')}).Count){$script:PresetRuntime.CatalogRuntime.ById['EDGE-009'].risk}else{'Baixo'}
 Check ($p.count -eq $expectedCount -and $p.machinePolicyCount -eq $expectedCount -and $p.risk -eq $expectedRisk) 'preview counts all policies and preserves actual risk'
 Check (@($p.compatibilityNotes).Count -ge $ids.Count) 'review includes applicability and lifecycle notes'
 $script:edge.EdgeMajor=0;Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token;EdgeMajor=999})} 'client version cannot bypass local compatibility recheck';$script:edge.EdgeMajor=155
 $p=Authorize
 $script:failRead=$true;Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'unavailable input prevents writes';$script:failRead=$false
 $p=Authorize;$script:failBackup=$true;Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})} 'unavailable backup prevents writes';$script:failBackup=$false
 Check ($script:writes -eq 0) 'failed preflight writes nothing'
 foreach($selection in @($ids | ForEach-Object {,@($_)})+@(,$ids)){
  $script:plan=New-Plan $selection;$p=Authorize;$n=$p.count
  $result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token});Check ($result.verified -and $result.changed -eq $n) ('Apply Verify '+($selection -join ','))
  $saved=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $result.backupId);Check ($saved.Verified -and $saved.Snapshot.CapturedCount -eq $n) 'full verified backup'
  $beforeWrites=$script:writes;$p=Authorize;$same=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token});Check ($same.verified -and $same.changed -eq 0 -and $beforeWrites -eq $script:writes) 'idempotent without writes'
  $rp=New-WinSlimRestorePreview ([pscustomobject]@{backupId=$result.backupId});$undo=Invoke-WinSlimBackupRestore ([pscustomobject]@{backupId=$result.backupId;token=$rp.token});Check $undo.verified 'Undo verified';Original
 }
 $script:plan=New-Plan $ids
 for($failure=1;$failure -le $expectedCount;$failure++){
  $script:attempts=0;$script:failAt=$failure;$p=Authorize;$result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$p.token})
  Check (-not $result.verified -and $result.recovered) ('partial write recovered '+$failure);Original
 }
 $passed=$true
} finally {
 if($passed -and [IO.Path]::GetFullPath($temp).StartsWith($tempBase.TrimEnd('\')+'\WinSlimEdgeCompletion-',[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $temp)){Remove-Item -LiteralPath $temp -Recurse -Force}
}
Write-Host ('EdgeCompletion: '+$script:checks+' behavioral checks; registry simulated; no held helper or real tweak executed.')
