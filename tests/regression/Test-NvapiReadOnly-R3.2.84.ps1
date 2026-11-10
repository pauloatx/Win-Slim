#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
trap {Write-Host ('[FAIL] NvapiReadOnly: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;exit 1}
. (Join-Path $Root 'tools/prototypes/NvapiReadOnly.ps1')
$build=Join-Path $Root ('logs\nvapi-readonly-test-'+[Guid]::NewGuid().ToString('N'))
$null=Import-WinSlimNvApiReadOnlyPrototype -Root $Root -BuildDirectory $build -WithFixture
$script:checks=0
function Check([bool]$Ok,[string]$Text){if(-not $Ok){throw $Text};$script:checks++;Write-Host ('[OK] '+$Text)}
function Reject([scriptblock]$Action,[string]$Text){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Text}
$oraclePath=Join-Path $build 'abi-oracle.json'
$python=Join-Path $Root 'logs/dev-python313/python.exe'
if(-not (Test-Path -LiteralPath $python)){$python='python.exe'}
& $python (Join-Path $Root 'tools/prototypes/nvapi_abi_oracle.py') | Set-Content -LiteralPath $oraclePath -Encoding UTF8
if($LASTEXITCODE -ne 0){throw 'Pinned SDK ABI oracle failed.'}
$oracle=Get-Content -LiteralPath $oraclePath -Raw -Encoding UTF8 | ConvertFrom-Json
Check ($oracle.platform -ceq 'win32' -and $oracle.pointerBytes -eq 8 -and $oracle.unicodeCodeUnitBytes -eq 2) 'Windows x64 ctypes oracle with explicit 16-bit NVAPI strings'
[WinSlim.Development.NvapiReadOnly.Abi]::Validate()
$sizeMethod=[Runtime.InteropServices.Marshal].GetMethod('SizeOf',[type[]]@([type]))
foreach($entry in $oracle.layouts.PSObject.Properties){
 $type=('WinSlim.Development.NvapiReadOnly.'+$entry.Name) -as [type]
 Check ($sizeMethod.Invoke($null,[object[]]@($type)) -eq $entry.Value.size) ('independent native ctypes/.NET size '+$entry.Name)
 $revision=if($entry.Name -ceq 'Application'){4}else{1}
 Check ([WinSlim.Development.NvapiReadOnly.Abi]::Version($type,$revision) -eq $entry.Value.version) ('SDK size OR revision macro '+$entry.Name)
 foreach($offset in $entry.Value.offsets.PSObject.Properties){
  # SettingValues uses one contiguous marshalled payload for the default + 100 native unions.
  if($entry.Name -ceq 'SettingValues' -and $offset.Name -in @('Default','Values')){continue}
  Check ([Runtime.InteropServices.Marshal]::OffsetOf($type,$offset.Name).ToInt32() -eq $offset.Value) ('native field offset '+$entry.Name+'.'+$offset.Name)
 }
}
Check ($oracle.unionStride -eq 4100 -and $oracle.settingId -eq 0x10835002 -and $oracle.headerRangeMax -eq 1023) 'pinned SDK ID and pack-4 union stride; range is not runtime proof'
$ids=[WinSlim.Development.NvapiReadOnly.InstalledReader]::InterfaceIds()
$names=@('NvAPI_Initialize','NvAPI_Unload','NvAPI_SYS_GetDriverAndBranchVersion','NvAPI_DRS_CreateSession','NvAPI_DRS_DestroySession','NvAPI_DRS_LoadSettings','NvAPI_DRS_FindApplicationByName','NvAPI_DRS_GetProfileInfo','NvAPI_DRS_GetBaseProfile','NvAPI_DRS_GetCurrentGlobalProfile','NvAPI_DRS_GetSetting','NvAPI_DRS_EnumAvailableSettingValues')
Check ($ids.Count -eq $names.Count -and @($ids | Sort-Object -Unique).Count -eq $names.Count) 'only reviewed read/lifecycle interfaces bound'
foreach($name in $names){Check ($ids -contains [uint32]$oracle.interfaceIds.$name) ('official query-interface ID '+$name)}
foreach($name in @('NvAPI_DRS_SetSetting','NvAPI_DRS_SaveSettings','NvAPI_DRS_DeleteProfile','NvAPI_DRS_CreateApplication','NvAPI_DRS_RestoreAllDefaults')){
 Check ($ids -notcontains [uint32]$oracle.interfaceIds.$name) ('write/persistence interface not exposed '+$name)
}
$ids[0]=0;Check ([WinSlim.Development.NvapiReadOnly.InstalledReader]::InterfaceIds()[0] -eq 0x0150e828) 'caller cannot change interface allowlist'
function Fixture {New-Object WinSlim.Development.NvapiReadOnlyTests.FixtureApi}
function Read($api){[WinSlim.Development.NvapiReadOnly.Reader]::Read($api,'C:\Games\One\game.exe')}
$api=Fixture;$result=Read $api
Check ($result.Status -ceq 'ReadOnlySnapshot' -and $result.HasValue -and $result.Value -eq 60 -and $result.Origin -ceq 'CurrentExplicit') 'explicit DWORD value read from fixture'
Check ($api.LastPath -ceq 'c:\games\one\game.exe' -and $api.Destroys -eq 1 -and $api.Unloads -eq 1) 'full executable path used; only own session released'
Check (-not $result.CanApplyToDriver -and -not $result.PhysicalFrameLimitTested -and $result.ReadOnly) 'read result never authorizes driver writes or FPS claim'
Check (($result.RawEnumeratedValues -join ',') -ceq '0,0,1023' -and -not $result.EnumeratedValuesAreCompleteRange) 'raw range-like values preserved without inventing supported FPS list'
foreach($location in 0..3){$api=Fixture;$api.Location=$location;$r=Read $api;Check ($r.SettingLocation -eq $location -and $r.HasValue -and $r.Origin -ceq @('CurrentExplicit','GlobalInherited','BaseInherited','DefaultInherited')[$location]) ('setting origin preserved '+$location)}
$api=Fixture;$api.CurrentPredefined=1;$r=Read $api;Check ($r.Origin -ceq 'CurrentPredefined' -and $r.CurrentPredefined) 'current predefined state distinct from explicit'
$api=Fixture;$api.PredefinedValid=0;$r=Read $api;Check ($null -eq $r.PredefinedValue) 'invalid predefined data never shown as zero'
$api=Fixture;$api.Value=0;$r=Read $api;Check ($r.HasValue -and $r.Value -eq 0 -and $r.Origin -ceq 'CurrentExplicit') 'explicit zero remains present'
$api=Fixture;$api.Missing=$true;$r=Read $api;Check (-not $r.HasValue -and $null -eq $r.Value -and $r.Origin -ceq 'Absent') 'missing setting never fabricated as zero'
foreach($field in @('Generic','GlobalProfile')){$api=Fixture;$api.$field=$true;$r=Read $api;Check (-not $r.CanApplyToDriver -and $r.ReadComplete -and ($r.Mapping -ne 'ExactStoredPath' -or $r.GlobalProfile)) ('readonly global/generic mapping is not writable '+$field)}
$api=Fixture;$api.Apps=2;$r=Read $api;Check ($r.SharedProfile -and $r.EligibilityReason -ceq 'Shared or empty profile') 'shared profile explicitly diagnosed'
$api=Fixture;$api.Flags=2;$r=Read $api;Check ($r.EligibilityReason -ceq 'Qualified or command-line association') 'qualified match not claimed as exclusive game association'
foreach($failure in @('Initialize','DriverVersion','CreateSession','LoadSettings','FindFullPath','ProfileInfo','BaseProfile','GlobalProfile','GetSetting')){
 $api=Fixture;$api.Failure=$failure;$r=Read $api
 Check ($r.Status -ceq 'Unavailable' -and -not $r.CanApplyToDriver -and $null -eq $r.Value) ('native error fails closed '+$failure)
 Check ($api.Unloads -eq $(if($failure -ceq 'Initialize'){0}else{1}) -and $api.Destroys -eq $(if($failure -in @('Initialize','DriverVersion','CreateSession')){0}else{1})) ('cleanup limited to acquired resources '+$failure)
}
foreach($failure in @('DestroySession','Unload')){$api=Fixture;$api.Failure=$failure;$r=Read $api;Check ($r.Status -ceq 'CleanupFailed' -and -not $r.ReadComplete -and $r.CleanupErrors.Count -gt 0) ('cleanup failure not hidden '+$failure)}
$api=Fixture;$api.ThrowSetting=$true;$r=Read $api;Check ($r.Status -ceq 'Unavailable' -and $api.Destroys -eq 1 -and $api.Unloads -eq 1) 'read exception releases session'
$api=Fixture;$api.Failure='EnumAvailableSettingValues';$r=Read $api;Check ($r.Status -ceq 'PartialCapabilitiesUnavailable' -and -not $r.ReadComplete -and $r.RawEnumeratedValues.Count -eq 0 -and $r.HasValue) 'partial capability is not complete support'
foreach($field in @('SettingType','Location','SettingVersion','AppVersion','CapabilityCount')){
 $api=Fixture;$api.$field=$(switch($field){'SettingType'{1};'Location'{99};'CapabilityCount'{101};default{0}});$r=Read $api
 Check ($r.Status -ceq 'Unavailable' -and -not $r.ReadComplete -and -not $r.CanApplyToDriver) ('ABI/contract mismatch rejected '+$field)
}
foreach($path in @('game.exe','C:game.exe','\\host\share\game.exe','C:\game.exe:stream','C:\game.dll')){
 $api=Fixture;Reject {[WinSlim.Development.NvapiReadOnly.Reader]::Read($api,$path)} 'invalid executable identity rejected';Check ($api.Calls -eq 0) 'invalid identity performs no driver calls'
}
Check (Test-WinSlimNvApiDriverTrust 'AMD64' 'Valid' 'CN=NVIDIA Corporation, O=NVIDIA Corporation' 0x8664) 'reviewed signer/architecture gate accepts exact fixture'
foreach($case in @(@('ARM64','Valid','CN=NVIDIA Corporation',0x8664),@('AMD64','UnknownError','CN=NVIDIA Corporation',0x8664),@('AMD64','Valid','CN=Fake NVIDIA Corporation',0x8664),@('AMD64','Valid','CN=NVIDIA Corporation',0xAA64))){Check (-not (Test-WinSlimNvApiDriverTrust $case[0] $case[1] $case[2] $case[3])) 'untrusted/unsupported native library cannot pass loader prerequisite'}
. (Join-Path $Root 'tools/prototypes/FrameLimitPlan.ps1')
$api=Fixture;$r=Read $api;Reject {New-WinSlimFrameLimitPlan -Snapshot $r -GamePath 'C:\Games\One\game.exe' -Value 60} 'real-reader DTO cannot be relabeled as offline planner fixture'
[pscustomobject]@{Checks=$script:checks;FixtureOnly=$true;PhysicalNvapiCallTested=$false;CanApplyToDriver=$false;Build=$build} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $build 'result.json') -Encoding UTF8
Write-Host ('NvapiReadOnly: '+$script:checks+' behavioral/ABI checks passed; transport fixtures only; no GPU driver or held family executed. Build: '+$build)
