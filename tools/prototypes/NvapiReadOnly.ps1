#requires -Version 5.1
# Development module. No automatic probe, driver installation, UI registration or setting writes.
function Import-WinSlimNvApiReadOnlyPrototype {
 param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$BuildDirectory,[switch]$WithFixture)
 . (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
 Assert-WinSlimTestExecutionAllowed -Family NvapiReadOnly
 $rootFull=[IO.Path]::GetFullPath($Root);$build=[IO.Path]::GetFullPath($BuildDirectory)
 if(-not $build.StartsWith($rootFull.TrimEnd('\')+'\logs\',[StringComparison]::OrdinalIgnoreCase)){throw 'Development build must remain under workspace logs.'}
 $sdk=Get-Content -LiteralPath (Join-Path $Root 'specs/NVAPI-SDK-R3.2.84.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($sdk.commit -cne '70d337db9186e968eab622f7e786de7e437faf3d' -or @($sdk.files).Count -ne 8){throw 'Reviewed SDK pin required.'}
 foreach($item in $sdk.files){
  $path=[IO.Path]::GetFullPath((Join-Path $Root $item.path))
  if(-not $path.StartsWith((Join-Path $rootFull ('third_party\NvApiSdk\'+$sdk.commit+'\')),[StringComparison]::OrdinalIgnoreCase) -or
      (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $item.sha256){throw 'Pinned SDK source mismatch.'}
 }
 $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
 if(-not [Environment]::Is64BitProcess -or -not (Test-Path -LiteralPath $csc)){throw 'Windows x64 .NET Framework compiler required.'}
 [void][IO.Directory]::CreateDirectory($build);$dll=Join-Path $build 'NvapiReadOnly.Prototype.dll'
 if(Test-Path -LiteralPath $dll){throw 'Preserve previous prototype artifact; use a new build directory.'}
 $sources=@((Join-Path $Root 'tools/prototypes/NvapiReadOnly.cs'))
 if($WithFixture){$sources+=Join-Path $Root 'tests/fixtures/NvapiReadOnlyFixture.cs'}
 $args=@('/nologo','/target:library','/platform:x64','/optimize+',('/out:'+$dll),'/reference:System.dll','/reference:System.Core.dll')+$sources
 & $csc @args 2>&1 | Set-Content -LiteralPath (Join-Path $build 'compiler.log') -Encoding UTF8
 if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $dll)){throw 'Readonly prototype compilation failed; preserve compiler log.'}
 $provenance=[ordered]@{Family='NvapiReadOnly';Source='independent new readonly adapter; not PresentMonHarness/MonitorHarness';SdkCommit=$sdk.commit;
  Compiler=$csc;CompilerSHA256=(Get-FileHash -LiteralPath $csc -Algorithm SHA256).Hash;Sources=@(foreach($source in $sources){[pscustomobject]@{Path=$source;SHA256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}});
  Output=$dll;OutputSHA256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash;Fixture=[bool]$WithFixture;Utc=[DateTime]::UtcNow.ToString('o');CanApplyToDriver=$false}
 $provenance | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $build 'provenance-before-load.json') -Encoding UTF8
 [Reflection.Assembly]::LoadFrom($dll)
}
function Test-WinSlimNvApiDriverTrust {
 param([string]$Architecture,[string]$SignatureStatus,[string]$Subject,[int]$PeMachine)
 return ($Architecture -ceq 'AMD64' -and $PeMachine -eq 0x8664 -and $SignatureStatus -ceq 'Valid' -and $Subject -cmatch '(^|,\s*)CN=NVIDIA Corporation(,|$)')
}
function Get-WinSlimNvApiReadOnlySnapshot {
 param([Parameter(Mandatory=$true)][string]$GamePath)
 $null=[WinSlim.Development.NvapiReadOnly.Abi]::GameKey($GamePath)
 $path=Join-Path ([Environment]::SystemDirectory) 'nvapi64.dll'
 if(-not (Test-Path -LiteralPath $path)){return [WinSlim.Development.NvapiReadOnly.InstalledReader]::ReadValidatedSystemLibrary($GamePath,$null)}
 $signature=Get-AuthenticodeSignature -LiteralPath $path
 $bytes=[IO.File]::ReadAllBytes($path)
 if($bytes.Length -lt 64){throw 'Invalid installed NVAPI PE.'}
 $pe=[BitConverter]::ToInt32($bytes,60)
 if($pe -lt 64 -or $pe -gt ($bytes.Length-6) -or [BitConverter]::ToUInt32($bytes,$pe) -ne 0x4550){throw 'Invalid installed NVAPI PE header.'}
 $machine=[BitConverter]::ToUInt16($bytes,$pe+4)
 if(-not (Test-WinSlimNvApiDriverTrust $env:PROCESSOR_ARCHITECTURE ([string]$signature.Status) ([string]$signature.SignerCertificate.Subject) $machine)){
  return [pscustomobject]@{Source='nvapi-readonly';Status='Unavailable';Stage='ArchitectureOrSignatureNotApproved';ReadOnly=$true;CanApplyToDriver=$false;HasValue=$false;Value=$null}
 }
 $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
 try {[WinSlim.Development.NvapiReadOnly.InstalledReader]::ReadValidatedSystemLibrary($GamePath,$hash)}
 catch {[pscustomobject]@{Source='nvapi-readonly';Status='Unavailable';Stage='NativeBindingUnavailable';Error=$_.Exception.GetBaseException().Message;ReadOnly=$true;CanApplyToDriver=$false;HasValue=$false;Value=$null}}
}
