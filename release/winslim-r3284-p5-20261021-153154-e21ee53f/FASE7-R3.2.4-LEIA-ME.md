# Win-Slim Suite — FASE 7 R3.2.4 / Native UI Gate Reliability Hotfix

## Estado que levou a esta revisão
A R3.2.3 atingiu o objetivo técnico principal: no Windows do usuário o `csc.exe` retornou código 0, o EXE foi gerado, o `.config` foi copiado e o self-test real carregou o XAML e conversou com o bridge/backend 230.

Restaram dois falsos negativos de infraestrutura:

1. o teste que deveria confirmar a passagem direta de argumentos ao `csc.exe` usava uma regex frágil, embora a compilação real tivesse sido concluída com sucesso;
2. em compilação limpa e sem warnings o `csc.exe` não emite saída, então a pipeline antiga não criava `logs\build-native-r3.2.3.log`.

## Correção R3.2.4
- O compilador continua recebendo `/noconfig` diretamente, fora do response file.
- A invocação agora usa array splatting explícito:
  `& $csc @compilerArgs 2>&1`
- O log é criado antes da execução do compilador, portanto existe mesmo quando o build é silencioso.
- O log registra `Invocation`, `ReferenceCount`, `SourceCount` e `ExitCode`.
- O caminho `-IfNeeded` também grava um log de auditoria.
- O gate usa uma verificação textual determinística em vez da regex problemática.
- O gate exige log não vazio, `ExitCode: 0` e ausência de `CS2023`/`CS1703`.
- O launcher aponta para `logs\build-native-r3.2.4.log`.

## Arquitetura preservada

`C# WPF Native UI -> bridge PowerShell persistente -> RuntimePromotion / PresetRuntime -> backend aprovado`

Esta revisão continua read-only. Não chama Planner validation, Preview transacional, Transaction nem Provider de mutação.

## Validação no Windows
```powershell
cd "D:\Desktop\winslim_fase7_r3_2_4"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.4-NativeUI.ps1
```

Resultado esperado:
`FASE 7 R3.2.4 APROVADA`

Depois:
`Executar-WinSlim-R3.2.4.bat`

## Validação visual
Após o gate verde, validar a janela real contra o contrato visual oficial: Presets, overlays interativos, transições curtas, comportamento em DPI, resize, idle e minimização.

Não avançar para R4 antes desta fundação ficar verde e estável no Windows real.
