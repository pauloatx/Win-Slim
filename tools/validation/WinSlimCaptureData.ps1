#requires -Version 5.1
# Data fixtures load only production capture classes as a DLL: no Main, fake collector or helper executable.
function Import-WinSlimCaptureDataTypes {
 param([Parameter(Mandatory=$true)][string]$Root,[switch]$IncludeTransportFixtures)
 . (Join-Path $Root 'tools/TestExecutionPolicy.ps1')
 Assert-WinSlimTestExecutionAllowed -Family CaptureDataFixtures
 $script:CaptureBuild=Join-Path $Root ('logs/capture-data-'+[Guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($script:CaptureBuild)
 $compiler=Join-Path $env:SystemRoot 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
 $sources=@('PresentMonBenchmark.cs','BenchmarkLive.cs','PresentMonMonitor.cs') | ForEach-Object {Join-Path $Root ('src/UI/Native/R3_2_84/'+$_)}
 if($IncludeTransportFixtures){$sources+=Join-Path $Root 'tests/fixtures/CaptureTransportFixture.cs'}
 $dll=Join-Path $script:CaptureBuild 'WinSlim.Capture.Data.dll'
 $framework=Split-Path -Parent $compiler
 & $compiler /nologo /noconfig /target:library /langversion:5 /warnaserror:4014 ('/reference:'+(Join-Path $framework 'System.dll')) ('/reference:'+(Join-Path $framework 'System.Core.dll')) ('/out:'+$dll) @sources 2>&1 | Set-Content (Join-Path $script:CaptureBuild 'compiler.log') -Encoding UTF8
 if($LASTEXITCODE -ne 0){throw 'Production capture data-library compilation failed; no harness was included'}
 [ordered]@{Kind='data-fixture-library';ContainsEntryPoint=$false;BlockedHarnessSourceIncluded=$false;Compiler=$compiler;CompilerSHA256=(Get-FileHash $compiler -Algorithm SHA256).Hash;
  Sources=@(foreach($source in $sources){@{Path=$source;SHA256=(Get-FileHash $source -Algorithm SHA256).Hash}});Output=$dll;OutputSHA256=(Get-FileHash $dll -Algorithm SHA256).Hash;Utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $script:CaptureBuild 'provenance-before-load.json') -Encoding UTF8
 $script:CaptureAssembly=[Reflection.Assembly]::LoadFrom($dll)
 if($null -ne $script:CaptureAssembly.EntryPoint){throw 'Data-only library must have no entry point'}
 $script:CaptureFlags=[Reflection.BindingFlags]'Public,NonPublic,Instance,Static'
}
function Invoke-WinSlimCaptureMember {
 param([string]$Type,[string]$Method,[object]$Instance,[object[]]$Arguments=@())
 $typeInfo=$script:CaptureAssembly.GetType('WinSlim.NativeUI.'+$Type,$true)
 $methods=@($typeInfo.GetMethods($script:CaptureFlags) | Where-Object {$_.Name -ceq $Method -and $_.GetParameters().Count -eq $Arguments.Count})
 if($methods.Count -ne 1){throw ('Unambiguous production method required: '+$Type+'.'+$Method)}
 $parameters=$methods[0].GetParameters();$nativeArguments=New-Object object[] $Arguments.Count
 for($i=0;$i -lt $Arguments.Count;$i++){$nativeArguments[$i]=[Management.Automation.LanguagePrimitives]::ConvertTo($Arguments[$i],$parameters[$i].ParameterType)}
 try{return $methods[0].Invoke($Instance,$nativeArguments)}catch{throw $_.Exception.GetBaseException()}
}
function New-WinSlimCaptureObject {
 param([string]$Type,[object[]]$Arguments=@())
 $typeInfo=$script:CaptureAssembly.GetType('WinSlim.NativeUI.'+$Type,$true)
 $constructors=@($typeInfo.GetConstructors($script:CaptureFlags) | Where-Object {$_.GetParameters().Count -eq $Arguments.Count})
 if($constructors.Count -ne 1){throw 'Unambiguous production constructor required'}
 $parameters=$constructors[0].GetParameters();$nativeArguments=New-Object object[] $Arguments.Count
 for($i=0;$i -lt $Arguments.Count;$i++){$nativeArguments[$i]=[Management.Automation.LanguagePrimitives]::ConvertTo($Arguments[$i],$parameters[$i].ParameterType)}
 try{return $constructors[0].Invoke($nativeArguments)}catch{throw $_.Exception.GetBaseException()}
}
function Get-WinSlimCaptureValue {
 param([object]$Instance,[string]$Name)
 $typeInfo=$Instance.GetType();$field=$typeInfo.GetField($Name,$script:CaptureFlags)
 if($field){return $field.GetValue($Instance)}
 $property=$typeInfo.GetProperty($Name,$script:CaptureFlags)
 if($property){return $property.GetValue($Instance,$null)}
 throw ('Production member missing: '+$Name)
}
function Wait-WinSlimCaptureTask {
 param([object]$Task)
 try{return $Task.GetAwaiter().GetResult()}catch{throw $_.Exception.GetBaseException()}
}
