# Controlled native IO test: only a unique disposable HKCU key, never catalog tweaks.
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'Este teste precisa do Windows.'}
. (Join-Path $Root 'src/UI/Native/R3_2_75/WinSlimLivePreview.ps1')
. (Join-Path $Root 'src/UI/Native/R3_2_75/WinSlimBackup.ps1')
. (Join-Path $Root 'src/UI/Native/R3_2_75/WinSlimRegistryApply.ps1')
$sub='Software\WinSlimApplyValidation-'+[Guid]::NewGuid().ToString('N')
$view=if([Environment]::Is64BitOperatingSystem){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
$key=$base.OpenSubKey($sub,$false)
if($null -ne $key){$key.Dispose();$base.Dispose();throw 'Chave exclusiva ja existe.'}
$count=0
function Check([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};$script:count++;Write-Host ('[OK] RegistryApply Windows: '+$Message)}
try{
 $absent=[pscustomobject]@{Exists=$false;Kind=$null;Encoding='None';Value=$null}
 $targets=@(
  [pscustomobject]@{Type='registry';TweakId='Fixture-String';DisplayName='Fixture';Path=('HKCU:\'+$sub);Hive='CurrentUser';SubPath=$sub;Name='String';Current=$absent;Desired=[pscustomobject]@{Exists=$true;Kind='String';Encoding='String';Value='100'}},
  [pscustomobject]@{Type='registry';TweakId='Fixture-DWord';DisplayName='Fixture';Path=('HKCU:\'+$sub);Hive='CurrentUser';SubPath=$sub;Name='DWord';Current=$absent;Desired=[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='1'}}
 )
 $reader={param($t) Read-WinSlimRestoreTarget $t}
 $writer={param($t,$s) Set-WinSlimRestoreRegistry $t $s}
 $journal={param($s,$t)}
 $result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $journal
 Check ($result.verified -and $result.changed -eq 2) 'aplicacao real String e DWord na chave descartavel'
 foreach($t in $targets){Check (Test-WinSlimRestoreEqual (Read-WinSlimRestoreTarget $t) $t.Desired) ('Verify '+$t.Name)}
 foreach($t in $targets){$t.Current=$t.Desired}
 $result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $journal
 Check ($result.verified -and $result.changed -eq 0 -and $result.unchanged -eq 2) 'segunda aplicacao nao altera valores'
 foreach($t in $targets){Set-WinSlimRestoreRegistry $t $absent;$t.Current=$absent}
 $partial={param($t,$s) Set-WinSlimRestoreRegistry $t $s;if($t.Name -eq 'DWord' -and $s.Exists){throw 'Falha controlada depois da escrita'}}
 $result=Invoke-WinSlimRegistryTransaction $targets $reader $partial $journal
 Check (-not $result.verified -and $result.recovered) 'falha real parcial recuperada'
 foreach($t in $targets){Check (-not (Read-WinSlimRestoreTarget $t).Exists) ('ausencia original recuperada: '+$t.Name)}
 $wrong={param($t,$s) if($t.Name -eq 'DWord' -and $s.Exists){$s=[pscustomobject]@{Exists=$true;Kind='DWord';Encoding='Int32Decimal';Value='9'}};Set-WinSlimRestoreRegistry $t $s}
 $result=Invoke-WinSlimRegistryTransaction $targets $reader $wrong $journal
 Check (-not $result.verified -and $result.recovered) 'verificacao divergente provoca recuperacao'
 foreach($t in $targets){Check (-not (Read-WinSlimRestoreTarget $t).Exists) ('Undo apos Verify divergente: '+$t.Name)}
 Set-WinSlimRestoreRegistry $targets[0] $targets[0].Desired
 $result=Invoke-WinSlimRegistryTransaction $targets $reader $writer $journal
 Check (-not $result.verified -and -not (Read-WinSlimRestoreTarget $targets[1]).Exists) 'mudanca externa impede novas escritas'
 Check (Test-WinSlimRestoreEqual (Read-WinSlimRestoreTarget $targets[0]) $targets[0].Desired) 'estado externo preservado'
 Write-Host ('RegistryApply Windows: '+$count+' verificacoes passaram; nenhum ajuste do catalogo aplicado.')
}finally{$base.DeleteSubKeyTree($sub,$false);$base.Dispose()}
