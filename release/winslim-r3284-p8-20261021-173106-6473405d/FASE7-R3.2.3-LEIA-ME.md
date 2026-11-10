# Win-Slim Suite — FASE 7 R3.2.3 / Native UI Build Invocation Hotfix

## Objetivo
Corrigir exclusivamente a forma como `/noconfig` é entregue ao `csc.exe` do .NET Framework, preservando byte-a-byte a R3.2.2 para auditoria e mantendo intactos o backend aprovado e a arquitetura Native UI.

## Causa confirmada no Windows
O log da R3.2.2 mostrou:

`warning CS2023: Ignoring /noconfig option because it was specified in a response file`

Ou seja, a intenção da R3.2.2 estava correta, porém `/noconfig` foi escrito dentro do `.rsp`. O compilador da Microsoft ignora essa opção quando ela vem de um response file. Consequentemente, o `csc.rsp` padrão continuou sendo carregado e voltou a injetar `System`, `System.Core`, `System.Xml` e `System.Web.Extensions`, duplicando as referências explícitas e produzindo `CS1703`.

## Correção R3.2.3
- `/noconfig` saiu do response file.
- O compilador agora é invocado diretamente como:
  `csc.exe /noconfig @winslim-native-r323-....rsp`
- O `.rsp` contém somente opções normais, referências explícitas e arquivos-fonte.
- Mantém referências determinísticas resolvidas pelo .NET Framework carregado no Windows PowerShell 5.1.
- O gate verifica que `/noconfig` não está dentro do `.rsp` e que a invocação direta usa `/noconfig`.
- O gate reprova se o log ainda contiver `CS2023` ou `CS1703`.

A Native UI continua read-only nesta etapa:

`C# WPF Native UI -> bridge PowerShell persistente -> RuntimePromotion / PresetRuntime -> backend aprovado`

Nenhum Planner validation, Preview transacional, Transaction ou Provider de mutação é chamado pela R3.2.3.

## Validação no Windows
```powershell
cd "D:\Desktop\winslim_fase7_r3_2_3"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.3-NativeUI.ps1
```

O gate deve:
1. preservar a baseline FASE 6.5 R4.1;
2. preservar byte-a-byte a R3.2.2;
3. confirmar 230 tweaks e presets 105/129/168;
4. testar o bridge real;
5. compilar `bin\WinSlim.UI.Native.R3.2.3.exe`;
6. confirmar ausência de `CS2023` e `CS1703`;
7. carregar o XAML no WPF real;
8. executar o self-test contra o bridge persistente.

Se aprovado:
`Executar-WinSlim-R3.2.3.bat`

## Observação
A R3.2.3 não muda o designer nem a lógica dos overlays. É um hotfix de toolchain deliberadamente mínimo para estabilizar a fundação C#/WPF antes de avançar a FASE 7.
