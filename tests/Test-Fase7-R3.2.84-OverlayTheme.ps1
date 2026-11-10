#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
Assert-WinSlimTestExecutionAllowed -Family OverlayThemeFixtures
. (Join-Path $Root 'tools/TestArtifactProvenance.ps1')
$build=Join-Path $Root ('logs/overlay-theme-fixture-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($build)
$compiler=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
foreach($name in @('PresentationFramework','PresentationCore','WindowsBase','System.Xaml','System.Web.Extensions')){Add-Type -AssemblyName $name}
$refs=@([Windows.Window].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[System.Xaml.XamlServices].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[System.Xml.XmlReader].Assembly.Location,[Diagnostics.Process].Assembly.Location,[Linq.Enumerable].Assembly.Location)|Select-Object -Unique|ForEach-Object {'/reference:'+$_}
$sources=@('PresentMonBenchmark.cs','BenchmarkLive.cs','PresentMonMonitor.cs','BenchmarkGameWindow.cs','BenchmarkOverlay.cs','BenchmarkOverlayDesktop.cs','BenchmarkSettings.cs','BenchmarkSettingsWindow.cs','UiLanguage.cs')|ForEach-Object {Join-Path $Root ('src/UI/Native/R3_2_84/'+$_)}
$sources+=Join-Path $Root 'tests/fixtures/OverlayThemeFixture.cs'
$dll=Join-Path $build 'WinSlim.OverlayTheme.Fixture.dll'
& $compiler /nologo /noconfig /target:library /platform:anycpu /optimize+ /debug- /warn:4 /warnaserror:4014 /langversion:5 /codepage:65001 /utf8output @refs ('/out:'+$dll) @sources 2>&1|Set-Content (Join-Path $build 'compiler.log') -Encoding UTF8
$compilerExit=$LASTEXITCODE
$record=Write-WinSlimTestArtifactRecord -Root $Root -Artifact $dll -Compiler $compiler -Sources $sources -CompilerExit $compilerExit
Copy-Item -LiteralPath $record.Path -Destination (Join-Path $build 'provenance-before-load.json')
Write-Host ('Overlay theme evidence: '+$build)
if($compilerExit -ne 0 -or -not $record.ArtifactReadable -or -not $record.InputsReadable){throw 'Theme fixture compilation/provenance failed; evidence retained.'}
$assembly=[Reflection.Assembly]::LoadFrom($dll)
if($null -ne $assembly.EntryPoint){throw 'Theme fixture must have no entry point.'}
$arguments=New-Object object[] 1
$arguments[0]=[string](Join-Path $build 'isolated-state')
try {
 $results=@($assembly.GetType('WinSlim.NativeUI.OverlayThemeFixture',$true).GetMethod('RunAll').Invoke($null,$arguments))
 $results|Set-Content (Join-Path $build 'checks.log') -Encoding UTF8
 $results|ForEach-Object {Write-Host $_}
 $failed=@($results|Where-Object {$_ -notlike '[[]OK]*'})
 [ordered]@{Utc=[DateTime]::UtcNow.ToString('o');Case='REG-OVERLAYTHEME-001';Checks=$results.Count;Failed=$failed.Count;Passed=($results.Count -gt 0 -and $failed.Count -eq 0);ArtifactSHA256=$record.ArtifactSHA256;ContainsEntryPoint=$false}|ConvertTo-Json|Set-Content (Join-Path $build 'result.json') -Encoding UTF8
 if($results.Count -eq 0 -or $failed.Count -gt 0){throw ('Overlay theme behavioral regression failed: '+$failed.Count+'/'+$results.Count)}
} catch {
 Write-WinSlimTestArtifactRecord -Root $Root -Artifact $dll -Compiler $compiler -Sources $sources -CompilerExit $compilerExit -Stage ExecutionFailed|Out-Null
 throw
}
