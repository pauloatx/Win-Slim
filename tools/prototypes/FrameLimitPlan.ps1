#requires -Version 5.1
# Development-only state model. No driver/registry/process/file I/O or runtime registration.
# Inputs marked fixture are illustrative; they are not a successful NVAPI probe.
function Copy-WinSlimFrameLimitData($Data) {
    ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Data -Depth 40 -Compress)
}
function Get-WinSlimFrameLimitDigest($Data) {
    $json=ConvertTo-Json -InputObject $Data -Depth 40 -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($json)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-WinSlimFrameLimitGameKey([string]$GamePath) {
    if($GamePath -notmatch '\A[A-Za-z]:[\\/]' -or $GamePath -match '[\x00-\x1f"<>|*?]' -or $GamePath.Substring(2).Contains(':')) { throw 'A full local executable path is required.' }
    $full=[IO.Path]::GetFullPath($GamePath)
    if([IO.Path]::GetExtension($full) -ine '.exe') { throw 'An executable path is required.' }
    $full.ToLowerInvariant()
}
function Test-WinSlimFrameLimitDword($Value) {
    ($Value -is [int] -or $Value -is [long] -or $Value -is [uint32]) -and $Value -ge 0 -and $Value -le [uint32]::MaxValue
}
function Assert-WinSlimFrameLimitFixture($Snapshot) {
    if($null -eq $Snapshot -or $Snapshot.SchemaVersion -ne 1 -or $Snapshot.Source -cne 'fixture' -or
       $Snapshot.Available -isnot [bool] -or -not $Snapshot.Available -or
       $Snapshot.Complete -isnot [bool] -or -not $Snapshot.Complete -or $Snapshot.ContractVersion -ne 1 -or
       $Snapshot.SettingId -cne 'FRL_FPS_ID') { throw 'Unavailable, incomplete or incompatible fixture snapshot.' }
    $values=@($Snapshot.SupportedValues)
    if($values.Count -eq 0) { throw 'Supported values are unavailable.' }
    foreach($value in $values) { if(-not (Test-WinSlimFrameLimitDword $value)) { throw 'Invalid supported value.' } }
    if(@($values | Select-Object -Unique).Count -ne $values.Count) { throw 'Duplicate supported values.' }
    if($null -eq $Snapshot.Profiles -or @($Snapshot.Profiles).Count -eq 0) { throw 'Profiles are unavailable.' }
    $ids=@{}
    foreach($profile in @($Snapshot.Profiles)) {
        if([string]::IsNullOrWhiteSpace([string]$profile.Id) -or $ids.ContainsKey([string]$profile.Id) -or
           $profile.Global -isnot [bool] -or $null -eq $profile.Applications -or $null -eq $profile.Setting) { throw 'Invalid or duplicate profile.' }
        $ids[[string]$profile.Id]=$true
        foreach($app in @($profile.Applications)) { Get-WinSlimFrameLimitGameKey $app | Out-Null }
        if(@('Explicit','Inherited','Absent','Predefined') -cnotcontains $profile.Setting.Origin) { throw 'Unknown setting origin.' }
        if($profile.Setting.Origin -eq 'Absent') {
            if($null -ne $profile.Setting.Value) { throw 'An absent setting must not contain a fake zero.' }
        } elseif(-not (Test-WinSlimFrameLimitDword $profile.Setting.Value)) { throw 'Setting value is unavailable or invalid.' }
    }
}
function New-WinSlimFrameLimitPlan {
    param([Parameter(Mandatory=$true)]$Snapshot,[Parameter(Mandatory=$true)][string]$GamePath,
          [Parameter(Mandatory=$true)]$Value)
    Assert-WinSlimFrameLimitFixture $Snapshot
    $key=Get-WinSlimFrameLimitGameKey $GamePath
    if(-not (Test-WinSlimFrameLimitDword $Value) -or @($Snapshot.SupportedValues) -notcontains $Value) { throw 'Requested value was not confirmed by the fixture capability.' }
    $matches=@(foreach($profile in @($Snapshot.Profiles)) {
        if(@($profile.Applications | Where-Object { (Get-WinSlimFrameLimitGameKey $_) -ceq $key }).Count -gt 0) { $profile }
    })
    if($matches.Count -ne 1) { throw 'Missing or ambiguous game association.' }
    $target=$matches[0]
    if($target.Global -or @($target.Applications).Count -ne 1) { throw 'Global or shared profile cannot be changed by this prototype.' }
    # Preserve origin: an inherited/predefined value equal to the target is already effective.
    $change=$target.Setting.Origin -eq 'Absent' -or $target.Setting.Value -ne $Value
    $plan=[pscustomobject][ordered]@{
        SchemaVersion=1; Mode='offline-fixture-only'; CanApplyToDriver=$false
        GamePath=$key; ProfileId=$target.Id; Value=$Value
        Before=(Copy-WinSlimFrameLimitData $target.Setting)
        Action=$(if($change){'SetExplicit'}else{'NoChange'})
        SnapshotDigest=(Get-WinSlimFrameLimitDigest $Snapshot)
    }
    $plan | Add-Member -NotePropertyName PlanDigest -NotePropertyValue (Get-WinSlimFrameLimitDigest $plan)
    $plan
}
function Invoke-WinSlimFrameLimitFixtureTransition {
    param([Parameter(Mandatory=$true)]$Snapshot,[Parameter(Mandatory=$true)]$Plan,
          [ValidateSet('None','Backup','Set','Save','Verify')][string]$FailureStage='None')
    # Rebuild rather than trust editable profile/origin/action fields in a proposal.
    $reviewed=New-WinSlimFrameLimitPlan -Snapshot $Snapshot -GamePath $Plan.GamePath -Value $Plan.Value
    if((Get-WinSlimFrameLimitDigest $Plan) -cne (Get-WinSlimFrameLimitDigest $reviewed)) { throw 'Stale or altered proposal; review again.' }
    $before=Copy-WinSlimFrameLimitData $Snapshot
    $after=Copy-WinSlimFrameLimitData $Snapshot
    if($FailureStage -ne 'None') { throw ('Injected fixture '+$FailureStage+' failure; caller snapshot preserved.') }
    if($Plan.Action -eq 'SetExplicit') {
        $profile=@($after.Profiles | Where-Object { $_.Id -ceq $Plan.ProfileId })[0]
        $profile.Setting.Origin='Explicit';$profile.Setting.Value=$Plan.Value
    }
    [pscustomobject][ordered]@{
        SchemaVersion=1; Mode='offline-fixture-only'; CanApplyToDriver=$false
        Plan=(Copy-WinSlimFrameLimitData $Plan); Before=$before; After=$after
    }
}
function Test-WinSlimFrameLimitFixtureResult {
    param([Parameter(Mandatory=$true)]$Receipt,[Parameter(Mandatory=$true)]$CurrentSnapshot)
    try {
        if($Receipt.SchemaVersion -ne 1 -or $Receipt.Mode -cne 'offline-fixture-only' -or $Receipt.CanApplyToDriver -ne $false) { return $false }
        $expected=Invoke-WinSlimFrameLimitFixtureTransition -Snapshot $Receipt.Before -Plan $Receipt.Plan
        ((Get-WinSlimFrameLimitDigest $Receipt.After) -ceq (Get-WinSlimFrameLimitDigest $expected.After)) -and
        ((Get-WinSlimFrameLimitDigest $CurrentSnapshot) -ceq (Get-WinSlimFrameLimitDigest $expected.After))
    } catch { return $false }
}
function Undo-WinSlimFrameLimitFixtureTransition {
    param([Parameter(Mandatory=$true)]$Receipt,[Parameter(Mandatory=$true)]$CurrentSnapshot)
    if(-not (Test-WinSlimFrameLimitFixtureResult -Receipt $Receipt -CurrentSnapshot $CurrentSnapshot)) { throw 'Unavailable, altered receipt or external change; no undo proposal.' }
    # Returning a deep copy is the entire action. Nothing is written to a real driver or disk.
    Copy-WinSlimFrameLimitData $Receipt.Before
}
