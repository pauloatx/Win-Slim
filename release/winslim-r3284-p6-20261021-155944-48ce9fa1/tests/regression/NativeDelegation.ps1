function Get-WinSlimNativeDelegation {
 @(
  @{Id='REG-PERF-001';Script='tests/Test-Fase7-R3.2.84-Performance.ps1'},
  @{Id='REG-EDGE-001';Script='tests/Test-Fase7-R3.2.84-Edge.ps1'},
  @{Id='REG-ENDTASK-001';Script='tests/Test-Fase7-R3.2.84-EndTask.ps1'},
  @{Id='REG-SEARCH-001';Script='tests/Test-Fase7-R3.2.84-SearchIcon.ps1'},
  @{Id='REG-UIBATCH-001';Script='tests/Test-Fase7-R3.2.84-UiBatch.ps1'},
  @{Id='REG-REPORT-001';Script='tests/Test-Fase7-R3.2.84-Report.ps1'},
  @{Id='REG-QOLBATCH-001';Script='tests/Test-Fase7-R3.2.84-QolBatch.ps1'},
  @{Id='REG-EDGEBATCH-001';Script='tests/Test-Fase7-R3.2.84-EdgeBatch.ps1'},
  @{Id='REG-EDGENEXT-001';Script='tests/Test-Fase7-R3.2.84-EdgeNext.ps1'},
  @{Id='REG-EDGEPRIV-001';Script='tests/Test-Fase7-R3.2.84-EdgePrivacy.ps1'}
 )
}
function Assert-WinSlimNativeDelegation {
 param([object[]]$Cases,$NativeCase)
 if($NativeCase.id -cne 'REG-UI-001' -or $NativeCase.script.Replace('\','/') -cne 'tests/Test-Fase7-R3.2.84-NativeUI.ps1'){throw 'Delegacao nativa invalida.'}
 foreach($entry in (Get-WinSlimNativeDelegation)){
  $found=@($Cases | Where-Object {$_.id -ceq $entry.Id})
  if($found.Count -ne 1 -or $found[0].script.Replace('\','/') -cne $entry.Script -or $found[0].integratedNative -eq $true){throw ('Suite delegada ausente ou invalida: '+$entry.Id)}
 }
}
function Invoke-WinSlimNativePrerequisite {
 param([string]$Root,[string]$Script,[switch]$IntegratedMode,[scriptblock]$AssertResult,[string]$Message)
 $entry=@(Get-WinSlimNativeDelegation | Where-Object {$_.Script -ceq $Script.Replace('\','/')})
 if($entry.Count -ne 1){throw ('Pre-requisito nao cadastrado: '+$Script)}
 if($IntegratedMode){Write-Host ('  [SUITE EXTERNA] '+$entry[0].Id+' agendada no gate completo.');return}
 & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $Root $Script) -Root $Root
 & $AssertResult ($LASTEXITCODE -eq 0) $Message
}
