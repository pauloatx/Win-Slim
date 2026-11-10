# Controlled writer test. Creates only a unique HKCU test key and removes it afterwards.
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Este teste precisa do Windows.'}
. (Join-Path $Root 'src/UI/Native/R3_2_65/WinSlimLivePreview.ps1')
. (Join-Path $Root 'src/UI/Native/R3_2_65/WinSlimBackup.ps1')
$sub='Software\WinSlimRestoreValidation-'+[Guid]::NewGuid().ToString('N')
$view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
$key=$base.OpenSubKey($sub,$false)
if($null -ne $key){$key.Dispose();$base.Dispose();throw 'A chave exclusiva de teste ja existe.'}
$script:count=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:count++;Write-Host ('[OK] '+$Message)}
try{
 $typed=@(
  [pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='-2147483648'},
  [pscustomobject]@{Exists=$true;Kind='QWord';Encoding='Int64Decimal';Value='9223372036854775807'},
  [pscustomobject]@{Exists=$true;Kind='Binary';Encoding='Base64';Value='AID/'},
  [pscustomobject]@{Exists=$true;Kind='Binary';Encoding='Base64';Value=''},
  [pscustomobject]@{Exists=$true;Kind='MultiString';Encoding='StringArray';Value=@('one','two')},
  [pscustomobject]@{Exists=$true;Kind='MultiString';Encoding='StringArray';Value=@()},
  [pscustomobject]@{Exists=$true;Kind='ExpandString';Encoding='String';Value='%SystemRoot%\Fixture'},
  [pscustomobject]@{Exists=$true;Kind='String';Encoding='String';Value=''}
 )
 $absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
 for($i=0;$i -lt $typed.Count;$i++){
  $t=[pscustomobject]@{Type='registry';TweakId=('Fixture-'+$i);Path=('HKCU:\'+$sub);Hive='CurrentUser';SubPath=$sub;Name=('V'+$i);Current=$absent;Desired=$typed[$i]}
  Set-WinSlimRestoreRegistry $t $t.Desired
  $seen=Read-WinSlimRestoreTarget $t
  Check (Test-WinSlimRestoreEqual $seen $t.Desired) ('Gravacao e leitura tipada: '+$i+' / '+$t.Desired.Kind)
  Set-WinSlimRestoreRegistry $t $absent
  Check (-not (Read-WinSlimRestoreTarget $t).Exists) ('Ausencia original restaurada: '+$i)
 }
 $targets=@()
 for($i=0;$i -lt 2;$i++){$targets+=[pscustomobject]@{Type='registry';TweakId=('Fixture-'+$i);Path=('HKCU:\'+$sub);Hive='CurrentUser';SubPath=$sub;Name=('V'+$i);Current=$absent;Desired=$typed[$i]}}
 $result=Invoke-WinSlimRestoreTransaction $targets {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreTarget $t $s;if($t.Name -eq 'V1' -and $s.Exists){throw 'Falha de teste apos escrever'}} {param($s,$c)}
 Check (-not $result.verified -and $result.recovered) 'Falha controlada recuperada e verificada pelo writer real'
 foreach($t in $targets){Check (-not (Read-WinSlimRestoreTarget $t).Exists) ('Valor de teste removido na recuperacao: '+$t.Name)}
 # Use authorized single-operation tweaks against the same disposable HKCU key.
 # This reproduces the PS5.1 catalog shape without touching actual catalog targets.
 $identity=[pscustomobject]@{MachineGuid='IsolatedFixture';UserSid='IsolatedFixture';RegistryView=$view.ToString()}
 $catalog=@{};$items=@()
 for($i=0;$i -lt 2;$i++){
  $id='Fixture-'+$i;$name='V'+$i
  $catalog[$id]=[pscustomobject]@{type='registry';registry=@([pscustomobject]@{Path=('HKCU:\'+$sub);Name=$name})}
  $items+=[pscustomobject]@{TweakId=$id;Type='registry';Operations=@([pscustomobject]@{Hive='CurrentUser';SubPath=$sub;Name=$name;Before=$typed[$i]})}
 }
 $snapshot=[pscustomobject]@{Identity=$identity;Items=$items}
 $targets=@(Get-WinSlimRestoreTargets $snapshot $catalog $identity)
 Check ($targets.Count -eq 2) 'Catalogo autoriza dois tweaks de operacao unica no PowerShell do Windows'
 foreach($t in $targets){$t | Add-Member NoteProperty Current (Read-WinSlimRestoreTarget $t)}
 $result=Invoke-WinSlimRestoreTransaction $targets {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreTarget $t $s} {param($s,$c)}
 Check ($result.verified -and $result.changed -eq 2) 'Restauracao completa dos dois tweaks temporarios verificada'
 foreach($item in $snapshot.Items){$item.Operations[0].Before=$absent}
 $selected=@(Get-WinSlimRestoreTargets $snapshot $catalog $identity 'Fixture-0')
 Check ($selected.Count -eq 1) 'Restaurar selecionado autoriza somente o tweak escolhido'
 foreach($t in $selected){$t | Add-Member NoteProperty Current (Read-WinSlimRestoreTarget $t)}
 $result=Invoke-WinSlimRestoreTransaction $selected {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreTarget $t $s} {param($s,$c)}
 Check ($result.verified -and $result.changed -eq 1 -and -not (Read-WinSlimRestoreTarget $targets[0]).Exists) 'Restauracao individual remove somente V0'
 Check (Test-WinSlimRestoreEqual (Read-WinSlimRestoreTarget $targets[1]) $typed[1]) 'Restauracao individual preserva V1 nao selecionado'
 $all=@(Get-WinSlimRestoreTargets $snapshot $catalog $identity)
 foreach($t in $all){$t | Add-Member NoteProperty Current (Read-WinSlimRestoreTarget $t)}
 $result=Invoke-WinSlimRestoreTransaction $all {param($t) Read-WinSlimRestoreTarget $t} {param($t,$s) Set-WinSlimRestoreTarget $t $s} {param($s,$c)}
 Check ($result.verified -and $result.changed -eq 1) 'Restaurar tudo recupera o valor restante e evita reescrever V0'
 foreach($t in $all){Check (-not (Read-WinSlimRestoreTarget $t).Exists) ('Escopo completo restaurou ausencia: '+$t.Name)}
 Write-Host ("Registro Windows: $script:count verificacoes aprovadas. Somente a chave temporaria do teste foi usada.")
}finally{$base.DeleteSubKeyTree($sub,$false);$base.Dispose()}
