function Resolve-WinSlimRegressionRoot {
 [CmdletBinding()]
 param([AllowNull()][AllowEmptyString()][string]$InputRoot,[Parameter(Mandatory=$true)][string]$ScriptDirectory)
 $candidate=if([string]::IsNullOrWhiteSpace($InputRoot)){$ScriptDirectory}else{$InputRoot}
 try {$item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop}
 catch {throw ('Pasta do projeto invalida: ['+$candidate+']. '+$_.Exception.Message)}
 if(-not ($item -is [IO.DirectoryInfo])){throw ('O caminho precisa ser uma pasta do sistema de arquivos: '+$candidate)}
 return $item.FullName
}
