# FASE 7 R3.2 — Native UI Architecture

## Boundary
A apresentação deixa de ser executada por callbacks PowerShell/WPF e passa para C# WPF. O backend PowerShell aprovado continua sendo a fonte de verdade.

```text
WinSlim.UI.Native.R3.2.exe
        |
        | async JSON lines (stdin/stdout)
        v
WinSlim.UiBridge.R3_2.ps1   [persistent, read-only]
        |
        +--> RuntimePromotion
        +--> PresetRuntime
        +--> SystemContextView R2
        +--> PresetOverlayView R3
        |
        X  no Planner/Preview/Transaction/Provider mutation in R3.2
```

## UI thread
O thread WPF nunca aguarda `ReadLine` de forma síncrona. `BridgeClient` serializa requests com `SemaphoreSlim` e usa I/O assíncrono. A atualização do controle retorna ao Dispatcher automaticamente pelo SynchronizationContext da chamada de UI.

## Bridge lifetime
Um processo `powershell.exe -NoProfile -NonInteractive` é iniciado por sessão e carrega o runtime apenas uma vez. Isso evita custos de startup por interação e elimina dependência de dynamic scope dos eventos WPF.

## Animation budget
- page transition: 160–170 ms;
- initial window fade: 190 ms;
- sem animações infinitas;
- sem timers de frame;
- sem blur/acrylic contínuo;
- `AllowsTransparency=False` para manter composição acelerada.

## Metrics budget
`DispatcherTimer` de 3 s. A chamada é suprimida se:
- a janela estiver minimizada;
- a página atual não for Dashboard;
- uma coleta anterior ainda estiver em andamento.

## Privilege model
R3.2 executa `asInvoker`. A interface não deve permanecer elevada durante o uso comum. Quando Apply for conectado em R6, a elevação deverá ocorrer no worker transacional/ação privilegiada, não no shell visual.

## Failure isolation
- falha de bridge não encerra a janela; a UI permanece em modo visual;
- falhas são registradas em `logs/ui-native-r3.2.log`;
- crash do backend não contamina o processo WPF;
- encerramento da janela termina o bridge.

## Compatibility
- Windows 10 / 11;
- Windows PowerShell 5.1 backend;
- .NET Framework 4.8;
- Per-Monitor V2 DPI quando suportado;
- sem dependências externas/NuGet nesta revisão.
