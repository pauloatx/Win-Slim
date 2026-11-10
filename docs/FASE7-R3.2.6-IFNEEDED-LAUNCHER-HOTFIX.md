# FASE 7 R3.2.6 — IfNeeded / Launcher Hotfix

## Sintoma observado

O gate R3.2.5 aprovava build e self-test. Ao abrir o launcher, que chama o build com `-IfNeeded`, o PowerShell 5.1 retornava `ParameterAlreadyBound` informando que `LiteralPath` havia sido especificado mais de uma vez.

## Causa

O caminho `-IfNeeded` criava uma lista com varias invocacoes `Get-Item` separadas por virgulas dentro de uma expressao de array. Esse formato e fragil no parser do Windows PowerShell 5.1 e pode fazer tokens subsequentes serem associados ao primeiro comando.

## Correcao

Foi adotada construcao explicita:

```powershell
$inputs = New-Object System.Collections.ArrayList
foreach ($sourceItem in @($sources)) { [void]$inputs.Add($sourceItem) }
[void]$inputs.Add((Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlimShell.xaml')))
[void]$inputs.Add((Get-Item -LiteralPath (Join-Path $SourceDir 'WinSlim.UiBridge.ps1')))
[void]$inputs.Add((Get-Item -LiteralPath $ConfigSource))
```

Cada `Get-Item` e uma expressao independente. O binder nao pode confundir os proximos tokens com uma segunda ocorrencia de `-LiteralPath` do mesmo comando.

## Regressao obrigatoria

O gate agora valida tanto o build normal quanto o build `-IfNeeded` no processo externo real do Windows PowerShell 5.1 e exige que o hash do EXE permaneca igual no segundo passo.
