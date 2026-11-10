# Pure evidence inventory parsing; no guest, process or registry operations.
function ConvertFrom-WinSlimEdgeVmInventory {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][string]$GuestRoot)
    # PS 5.1 emits the parsed JSON array as one pipeline object. Assign first,
    # then enumerate the variable, rather than wrapping ConvertFrom-Json in @().
    $parsed=ConvertFrom-Json -InputObject $Text -ErrorAction Stop
    $files=@($parsed)
    $seen=@{}
    foreach($file in $files) {
        if($file.Path -isnot [string] -or $file.SHA256 -isnot [string] -or $file.SHA256 -notmatch '\A[0-9a-fA-F]{64}\z'){throw 'Invalid evidence record.'}
        $path=[IO.Path]::GetFullPath($file.Path)
        if($path -cne $file.Path -or (-not $path.StartsWith($GuestRoot+'\evidence\',[StringComparison]::OrdinalIgnoreCase) -and -not $path.StartsWith($GuestRoot+'\Backups\',[StringComparison]::OrdinalIgnoreCase)) -or $path.Substring(2).Contains(':') -or $seen.ContainsKey($path)){throw 'Outside, noncanonical or duplicate evidence record.'}
        $seen[$path]=$true
    }
    if($files.Count -eq 0){throw 'Empty evidence inventory.'}
    $files
}
function Get-WinSlimEdgeVmDirectoryFiles {
    param([object[]]$Files,[string]$GuestRoot,[ValidateSet('evidence','Backups')][string]$Directory)
    foreach($file in $Files) {if($file.Path.StartsWith($GuestRoot+'\'+$Directory+'\',[StringComparison]::OrdinalIgnoreCase)){$file}}
}
function Get-WinSlimEdgeCdpPolicyTarget {
    param([string]$Json,[int]$Port)
    $parsed=ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    $pages=@(foreach($item in @($parsed)){if($item.type -eq 'page'){$item}})
    if($pages.Count -eq 0){throw 'No usable page in isolated Edge.'}
    $known=@($pages | Where-Object {$_.url -match '^edge://policy/?$'})
    $target=if($known.Count){$known[0]}else{$pages[0]};$uri=[Uri]$target.webSocketDebuggerUrl
    if($uri.Scheme -ne 'ws' -or $uri.Host -ne '127.0.0.1' -or $uri.Port -ne $Port){throw 'Only the expected guest loopback endpoint is allowed.'}
    $target
}
