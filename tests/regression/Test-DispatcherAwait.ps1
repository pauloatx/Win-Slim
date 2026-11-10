#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('winslim-dispatcher-regression-'+[guid]::NewGuid().ToString('N'))
try {
 [void][IO.Directory]::CreateDirectory($dir)
 $framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
 if(-not (Test-Path -LiteralPath (Join-Path $framework 'csc.exe'))){$framework=Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319'}
 $compiler=Join-Path $framework 'csc.exe'
 $windowsBase=Join-Path $framework 'WPF\WindowsBase.dll'
 if(-not (Test-Path -LiteralPath $windowsBase)){$windowsBase=Join-Path $framework 'WindowsBase.dll'}
 if(-not (Test-Path -LiteralPath $compiler) -or -not (Test-Path -LiteralPath $windowsBase)){throw 'Compilador ou WindowsBase indisponivel; regressao nao validada.'}
 $prefix='using System; using System.Threading.Tasks; using System.Windows.Threading; public static class Repro { public static async Task Run(Dispatcher dispatcher) { '
 $broken=$prefix+'dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate { })); await Task.Yield(); } }'
 $fixed=$prefix+'DispatcherOperation operation = dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate { })); await operation; } }'
 foreach($kind in @('broken','fixed')){
  $src=Join-Path $dir ($kind+'.cs');$dll=Join-Path $dir ($kind+'.dll')
  [IO.File]::WriteAllText($src,$(if($kind -eq 'broken'){$broken}else{$fixed}), (New-Object Text.UTF8Encoding($false)))
  $output=@(& $compiler /noconfig /nologo /target:library /langversion:5 /warn:4 /warnaserror:4014 ('/reference:'+ $windowsBase) ('/out:'+ $dll) $src 2>&1)
  $code=$LASTEXITCODE
  if($kind -eq 'broken'){
   if($code -eq 0 -or ($output -join "`n") -notmatch 'CS4014'){throw ('O reproducer defeituoso nao foi rejeitado por CS4014: '+($output -join "`n"))}
   Write-Host '[OK] Caso anterior: BeginInvoke ignorado falha por CS4014.'
  }else{
   if($code -ne 0 -or -not (Test-Path -LiteralPath $dll)){throw ('Operacao aguardada nao compilou: '+($output -join "`n"))}
   Write-Host '[OK] Caso corrigido: operacao do Dispatcher acompanhada e aguardada compila.'
  }
 }
} finally {if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force}}
