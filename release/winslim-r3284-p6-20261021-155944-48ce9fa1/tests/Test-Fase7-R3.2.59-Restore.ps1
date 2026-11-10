param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src/UI/Native/R3_2_59/WinSlimLivePreview.ps1')
. (Join-Path $Root 'src/UI/Native/R3_2_59/WinSlimBackup.ps1')
$script:checks=0
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:checks++;Write-Host ('[OK] Restore: '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action}catch{$rejected=$true};Require $rejected $Message}
function Copy-Data($x){ConvertTo-Json -InputObject $x -Depth 32 | ConvertFrom-Json}
$identity=[pscustomobject]@{MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'}
$typed=@(
 [pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null},
 [pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='-2147483648'},
 [pscustomobject]@{Exists=$true;Kind='QWord';Encoding='Int64Decimal';Value='9223372036854775807'},
 [pscustomobject]@{Exists=$true;Kind='Binary';Encoding='Base64';Value='AID/'},
 [pscustomobject]@{Exists=$true;Kind='MultiString';Encoding='StringArray';Value=@('one','two')},
 [pscustomobject]@{Exists=$true;Kind='MultiString';Encoding='StringArray';Value=@()},
 [pscustomobject]@{Exists=$true;Kind='ExpandString';Encoding='String';Value='%SystemRoot%\Fixture'},
 [pscustomobject]@{Exists=$true;Kind='String';Encoding='String';Value=''}
)
foreach($v in $typed){$raw=ConvertFrom-WinSlimRestoreValue $v;$state=[pscustomobject]@{Exists=$v.Exists;Kind=$v.Kind;Value=$raw};Require (Test-WinSlimRestoreEqual (ConvertTo-WinSlimBackupValue $state) $v) ('tipo preservado '+$v.Kind+' / '+$v.Encoding)}
Reject {ConvertFrom-WinSlimRestoreValue ([pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Base64';Value='0'})} 'encoding incorreto rejeitado'
Reject {ConvertFrom-WinSlimRestoreValue ([pscustomobject]@{Exists='true';Kind='DWord';Encoding='Int32Decimal';Value='0'})} 'booleano textual rejeitado'
Reject {ConvertFrom-WinSlimRestoreValue ([pscustomobject]@{Exists=$true;Kind='Binary';Encoding='Base64';Value='not-base64!'})} 'base64 invalido rejeitado'
$ops=@();$allowed=@()
for($i=0;$i -lt $typed.Count;$i++){$ops+=[pscustomobject]@{Hive='CurrentUser';SubPath='Fixture';Name=('V'+$i);Before=$typed[$i]};$allowed+=[pscustomobject]@{Path='HKCU:\Fixture';Name=('V'+$i)}}
$delay=$typed[0]
$service=[pscustomobject]@{Name='FixtureService';Exists=$true;StartMode='Auto';State='Running';DelayedAutoStart=$delay}
$snapshot=[pscustomobject]@{Identity=$identity;Items=@([pscustomobject]@{TweakId='R';Type='registry';Operations=$ops},[pscustomobject]@{TweakId='S';Type='service';Operations=@($service)})}
$catalog=@{R=[pscustomobject]@{type='registry';registry=$allowed};S=[pscustomobject]@{type='service';service=@([pscustomobject]@{Name='FixtureService'})}}
$targets=@(Get-WinSlimRestoreTargets $snapshot $catalog $identity)
Require ($targets.Count -eq 9) 'todos os destinos do backup autorizados'
# Regression: PS5.1 loses Count on a scalar PSCustomObject emitted by an if expression.
$single=Copy-Data $snapshot;$single.Items[0].Operations=@($single.Items[0].Operations[0])
$singleCatalog=@{R=[pscustomobject]@{type='registry';registry=@($allowed[0])};S=$catalog.S}
Require (@(Get-WinSlimRestoreTargets $single $singleCatalog $identity).Count -eq 2) 'registro e servico com uma operacao cada mantem cobertura'
Require (@(Get-WinSlimRestoreTargets $single $singleCatalog $identity 'R').Count -eq 1) 'registro de uma operacao aceita escopo individual'
$singleCatalog.R.registry=$allowed[0]
Require (@(Get-WinSlimRestoreTargets $single $singleCatalog $identity 'R').Count -eq 1) 'operacao escalar do catalogo normalizada sem perder autorizacao'
$empty=Copy-Data $single;$empty.Items[0].Operations=@()
Reject {Get-WinSlimRestoreTargets $empty $singleCatalog $identity} 'backup sem operacoes continua rejeitado'
$empty=Copy-Data $single;$empty.Items[0].Operations+=$empty.Items[0].Operations[0]
Reject {Get-WinSlimRestoreTargets $empty $singleCatalog $identity} 'operacao extra continua rejeitada'
$emptyCatalog=@{R=[pscustomobject]@{type='registry';registry=@()};S=$catalog.S}
Reject {Get-WinSlimRestoreTargets $single $emptyCatalog $identity} 'catalogo sem contrato continua rejeitado'

Require (@(Get-WinSlimRestoreTargets $snapshot $catalog $identity 'S').Count -eq 1) 'escopo de um unico tweak'
$bad=Copy-Data $snapshot;$bad.Identity.MachineGuid='Other';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'outro computador rejeitado'
$bad=Copy-Data $snapshot;$bad.Identity.UserSid='Other';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'outro usuario rejeitado'
$bad=Copy-Data $snapshot;$bad.Identity.RegistryView='Registry32';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'outra arquitetura rejeitada'
$bad=Copy-Data $snapshot;$bad.Items[0].Operations[0].SubPath='Unauthorized';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'destino adulterado rejeitado'
$bad=Copy-Data $snapshot;$bad.Items[0].TweakId='Unknown';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'ID desconhecido rejeitado'
$bad=Copy-Data $snapshot;$bad.Items[1].Operations[0].State='Start Pending';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'servico em transicao rejeitado'
$bad=Copy-Data $snapshot;$bad.Items[1].Type='script';Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'scripts nunca executados pelo restore'
Reject {Get-WinSlimRestoreTargets $snapshot $catalog $identity 'Absent'} 'escopo ausente rejeitado'
$bad=Copy-Data $snapshot;$bad.Items+= $bad.Items[0];Reject {Get-WinSlimRestoreTargets $bad $catalog $identity} 'ID duplicado rejeitado'
# Deterministic fake state isolates failure recovery from real registry/services.
function New-FixtureTargets {
 $result=@()
 for($i=0;$i -lt 3;$i++){$result+=[pscustomobject]@{Name=('T'+$i);TweakId=('T'+$i);Current=[pscustomobject]@{Value='before'};Desired=[pscustomobject]@{Value='after'}}}
 return $result
}
function Reset-Fixture {$script:db=@{T0=[pscustomobject]@{Value='before'};T1=[pscustomobject]@{Value='before'};T2=[pscustomobject]@{Value='before'}};$script:writes=0;$script:statuses=@()}
$reader={param($t) $script:db[$t.Name]}
$writer={param($t,$s) $script:writes++;$script:db[$t.Name]=Copy-Data $s}
$journal={param($s,$c) $script:statuses+= $s}
Reset-Fixture;$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $writer $journal
Require ($result.verified -and $result.changed -eq 3 -and $script:writes -eq 3 -and $script:statuses[-1] -eq 'Completed') 'restauracao em lote verifica todos os destinos'
Reset-Fixture;$t=New-FixtureTargets;foreach($x in $t){$x.Desired=$x.Current};$result=Invoke-WinSlimRestoreTransaction $t $reader $writer $journal
Require ($result.verified -and $script:writes -eq 0) 'estado ja presente nao escreve'
Reset-Fixture;$script:db.T0=[pscustomobject]@{Value='external'};$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $writer $journal
Require (-not $result.verified -and $script:writes -eq 0 -and $script:db.T0.Value -eq 'external') 'mudanca externa antes da escrita bloqueia o lote'
Reset-Fixture;$failing={param($t,$s) $script:writes++;$script:db[$t.Name]=Copy-Data $s;if($t.Name -eq 'T1' -and $s.Value -eq 'after'){throw 'fixture write failure'}}
$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $failing $journal
Require (-not $result.verified -and $result.recovered -and $script:db.T0.Value -eq 'before' -and $script:db.T1.Value -eq 'before' -and $script:db.T2.Value -eq 'before') 'falha apos escrita recupera inclusive a operacao parcial'
Reset-Fixture;$wrong={param($t,$s) $script:db[$t.Name]=Copy-Data $s;if($t.Name -eq 'T1' -and $s.Value -eq 'after'){$script:db[$t.Name]=[pscustomobject]@{Value='wrong'}}}
$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $wrong $journal
Require (-not $result.verified -and $result.recovered -and $script:db.T0.Value -eq 'before') 'falha de Verify recupera o lote'
Reset-Fixture;$unrecoverable={param($t,$s) if($t.Name -eq 'T1'){throw 'fixture inaccessible'};$script:db[$t.Name]=Copy-Data $s}
$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $unrecoverable $journal
Require (-not $result.verified -and -not $result.recovered -and $result.message -match 'incompleta') 'recuperacao incompleta explicitamente reportada'
Reset-Fixture;$badJournal={param($s,$c) if($s -eq 'Writing'){throw 'journal failure'}}
$result=Invoke-WinSlimRestoreTransaction (New-FixtureTargets) $reader $writer $badJournal
Require (-not $result.verified -and $result.recovered -and $script:writes -eq 0 -and $script:db.T0.Value -eq 'before') 'journal indisponivel impede alteracao sem recuperacao'
$script:RestoreAuthorization=$null;Reject {Invoke-WinSlimBackupRestore ([pscustomobject]@{token='missing'})} 'restauracao exige confirmacao valida'
$script:RestoreAuthorization=[pscustomobject]@{Token='fixture';Expires=[DateTime]::UtcNow.AddMinutes(-1);BackupId='id';TweakId=''}
Reject {Invoke-WinSlimBackupRestore ([pscustomobject]@{token='fixture';backupId='id';tweakId=''})} 'token expirado rejeitado'
Require ($null -eq $script:RestoreAuthorization) 'token consumido antes de qualquer tentativa'
# Persisted integration: backend auth/token/hash/recovery/journal with memory-only system IO.
function Test-WinSlimRestoreAdministrator {$true}
function Get-WinSlimBackupIdentity {$identity}
function Read-WinSlimRestoreTarget {param($Target) Copy-Data $script:state[$Target.Name]}
function Set-WinSlimRestoreTarget {param($Target,$State) $script:restoreWrites++;$script:state[$Target.Name]=Copy-Data $State}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimRestoreFixture-'+[Guid]::NewGuid().ToString('N'))
$script:WinSlimBridgeRoot=$temp
$script:PresetRuntime=[pscustomobject]@{CatalogRuntime=[pscustomobject]@{ById=$catalog}}
try{
 $source=Copy-Data $snapshot
 foreach($pair in @(@('SchemaVersion',1),@('Kind','WinSlimRegistryServiceBackup'),@('AppVersion','R3.2.56'),@('Id',[Guid]::NewGuid().ToString('N')),@('Profile','Fixture'),@('CreatedAtUtc',[DateTime]::UtcNow.ToString('o')),@('CaptureStartedUtc',[DateTime]::UtcNow.ToString('o')),@('PlanFingerprint','fixture'),@('Applied',$false),@('CanApply',$false),@('CanRestore',$false),@('RestorePointCreated',$false),@('Coverage','Partial'),@('CapturedCount',2),@('ExcludedCount',1),@('Excluded',@([pscustomobject]@{TweakId='X';Type='script';Reason='Excluded'})))){$source | Add-Member NoteProperty $pair[0] $pair[1]}
 $saved=Save-WinSlimBackupSnapshot (Join-Path $temp 'Backups/UI') $source
 $script:state=@{};$script:restoreWrites=0
 foreach($t in $targets){$script:state[$t.Name]=Copy-Data $t.Desired}
 # Modify one registry value in memory so restore must actually write.
 $changed=[pscustomobject]@{Exists=$true;Kind='String';Encoding='String';Value='current'}
 $script:state.V0=$changed
 $request=[pscustomobject]@{backupId=$source.Id;tweakId='';token=''}
 $preview=New-WinSlimRestorePreview $request
 Require ($preview.count -eq 2 -and $preview.changes -eq 1 -and $preview.excluded -eq 1) 'previa informa cobertura parcial e alteracoes'
 $request.token=$preview.token
 $result=Invoke-WinSlimBackupRestore $request
 Require ($result.verified -and $script:restoreWrites -eq 1 -and -not $script:state.V0.Exists) 'fluxo completo restaura ausencia sem escrever em registro real'
 $recovery=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $result.recoveryBackupId)
 Require ($recovery.Verified -and $recovery.Snapshot.Items[0].Operations[0].Before.Value -ceq 'current') 'copia anterior a restauracao persistida e verificada'
 Require ((Read-WinSlimVerifiedBackup $saved.Path).Sha256 -ceq $saved.Sha256) 'backup original preservado apos restauracao'
 $journals=@(Get-ChildItem (Join-Path $recovery.Path 'restore-journal') -Filter '*.json' | ForEach-Object {Get-Content $_.FullName -Raw | ConvertFrom-Json})
 Require (@($journals | Where-Object {$_.Status -eq 'Completed'}).Count -eq 1) 'journal persistente confirma conclusao'
 Reject {Invoke-WinSlimBackupRestore $request} 'token usado nao permite repetir a restauracao'
 $preview=New-WinSlimRestorePreview $request;$request.token=$preview.token;$script:state.V0=$changed;$writes=$script:restoreWrites
 Reject {Invoke-WinSlimBackupRestore $request} 'mudanca apos previa exige nova confirmacao'
 Require ($script:restoreWrites -eq $writes) 'drift apos previa nao escreve'
 # Single-tweak path restores only its selected destinations.
 $script:state.V0=$changed;$request.tweakId='S';$preview=New-WinSlimRestorePreview $request;$request.token=$preview.token
 $result=Invoke-WinSlimBackupRestore $request
 Require ($result.verified -and $script:state.V0.Value -ceq 'current') 'restauracao individual preserva tweaks nao selecionados'
 $recovery=Read-WinSlimVerifiedBackup (Join-Path (Join-Path $temp 'Backups/UI') $result.recoveryBackupId)
 Require ($recovery.Snapshot.CapturedCount -eq 1 -and $recovery.Snapshot.Items[0].TweakId -ceq 'S') 'copia de recuperacao respeita escopo individual'
 $request.tweakId='';$preview=New-WinSlimRestorePreview $request;$request.token=$preview.token
 function Test-WinSlimRestoreAdministrator {$false}
 Reject {Invoke-WinSlimBackupRestore $request} 'aplicacao exige administrador'
 function Test-WinSlimRestoreAdministrator {$true}
 $preview=New-WinSlimRestorePreview $request;$request.token=$preview.token
 [IO.File]::AppendAllText((Join-Path $saved.Path 'snapshot.json'),' ')
 Reject {Invoke-WinSlimBackupRestore $request} 'arquivo alterado depois da previa impede restauracao'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
Write-Host ("Restore fixtures: $script:checks verificacoes aprovadas; nenhum registro/servico real alterado.")
