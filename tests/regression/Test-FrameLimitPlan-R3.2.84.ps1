#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'tools/prototypes/FrameLimitPlan.ps1')
$script:checks=0
function Check([bool]$Ok,[string]$Label) { if(-not $Ok) { throw $Label };$script:checks++;Write-Host ('[OK] '+$Label) }
function Reject([scriptblock]$Action,[string]$Label) { $failed=$false;try { & $Action | Out-Null } catch { $failed=$true };Check $failed $Label }
function New-Fixture {
    # Values are illustrative. No physical driver capability or FPS encoding is claimed.
    [pscustomobject][ordered]@{
        SchemaVersion=1;Source='fixture';Available=$true;Complete=$true;ContractVersion=1;SettingId='FRL_FPS_ID'
        SupportedValues=@(0,30,60,120)
        Profiles=@(
            [pscustomobject]@{Id='global';Global=$true;Applications=@();Setting=[pscustomobject]@{Origin='Explicit';Value=0};Other='global-preserved'},
            [pscustomobject]@{Id='cities';Global=$false;Applications=@('C:\Games\Cities.exe');Setting=[pscustomobject]@{Origin='Explicit';Value=30};Other='vsync-preserved'},
            [pscustomobject]@{Id='other';Global=$false;Applications=@('D:\Other\Cities.exe');Setting=[pscustomobject]@{Origin='Inherited';Value=120};Other='another-game'}
        )
    }
}
$fixture=New-Fixture;$original=Get-WinSlimFrameLimitDigest $fixture
$plan=New-WinSlimFrameLimitPlan $fixture 'c:\games\CITIES.exe' 60
Check ($plan.ProfileId -ceq 'cities' -and $plan.Action -ceq 'SetExplicit' -and -not $plan.CanApplyToDriver) 'full executable identity and explicit offline-only proposal'
$receipt=Invoke-WinSlimFrameLimitFixtureTransition $fixture $plan
Check ($receipt.After.Profiles[1].Setting.Value -eq 60 -and $receipt.After.Profiles[1].Setting.Origin -ceq 'Explicit') 'fixture transition changes only requested setting'
Check ((Get-WinSlimFrameLimitDigest $fixture) -ceq $original) 'input fixture and backup source never mutated'
Check ((Get-WinSlimFrameLimitDigest $receipt.Before) -ceq $original) 'backup snapshot contains complete original state'
Check ((Get-WinSlimFrameLimitDigest $fixture.Profiles[0]) -ceq (Get-WinSlimFrameLimitDigest $receipt.After.Profiles[0]) -and
       (Get-WinSlimFrameLimitDigest $fixture.Profiles[2]) -ceq (Get-WinSlimFrameLimitDigest $receipt.After.Profiles[2]) -and
       $receipt.After.Profiles[1].Other -ceq 'vsync-preserved') 'global, same-name other executable and unrelated settings preserved'
