param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
trap {
 Write-Host ('[ERRO] RegistryApply: '+$_.Exception.ToString())
 Write-Host $_.InvocationInfo.PositionMessage
 Write-Host $_.ScriptStackTrace
 exit 1
}
. (Join-Path $Root 'src/UI/Native/R3_2_65/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$script:checks=0
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++;Write-Host ('[OK] RegistryApply: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action}catch{$rejected=$true};Require $rejected $Message}
function Copy-Data($x){ConvertTo-Json -InputObject $x -Depth 32 | ConvertFrom-Json}
$ids=@('PERF-001','UI-007','UI-008','UI-009','UI-016')
$entries=@($ids | ForEach-Object {[pscustomobject]@{TweakId=$_;Tweak=$script:PresetRuntime.CatalogRuntime.ById[$_]}})
$plan=[pscustomobject]@{CanExecute=$true;Fingerprint='fixture-plan';ExecutionOrder=$entries}
foreach($os in @('10','11')){
 $realPlan=New-WinSlimExecutionPlan -CatalogTweaks $script:AllTweaks -SelectedIds $ids -Context @{OS=$os;IsAdmin=$true} -ConflictPolicy Block
 Require ($realPlan.CanExecute -and (Get-WinSlimRegistryApplyScope $realPlan).Targets.Count -eq 5) ('Planner real autoriza cinco ajustes no Windows '+$os)
}
$scope=Get-WinSlimRegistryApplyScope $plan
Require ($scope.Targets.Count -eq 5 -and $scope.Excluded.Count -eq 0) 'cinco contratos conferidos contra o catalogo real'
foreach($id in $ids){$one=Copy-Data $plan;$one.ExecutionOrder=@($one.ExecutionOrder | Where-Object {$_.TweakId -eq $id});Require ((Get-WinSlimRegistryApplyScope $one).Targets.Count -eq 1) ('escopo individual '+$id)}
$other=Copy-Data $plan;$other.ExecutionOrder+= [pscustomobject]@{TweakId='PERF-016';Tweak=$script:PresetRuntime.CatalogRuntime.ById['PERF-016']}
$other.ExecutionOrder+=[pscustomobject]@{TweakId='TEST-SERVICE';Tweak=[pscustomobject]@{type='service';name='Service'}}
$otherScope=Get-WinSlimRegistryApplyScope $other
Require ($otherScope.Targets.Count -eq 5 -and $otherScope.Excluded.Count -eq 2) 'hardware e servicos excluidos explicitamente'
foreach($change in @('Path','Name','Type','Value')){
 $bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.registry[0].$change='Unauthorized'
 Reject {Get-WinSlimRegistryApplyScope $bad} ('contrato adulterado rejeitado: '+$change)
}
$bad=Copy-Data $plan;$bad.CanExecute=$false;Reject {Get-WinSlimRegistryApplyScope $bad} 'plano bloqueado rejeitado'
$bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.risk='Alto';Reject {Get-WinSlimRegistryApplyScope $bad} 'risco alterado rejeitado'
$bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.dependencies=@('UNAPPROVED');Reject {Get-WinSlimRegistryApplyScope $bad} 'dependencia nao aplicada rejeitada'
$bad=Copy-Data $plan;$bad.ExecutionOrder[0].Tweak.registry+= $bad.ExecutionOrder[0].Tweak.registry[0];Reject {Get-WinSlimRegistryApplyScope $bad} 'operacao extra rejeitada'
$bad=Copy-Data $plan;$bad.ExecutionOrder+=$bad.ExecutionOrder[0];Reject {Get-WinSlimRegistryApplyScope $bad} 'ID duplicado rejeitado'
# Pure transaction fixtures exercise the production algorithm without any system IO.
$absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
# Build a plain array of explicit records. Do not round-trip an array carrying
# PowerShell adapter metadata through JSON: Windows PowerShell 5.1 can expose
# a different shape on a second serialization. Copy only scalar state records.
function New-FixtureApplyTargets {
 param([switch]$AlreadyConfigured)
 foreach($source in $scope.Targets){
  $desired=Copy-Data $source.Desired
  $current=if($AlreadyConfigured){Copy-Data $source.Desired}else{Copy-Data $absent}
  [pscustomobject]@{Type=$source.Type;TweakId=$source.TweakId;DisplayName=$source.DisplayName;Path=$source.Path;Hive=$source.Hive;SubPath=$source.SubPath;Name=$source.Name;Current=$current;Desired=$desired}
 }
}
$targets=@(New-FixtureApplyTargets)
Require ($targets.Count -eq 5 -and @($targets | Where-Object {$_.PSObject.Properties.Name -notcontains 'Current'}).Count -eq 0) 'fixture inicial tem cinco registros com Current explicito' 
function Reset-State {$script:db=@{};foreach($t in $targets){$script:db[$t.Name]=Copy-Data $absent};$script:writes=0;$script:events=@();$script:stages=@()}
$reader={param($t) Copy-Data $script:db[$t.Name]}
$writer={param($t,$s) $script:writes++;$script:db[$t.Name]=Copy-Data $s}
$journal={param($s,$t) $script:stages+=$s}
$progress={param($s,$n,$total,$id) $script:events+=[pscustomobject]@{s=$s;n=$n;total=$total;id=$id}}
Reset-State;$result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $journal $progress
Require ($result.verified -and $result.changed -eq 5 -and $result.unchanged -eq 0) 'cinco alteracoes verificadas'
Require ($script:events[-1].s -eq 'Verified' -and $script:events[-1].n -eq 5) 'progresso depende das verificacoes reais'
Require ($script:stages[0] -eq 'Started' -and $script:stages[-1] -eq 'Completed') 'journal acompanha inicio e conclusao'
$same=@(New-FixtureApplyTargets -AlreadyConfigured);$script:writes=0
Require ($same.Count -eq 5 -and @($same | Where-Object {$_.PSObject.Properties.Name -notcontains 'Current'}).Count -eq 0) 'fixture de reaplicacao tem cinco registros com Current explicito'
Require (@($same | Where-Object {-not (Test-WinSlimRestoreEqual $_.Current $_.Desired)}).Count -eq 0) 'reaplicacao parte dos valores desejados'
Require (@($targets | Where-Object {$_.Current.Exists}).Count -eq 0) 'fixture de reaplicacao nao modifica os estados originais' 
$result=Invoke-WinSlimRegistryTransaction $same $reader $writer $journal $progress
Require ($result.verified -and $result.changed -eq 0 -and $result.unchanged -eq 5 -and $script:writes -eq 0) 'reaplicar nao escreve estados ja presentes'
Reset-State;$script:db[$targets[0].Name]=Copy-Data $targets[0].Desired
$result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $journal $progress
Require (-not $result.verified -and $script:writes -eq 0) 'drift antes de escrever bloqueia o lote'
Reset-State;$partial={param($t,$s) $script:db[$t.Name]=Copy-Data $s;if($t.TweakId -eq 'UI-008' -and $s.Exists){throw 'partial write'}}
$result=Invoke-WinSlimRegistryTransaction $targets $reader $partial $journal $progress
Require (-not $result.verified -and $result.recovered -and @($script:db.Values | Where-Object {$_.Exists}).Count -eq 0) 'falha parcial desfaz inclusive o ultimo destino'
Reset-State;$wrong={param($t,$s) $script:db[$t.Name]=Copy-Data $s;if($t.TweakId -eq 'UI-007' -and $s.Exists){$script:db[$t.Name].Value='7'}}
$result=Invoke-WinSlimRegistryTransaction $targets $reader $wrong $journal $progress
Require (-not $result.verified -and $result.recovered -and @($script:db.Values | Where-Object {$_.Exists}).Count -eq 0) 'falha de Verify recupera o estado anterior'
Reset-State;$unrecoverable={param($t,$s) if($t.TweakId -eq 'UI-007'){throw 'inaccessible'};$script:db[$t.Name]=Copy-Data $s}
$result=Invoke-WinSlimRegistryTransaction $targets $reader $unrecoverable $journal $progress
Require (-not $result.verified -and -not $result.recovered -and $result.errors.Count -gt 0) 'recuperacao incompleta nao vira sucesso'
Reset-State;$badJournal={param($s,$t) if($s -eq 'Writing'){throw 'journal unavailable'}}
$result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $badJournal $progress
Require (-not $result.verified -and $script:writes -eq 0) 'falha do journal impede primeira escrita'
Reset-State;$lateDrift={param($t,$s) $script:db[$t.Name]=Copy-Data $s;if($t.TweakId -eq 'UI-016' -and $s.Exists){$script:db[$targets[0].Name].Value='external'}}
$result=Invoke-WinSlimRegistryTransaction $targets $reader $lateDrift $journal $progress
Require (-not $result.verified -and $result.recovered) 'verificacao final detecta alteracao posterior a verificacao individual'

# Persisted end-to-end flow: real token checks, snapshots, hashes and journals;
# registry access and the administrator check are replaced only inside this test process.
$fixtureIdentity=[pscustomobject]@{ComputerName='Fixture';MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'}
function Get-WinSlimBackupIdentity {Copy-Data $fixtureIdentity}
function Test-WinSlimRestoreAdministrator {$true}
function Get-WinSlimHardwarePresetReport {param($Request) [pscustomobject]@{Plan=(Copy-Data $plan);PresetName='Fixture'}}
function Read-WinSlimPreviewRegistry {param($Operation) $v=$script:db[$Operation.Name];if($null -eq $v){throw 'fixture inaccessible'};[pscustomobject]@{Exists=$v.Exists;Kind=$v.Kind;Value=(ConvertFrom-WinSlimRestoreValue $v)}}
function Set-WinSlimRestoreRegistry {
 param($Target,$State)
 $all=@(Get-WinSlimBackupInventory (Join-Path $script:WinSlimBridgeRoot 'Backups/UI'))
 if($all[0].Items.Count -lt 1){throw 'MISSING BACKUP BEFORE WRITE'}
 $script:writes++;$script:db[$Target.Name]=Copy-Data $State
}
function Authorize {
 $script:RegistryPreviewSession=[pscustomobject]@{Token='fixture-preview';CreatedUtc=[DateTime]::UtcNow;Request=[pscustomobject]@{presetName='Fixture'};Fingerprint=$plan.Fingerprint}
 New-WinSlimRegistryApplyPreview ([pscustomobject]@{previewToken='fixture-preview'})
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimApplyFixture-'+[Guid]::NewGuid().ToString('N'));$script:WinSlimBridgeRoot=$temp
try{
 Reset-State
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token='missing'})} 'aplicar sem confirmacao rejeitado'
 $preview=Authorize
 Require ($preview.count -eq 5 -and $preview.changes -eq 5) 'previa informa contagem real'
 $script:RegistryApplyAuthorization.Expires=[DateTime]::UtcNow.AddSeconds(-1)
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'confirmacao expirada rejeitada'
 Require ($null -eq $script:RegistryApplyAuthorization) 'token consumido antes da tentativa'
 $preview=Authorize;$script:db[$targets[0].Name]=Copy-Data $targets[0].Desired
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'estado alterado entre revisao e aplicacao rejeitado'
 Require ($script:writes -eq 0) 'drift nao escreveu'
 Reset-State;$preview=Authorize;$plan.Fingerprint='changed'
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'plano alterado rejeitado'
 $plan.Fingerprint='fixture-plan';$preview=Authorize;$fixtureIdentity.UserSid='other'
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'identidade alterada rejeitada'
 $fixtureIdentity.UserSid='Fixture'
 $preview=Authorize;$result=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token;Path='HKLM:\Unauthorized';Value='ignored'})
 Require ($result.verified -and $result.changed -eq 5) 'fluxo completo aplica somente valores do catalogo'
 Require (Test-Path -LiteralPath $result.reportPath) 'relatorio final persistido'
 $saved=Read-WinSlimVerifiedBackup (Split-Path (Split-Path $result.reportPath))
 Require ($saved.Verified -and $saved.Snapshot.CapturedCount -eq 5 -and $saved.Snapshot.ExcludedCount -eq 0) 'backup completo e verificado precede as escritas'
 $back=@(Get-WinSlimRestoreTargets $saved.Snapshot $script:PresetRuntime.CatalogRuntime.ById $fixtureIdentity)
 Require ($back.Count -eq 5 -and @($back | Where-Object {$_.Desired.Exists}).Count -eq 0) 'snapshot guarda ausencia original para Undo'
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'token nao pode ser reutilizado'
 $preview=Authorize;$again=Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})
 Require ($again.verified -and $again.changed -eq 0 -and $again.unchanged -eq 5) 'fluxo completo idempotente'
 # Simulate abrupt termination by removing ONLY the outcome receipt in this temporary fixture.
 [IO.File]::WriteAllText($result.reportPath,'{broken')
 Reject {Authorize} 'aplicacao interrompida exige recuperacao antes de outro lote'
 foreach($t in $back){$script:db[$t.Name]=Copy-Data $t.Desired}
 $preview=Authorize
 Require ($preview.changes -eq 5) 'restauracao conferida desbloqueia tentativa futura'
 Require (Test-Path -LiteralPath (Join-Path (Split-Path $result.reportPath) 'recovered.json')) 'recuperacao apos interrupcao deixa recibo'
 # Failed or partial persistence must stop before the first system write.
 $originalSnapshot=(Get-Command New-WinSlimBackupSnapshot).ScriptBlock
 function New-WinSlimBackupSnapshot {
  param($Plan,$Profile)
  $v=& $originalSnapshot -Plan $Plan -Profile $Profile
  $v.ExcludedCount=1;$v.CapturedCount--
  return $v
 }
 $script:writes=0;$preview=Authorize
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'captura parcial bloqueia aplicacao'
 Require ($script:writes -eq 0) 'backup parcial nao autoriza escrita'
 Set-Item function:New-WinSlimBackupSnapshot $originalSnapshot
 $originalSave=(Get-Command Save-WinSlimBackupSnapshot).ScriptBlock
 function Save-WinSlimBackupSnapshot {param($Root,$Snapshot) throw 'fixture disk failure'}
 $preview=Authorize
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'falha de persistencia do backup bloqueia aplicacao'
 Require ($script:writes -eq 0) 'falha de disco nao autoriza escrita'
 Set-Item function:Save-WinSlimBackupSnapshot $originalSave
 # A partial capture must never authorize any write.
 $script:writes=0;$preview=Authorize;$script:db.Remove($targets[2].Name)
 Reject {Invoke-WinSlimRegistryApply ([pscustomobject]@{token=$preview.token})} 'leitura indisponivel bloqueia escrita'
 Require ($script:writes -eq 0) 'falha de leitura preserva sistema'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host ('RegistryApply: '+$script:checks+' verificacoes passaram. IO de sistema simulado; nenhum tweak real aplicado.')
