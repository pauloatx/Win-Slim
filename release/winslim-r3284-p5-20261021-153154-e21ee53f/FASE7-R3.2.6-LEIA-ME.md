# Win-Slim Suite — FASE 7 R3.2.6

## Objetivo

Hotfix estritamente focado no caminho `-IfNeeded` usado pelo launcher da Native UI.

A R3.2.5 ja compilava, passava self-test e tinha gate aprovado, mas ao abrir `Executar-WinSlim-R3.2.5.bat` o build era chamado novamente com `-IfNeeded` e o Windows PowerShell 5.1 podia interpretar a lista de `Get-Item` do freshness-check como um unico comando com `-LiteralPath` repetido.

## Correcao

A coleta dos arquivos que participam do freshness-check agora e feita com `ArrayList` e chamadas `Get-Item` isoladas/parentetizadas. Nao ha comandos separados por virgulas dentro de `@(...)`.

O gate R3.2.6 testa o fluxo real usado pelo launcher:

1. build completo;
2. build novamente com `-IfNeeded`;
3. confirma exit code 0;
4. confirma que o EXE nao e recompilado quando esta atualizado;
5. confirma que o `.config` permanece presente;
6. confirma log `Mode: IfNeeded / up-to-date` + `ExitCode: 0`;
7. executa self-test do EXE com XAML real + bridge real.

## Teste

```powershell
cd "D:\Desktop\winslim_fase7_r3_2_6"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.6-NativeUI.ps1
```

Resultado esperado:

```text
FASE 7 R3.2.6 APROVADA
```

Depois:

```text
Executar-WinSlim-R3.2.6.bat
```

## Escopo protegido

Esta revisao nao altera Planner, Transaction, Preview, Providers, catalogos ou a semantica dos presets. A Native UI continua sem mutacao direta do Windows.
