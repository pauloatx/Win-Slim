# Win-Slim Suite — FASE 7 R3.2.2 / Native UI Build Hotfix

## Objetivo
Corrigir exclusivamente a falha restante da R3.2.1 na compilacao do host C# WPF, mantendo intactos o backend aprovado e a R3.2.1 para auditoria.

## Causa encontrada no Windows
O `csc.exe` do .NET Framework carregava referencias padrao pelo `csc.rsp` e o build R3.2.1 tambem adicionava explicitamente `System`, `System.Core`, `System.Xml` e `System.Web.Extensions`. Em algumas instalacoes do .NET Framework isso resultava em duas assemblies com a mesma identidade (Framework/GAC) e no erro `CS1703`.

## Correcao R3.2.2
O build agora usa `/noconfig`, desabilitando a carga automatica do `csc.rsp`, e fornece de forma explicita apenas as referencias resolvidas pelo runtime .NET Framework do Windows PowerShell 5.1. Assim existe uma unica fonte de referencias e o build fica deterministico.

A Native UI continua em C# + WPF e permanece read-only nesta etapa:

`C# WPF Native UI -> bridge PowerShell persistente -> RuntimePromotion / PresetRuntime -> backend aprovado`

Nenhum Planner validation, Preview transacional, Transaction ou Provider de mutacao e chamado pela R3.2.2.

## Validacao no Windows
```powershell
cd "D:\Desktop\winslim_fase7_r3_2_2"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.2.2-NativeUI.ps1
```

O gate deve compilar `bin\WinSlim.UI.Native.R3.2.2.exe`, copiar o `.config`, carregar o XAML pelo runtime WPF real e executar o self-test contra o bridge persistente.

Se houver qualquer falha de compilacao, o diagnostico completo fica em:

`logs\build-native-r3.2.2.log`

Se terminar com `FASE 7 R3.2.2 APROVADA`, execute:

`Executar-WinSlim-R3.2.2.bat`

## Validacao visual
Priorize:
1. abertura sem erro e sem console residual;
2. layout compacto conforme o designer aprovado;
3. 16 overlays interativos, com estado ativo em laranja;
4. cards Equilibrado / Gamer / Extremo;
5. consentimento visual para overlays de risco Alto;
6. transicoes curtas e sem travamento;
7. CPU em idle e com a janela minimizada;
8. escala DPI em 100%, 125% e 150% quando disponivel.
