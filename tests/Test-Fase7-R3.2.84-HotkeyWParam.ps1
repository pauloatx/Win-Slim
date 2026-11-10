#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family HotkeyWParamFixtures
. (Join-Path $Root 'tools/TestArtifactProvenance.ps1')
if(-not [Environment]::Is64BitProcess){throw 'Requires 64-bit Windows PowerShell/WPF; native-width regression cannot be skipped.'}
$build=Join-Path $Root ('logs/hotkey-wparam-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($build)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
foreach($name in @('PresentationFramework','PresentationCore','WindowsBase','System.Xaml','System.Web.Extensions')){Add-Type -AssemblyName $name}
$refs=@([Windows.Window].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[System.Xaml.XamlServices].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[System.Xml.XmlReader].Assembly.Location,[System.Diagnostics.Process].Assembly.Location,[System.Linq.Enumerable].Assembly.Location) | Select-Object -Unique | ForEach-Object {'/reference:'+$_}
$sources=@((Join-Path $Root 'src/UI/Native/R3_2_84/BenchmarkSettings.cs'),(Join-Path $Root 'tests/fixtures/HotkeyWParamFixture.cs'))
$dll=Join-Path $build 'WinSlim.HotkeyWParam.Fixture.dll'
& $compiler /nologo /noconfig /target:library /platform:anycpu /optimize+ /debug- /warn:4 /warnaserror:4014 /langversion:5 /codepage:65001 /utf8output @refs ('/out:'+$dll) @sources 2>&1 | Set-Content (Join-Path $build 'compiler.log') -Encoding UTF8
$compilerExit=$LASTEXITCODE
$record=Write-WinSlimTestArtifactRecord -Root $Root -Artifact $dll -Compiler $compiler -Sources $sources -CompilerExit $compilerExit
Copy-Item -LiteralPath $record.Path -Destination (Join-Path $build 'provenance-before-load.json')
Write-Host ('Hotkey fixture evidence: '+$build)
if($compilerExit -ne 0 -or -not $record.ArtifactReadable -or -not $record.InputsReadable){throw 'Hotkey fixture compilation/provenance failed; evidence retained.'}
$assembly=[Reflection.Assembly]::LoadFrom($dll)
if($null -ne $assembly.EntryPoint){throw 'Hotkey fixture must be DLL-only without Main.'}
try {
 $arguments=New-Object object[] 1
 $arguments[0]=[string](Join-Path $build 'isolated-state')
 $results=@($assembly.GetType('WinSlim.NativeUI.HotkeyWParamFixture',$true).GetMethod('RunAll').Invoke($null,$arguments))
 $results | Set-Content (Join-Path $build 'checks.log') -Encoding UTF8
 $results | ForEach-Object {Write-Host $_}
 $failed=@($results | Where-Object {$_ -notlike '[[]OK]*'})
 [ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Case='REG-HOTKEY-001';Checks=$results.Count;Failed=$failed.Count;Passed=($results.Count -gt 0 -and $failed.Count -eq 0);ArtifactSHA256=$record.ArtifactSHA256;ContainsEntryPoint=$false;NativeWidth=64} | ConvertTo-Json | Set-Content (Join-Path $build 'result.json') -Encoding UTF8
 if($results.Count -eq 0 -or $failed.Count -gt 0){throw ('Hotkey behavioral regression failed: '+$failed.Count+'/'+$results.Count)}
 Write-Host ('[OK] HotkeyWParam: '+$results.Count+' behavioral checks; WPF STA, production Hook, DLL only.')
} catch {
 Write-WinSlimTestArtifactRecord -Root $Root -Artifact $dll -Compiler $compiler -Sources $sources -CompilerExit $compilerExit -Stage ExecutionFailed | Out-Null
 throw
}