Check (Test-WinSlimFrameLimitFixtureResult $receipt $receipt.After) 'verify accepts complete expected fixture state'
$restored=Undo-WinSlimFrameLimitFixtureTransition $receipt $receipt.After
Check ((Get-WinSlimFrameLimitDigest $restored) -ceq $original) 'undo returns complete original fixture'
foreach($origin in @('Absent','Inherited','Predefined','Explicit')) {
    $state=New-Fixture;$state.Profiles[1].Setting.Origin=$origin
    $state.Profiles[1].Setting.Value=$(if($origin -eq 'Absent'){$null}else{30})
    $before=Get-WinSlimFrameLimitDigest $state
    $r=Invoke-WinSlimFrameLimitFixtureTransition $state (New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60)
    Check ((Get-WinSlimFrameLimitDigest (Undo-WinSlimFrameLimitFixtureTransition $r $r.After)) -ceq $before) ('undo preserves origin/value: '+$origin)
}
foreach($origin in @('Inherited','Predefined','Explicit')) {
    $state=New-Fixture;$state.Profiles[1].Setting.Origin=$origin
    $before=Get-WinSlimFrameLimitDigest $state
    $r=Invoke-WinSlimFrameLimitFixtureTransition $state (New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 30)
    Check ($r.Plan.Action -ceq 'NoChange' -and (Get-WinSlimFrameLimitDigest $r.After) -ceq $before) ('already effective value does not materialize override: '+$origin)
}
foreach($stage in @('Backup','Set','Save','Verify')) {
    Reject { Invoke-WinSlimFrameLimitFixtureTransition $fixture $plan -FailureStage $stage } ('failure before publishing any fixture transition: '+$stage)
    Check ((Get-WinSlimFrameLimitDigest $fixture) -ceq $original) ('failure preserves caller state: '+$stage)
}
foreach($value in @(-1,1,61,1024,'60',60.5,$null)) { Reject { New-WinSlimFrameLimitPlan $fixture 'C:\Games\Cities.exe' $value } ('unsupported/untyped desired value rejected: '+[string]$value) }
foreach($game in @('Cities.exe','C:Cities.exe','\\host\share\Cities.exe','C:\Games\Cities.exe:stream','C:\Games\x.csv','C:\Missing.exe')) {
    Reject { New-WinSlimFrameLimitPlan $fixture $game 60 } ('invalid or unassociated path rejected: '+$game)
}
$state=New-Fixture;$state.Profiles[1].Applications+=@('C:\Games\Other.exe')
Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } 'shared profile rejected without affecting another game'
$state=New-Fixture;$state.Profiles[0].Applications=@('C:\Games\Cities.exe');$state.Profiles[1].Applications=@()
Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } 'global profile rejected'
$state=New-Fixture;$state.Profiles[2].Applications=@('C:\Games\Cities.exe')
Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } 'ambiguous executable association rejected'
foreach($field in @('Available','Complete','ContractVersion','Source','SettingId','SupportedValues','Profiles')) {
    $state=New-Fixture
    switch($field) {
        'Available' { $state.Available=$false };'Complete' { $state.Complete=$false }
        'ContractVersion' { $state.ContractVersion=2 };'Source' { $state.Source='physical-driver' }
        'SettingId' { $state.SettingId='other' };'SupportedValues' { $state.SupportedValues=@() };'Profiles' { $state.Profiles=@() }
    }
    Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } ('unavailable/incompatible/incomplete snapshot rejected: '+$field)
}
$state=New-Fixture;$state.Profiles[1].Setting.Origin='Absent';$state.Profiles[1].Setting.Value=0
Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } 'missing value is not confused with disabled zero'
$disabled=Invoke-WinSlimFrameLimitFixtureTransition $fixture (New-WinSlimFrameLimitPlan $fixture 'C:\Games\Cities.exe' 0)
Check ($disabled.After.Profiles[1].Setting.Origin -eq 'Explicit' -and $disabled.After.Profiles[1].Setting.Value -eq 0) 'illustrative supported zero is an explicit value, not deletion'
foreach($field in @('ProfileId','Action','Before','CanApplyToDriver','Value')) {
    $bad=Copy-WinSlimFrameLimitData $plan
    switch($field) {
        'ProfileId' { $bad.ProfileId='global' };'Action' { $bad.Action='NoChange' }
        'Before' { $bad.Before.Value=99 };'CanApplyToDriver' { $bad.CanApplyToDriver=$true };'Value' { $bad.Value=120 }
    }
    Reject { Invoke-WinSlimFrameLimitFixtureTransition $fixture $bad } ('altered plan rejected: '+$field)
}
$changed=Copy-WinSlimFrameLimitData $fixture;$changed.Profiles[1].Setting.Value=120
Reject { Invoke-WinSlimFrameLimitFixtureTransition $changed $plan } 'stale review cannot overwrite external change'
$changed=Copy-WinSlimFrameLimitData $receipt.After;$changed.Profiles[1].Setting.Value=120
Check (-not (Test-WinSlimFrameLimitFixtureResult $receipt $changed)) 'verify rejects diverging target state'
Reject { Undo-WinSlimFrameLimitFixtureTransition $receipt $changed } 'undo refuses external target change'
$changed=Copy-WinSlimFrameLimitData $receipt.After;$changed.Profiles[2].Other='external'
Reject { Undo-WinSlimFrameLimitFixtureTransition $receipt $changed } 'conservative undo refuses unrelated concurrent change'
$bad=Copy-WinSlimFrameLimitData $receipt;$bad.After.Profiles[0].Setting.Value=120
Reject { Undo-WinSlimFrameLimitFixtureTransition $bad $receipt.After } 'altered receipt rejected'
$bad=Copy-WinSlimFrameLimitData $receipt;$bad.Before=$null
Reject { Undo-WinSlimFrameLimitFixtureTransition $bad $receipt.After } 'unavailable backup rejected'
foreach($failure in @('DuplicateId','DuplicateValues','MissingValue','InvalidOrigin','WrongType')) {
    $state=New-Fixture
    switch($failure) {
        'DuplicateId' { $state.Profiles[2].Id='cities' };'DuplicateValues' { $state.SupportedValues=@(0,60,60) }
        'MissingValue' { $state.Profiles[1].Setting.Value=$null };'InvalidOrigin' { $state.Profiles[1].Setting.Origin='Unknown' }
        'WrongType' { $state.Available='true' }
    }
    Reject { New-WinSlimFrameLimitPlan $state 'C:\Games\Cities.exe' 60 } ('malformed capability/profile rejected: '+$failure)
}
$restored.Profiles[1].Other='caller edit'
Check ($receipt.Before.Profiles[1].Other -eq 'vsync-preserved' -and (Get-WinSlimFrameLimitDigest $fixture) -ceq $original) 'returned snapshots are independent deep copies'
Write-Host ('[OK] REG-FRAMELIMITPLAN-001: '+$script:checks+' offline contract checks; no driver, compiler, PresentMon or physical acceptance.')
