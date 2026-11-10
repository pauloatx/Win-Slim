param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src\UI\Native\R3_2_61\WinSlimLivePreview.ps1')
. (Join-Path $Root 'src\UI\Native\R3_2_61\WinSlimBackup.ps1')
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$identity={ [pscustomobject]@{ComputerName='Fixture';MachineGuid='Fixture';UserSid='Fixture';RegistryView='Registry64'} }
$registry=[pscustomobject]@{type='registry';name='Fixture registro';registry=@(
 [pscustomobject]@{Path='HKCU:\Fixture';Name='Missing'},
 [pscustomobject]@{Path='HKU\.DEFAULT\Fixture';Name='Binary'},
 [pscustomobject]@{Path='HKCU:\Fixture';Name='Multi'},
 [pscustomobject]@{Path='HKCU:\Fixture';Name='EmptyMulti'},
 [pscustomobject]@{Path='HKCU:\Fixture';Name='QWord'},
 [pscustomobject]@{Path='HKCU:\Fixture';Name='EmptyString'}
)}
$service=[pscustomobject]@{type='service';name='Fixture servico';service=@([pscustomobject]@{Name='FixtureService';StartupType='Manual'})}
$unsupported=[pscustomobject]@{type='script';script='throw "must never execute"'}
$plan=[pscustomobject]@{CanExecute=$true;Fingerprint='fixture-plan';ExecutionOrder=@([pscustomobject]@{TweakId='R';Tweak=$registry},[pscustomobject]@{TweakId='S';Tweak=$service},[pscustomobject]@{TweakId='X';Tweak=$unsupported})}
$before=ConvertTo-Json -InputObject $plan -Depth 20 -Compress
$reader={param($op)
 switch($op.Name){
  'Missing'{return [pscustomobject]@{Exists=$false;Kind=$null;Value=$null}}
  'Binary'{return [pscustomobject]@{Exists=$true;Kind='Binary';Value=[byte[]]@(0,128,255)}}
  'Multi'{return [pscustomobject]@{Exists=$true;Kind='MultiString';Value=[string[]]@('one','two')}}
  'EmptyMulti'{return [pscustomobject]@{Exists=$true;Kind='MultiString';Value=[string[]]@()}}
  'QWord'{return [pscustomobject]@{Exists=$true;Kind='QWord';Value=[long]::MaxValue}}
  'EmptyString'{return [pscustomobject]@{Exists=$true;Kind='String';Value=''}}
  'DelayedAutoStart'{return [pscustomobject]@{Exists=$true;Kind='DWord';Value=1}}
  default {throw 'unexpected registry read'}
 }
}
$serviceReader={ [pscustomobject]@{Name='FixtureService';StartMode='Auto';State='Running'} }
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinSlimBackupTest-'+[Guid]::NewGuid().ToString('N'))
try{
 $snapshot=New-WinSlimBackupSnapshot -Plan $plan -Profile 'Fixture' -RegistryReader $reader -ServiceReader $serviceReader -IdentityReader $identity
 Require ($snapshot.CapturedCount -eq 2 -and $snapshot.ExcludedCount -eq 1 -and $snapshot.Coverage -eq 'Partial') 'Cobertura parcial deve ser explicita'
 $singleRegistry=[pscustomobject]@{type='registry';name='Single';registry=@([pscustomobject]@{Path='HKCU:\Fixture';Name='Missing'})}
 $singlePlan=[pscustomobject]@{CanExecute=$true;Fingerprint='single';ExecutionOrder=@([pscustomobject]@{TweakId='One';Tweak=$singleRegistry},[pscustomobject]@{TweakId='S';Tweak=$service})}
 $singleSnapshot=New-WinSlimBackupSnapshot -Plan $singlePlan -Profile 'Single' -RegistryReader $reader -ServiceReader $serviceReader -IdentityReader $identity
 Require ($singleSnapshot.CapturedCount -eq 2 -and $singleSnapshot.ExcludedCount -eq 0 -and @($singleSnapshot.Items[0].Operations).Count -eq 1 -and @($singleSnapshot.Items[1].Operations).Count -eq 1) 'Captura de operacoes unicas preserva registro e servico no PowerShell 5.1'

 Require (-not $snapshot.Applied -and -not $snapshot.CanApply -and -not $snapshot.CanRestore -and -not $snapshot.RestorePointCreated) 'Backup nao pode afirmar execucao ou restauracao'
 Require ((ConvertTo-Json -InputObject $plan -Depth 20 -Compress) -ceq $before) 'Backup nao pode modificar plano'
 $saved=Save-WinSlimBackupSnapshot -Root $temp -Snapshot $snapshot
 Require $saved.Verified 'Gravacao precisa verificar integridade'
 $loaded=Read-WinSlimVerifiedBackup $saved.Path
 $ops=@($loaded.Snapshot.Items[0].Operations)
 Require (-not $ops[0].Before.Exists -and $null -eq $ops[0].Before.Value) 'Ausencia deve sobreviver ao JSON'
 Require ($ops[1].Hive -eq 'Users' -and $ops[1].Before.Value -ceq 'AID/') 'Hive HKU e bytes devem ser preservados'
 Require ($ops[2].Before.Value.Count -eq 2 -and $ops[3].Before.Value.Count -eq 0) 'Arrays vazios e multiplos devem sobreviver'
 Require ($ops[4].Before.Value -ceq '9223372036854775807' -and $ops[4].Before.Encoding -eq 'Int64Decimal') 'QWord nao pode perder precisao'
 Require ($ops[5].Before.Exists -and $ops[5].Before.Value -ceq '') 'String vazia nao pode virar ausencia'
 Require ($loaded.Snapshot.Items[1].Operations[0].DelayedAutoStart.Value -eq '1') 'Capturar atraso mesmo se destino for Manual'
 $inventory=Get-WinSlimBackupInventory $temp
 Require ($inventory.Items.Count -eq 1 -and $inventory.InvalidCount -eq 0) 'Backup publicado deve aparecer na consulta'
 $duplicateFailed=$false
 try{Save-WinSlimBackupSnapshot -Root $temp -Snapshot $snapshot | Out-Null}catch{$duplicateFailed=$true}
 Require ($duplicateFailed -and (Read-WinSlimVerifiedBackup $saved.Path).Sha256 -ceq $saved.Sha256) 'Backup existente nunca pode ser sobrescrito'
 # Separate process proves persistence is independent of live PowerShell objects.
 $child=Join-Path $temp 'verify.ps1'
 $childText='param($Helper,$Folder); $ErrorActionPreference="Stop"; . $Helper; $v=Read-WinSlimVerifiedBackup $Folder; if(-not $v.Verified -or $v.Snapshot.CapturedCount -ne 2){exit 1}; exit 0'
 [IO.File]::WriteAllText($child,$childText)
 & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child (Join-Path $Root 'src\UI\Native\R3_2_61\WinSlimBackup.ps1') $saved.Path
 Require ($LASTEXITCODE -eq 0) 'Backup deve ser verificavel em outro processo'
 [IO.File]::AppendAllText((Join-Path $saved.Path 'snapshot.json'),' ')
 $tampered=Get-WinSlimBackupInventory $temp
 Require ($tampered.Items.Count -eq 0 -and $tampered.InvalidCount -eq 1) 'Arquivo alterado nao pode ser exibido como verificado'
 $noneFailed=$false
 try{New-WinSlimBackupSnapshot -Plan $plan -RegistryReader {throw 'Access denied'} -ServiceReader {@()} -IdentityReader $identity | Out-Null}catch{$noneFailed=$true}
 Require $noneFailed 'Zero capturas nao pode gerar sucesso'
 $deniedFile=Join-Path $temp 'file-not-directory';[IO.File]::WriteAllText($deniedFile,'fixture')
 $writeFailed=$false
 try{Save-WinSlimBackupSnapshot -Root $deniedFile -Snapshot $snapshot | Out-Null}catch{$writeFailed=$true}
 Require $writeFailed 'Destino indisponivel deve falhar explicitamente'
 Require (@(Get-ChildItem -LiteralPath $temp -Directory | Where-Object {$_.Name -like '.pending-*'}).Count -eq 0) 'Gravacao interrompida nao pode publicar pasta incompleta'
 $plan.CanExecute=$false;$blocked=$false
 try{New-WinSlimBackupSnapshot -Plan $plan -RegistryReader $reader -ServiceReader $serviceReader -IdentityReader $identity | Out-Null}catch{$blocked=$true}
 Require $blocked 'Plano bloqueado nao pode criar backup'
 Write-Host 'Backup R3.2.61: captura tipada, cobertura, persistencia, integridade e falhas OK'
}finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
