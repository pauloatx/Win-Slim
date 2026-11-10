# FASE 7 R3.2.5 — PS5.1 Logging Hotfix

## Falha isolada
R3.2.4 compilava o host WPF e gerava o EXE, mas o build falhava após o `csc.exe` devido à resolução de overload de `File.AppendAllLines` no Windows PowerShell 5.1.

## Decisão
Não alterar C#, XAML funcional, bridge, Planner, Transaction ou PresetRuntime para corrigir uma falha de infraestrutura de logging.

O logger passa a serializar blocos como `string` e usa `WriteAllText` / `AppendAllText`, cujas assinaturas são inequívocas para PS5.1.

## Sequência de build
1. validar fontes;
2. resolver referências explícitas;
3. criar `.rsp` sem `/noconfig`;
4. invocar `csc.exe /noconfig @response-file`;
5. registrar saída e `ExitCode` com `AppendAllText`;
6. exigir `ExitCode == 0` e EXE presente;
7. copiar `.config`;
8. verificar `.config`;
9. retornar 0.

## Não regressão
O gate R3.2.5 congela R3.2.4, valida 230 tweaks, presets 105/129/168, 16 overlays, read-only, bridge real, build real e self-test real.
