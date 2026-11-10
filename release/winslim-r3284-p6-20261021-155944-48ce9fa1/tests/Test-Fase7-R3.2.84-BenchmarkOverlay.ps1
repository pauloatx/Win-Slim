#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[string]$PreviewDirectory)
$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('winslim-overlay-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($temp)
 $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
 if(-not (Test-Path -LiteralPath (Join-Path $framework 'csc.exe'))){$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319'}
 foreach($name in @('PresentationFramework','PresentationCore','WindowsBase','System.Xaml','System.Web.Extensions')){Add-Type -AssemblyName $name}
 $references=@([Windows.Window].Assembly.Location,[Windows.Media.Brush].Assembly.Location,[Windows.DependencyObject].Assembly.Location,[System.Xaml.XamlServices].Assembly.Location,[Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,[System.Xml.XmlReader].Assembly.Location,[System.Diagnostics.Process].Assembly.Location,[System.Linq.Enumerable].Assembly.Location) | Select-Object -Unique | ForEach-Object {'/reference:'+$_}
 $sources=@('PresentMonBenchmark.cs','BenchmarkLive.cs','BenchmarkGameWindow.cs','BenchmarkOverlay.cs','BenchmarkOverlayDesktop.cs','UiLanguage.cs') | ForEach-Object {Join-Path $Root ('src\UI\Native\R3_2_84\'+$_)}
 $exe=Join-Path $temp 'BenchmarkOverlayHarness.exe'
 & (Join-Path $framework 'csc.exe') /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014 @references ('/out:'+$exe) @sources (Join-Path $Root 'tests\BenchmarkOverlayHarness.cs')
 if($LASTEXITCODE -ne 0){throw 'Overlay harness compilation failed.'}
 & $exe $Root $PreviewDirectory
 if($LASTEXITCODE -ne 0){throw 'Overlay behavioral regression failed.'}
} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}}
