# Handoff Codex — UI-HOTKEY-WPARAM-001 / validação visual na VM

> **Atualização final de 26/10/2026: roteiro concluído pelo Codex, validação visual aprovada e ocorrência encerrada.** Três fechamentos WindowPattern.Close e três Alt+F4, atalho real e cancelamento validados, sem diálogos/OverflowException. VM desligada e WINSLIM_BASELINE restaurada após coleta conferida. [Relatório](VALIDACAO-UI-HOTKEY-WPARAM-VM-20261026.md) e [resultado](../logs/hotkey-vm-20261026-013704-fab8e664/validation-results.json). A baseline possui Defender ativo, sem Kaspersky instalado. Revisão textual posterior pelo Nemotron 3 Ultra permanece pendente. As seções abaixo conservam o handoff anterior à execução; seu roteiro não deve ser repetido sem regressão relacionada.

26/10/2026, America/Sao_Paulo. Divisão de trabalho vigente: a rodada anterior (GLM) executou implementação, correção, regressão comportamental, gate técnico e atualização dos registros usando código, comandos, logs e dados estruturados. A **validação visual e a interação visual na VM são atribuição do Codex**; não interpretar imagens ou capturas antes dessa etapa. Depois da validação do Codex, a revisão de código, logs e resultados em texto será feita pelo Nemotron 3 Ultra.

Não reiniciar a implementação nem repetir o gate técnico sem mudança relevante: a correção já foi aplicada, a regressão nova passou e o gate completo atual foi aprovado. O escopo desta rodada foi a correção do Hook; não houve expansão de funções nem alteração visual.

## 1. Objetivo e causa confirmada (com limites da conclusão)

**Objetivo:** corrigir `UI-HOTKEY-WPARAM-001` — `System.OverflowException` registrado em `WinSlim.NativeUI.BenchmarkHotkeys.Hook` durante fechamento por `WindowPattern.Close` de UI Automation (aceite Edge UI de 24/10, na VM, candidata `8B3ADD130E0F916B38C58F7E4B9E1FF15EB57F6453EC8C0B3B7747D4CE1E7AEF`) — criar regressão comportamental, validar a candidata alterada e transferir a etapa visual.

**Causa confirmada no código:** o Hook original executava `wp.ToInt32()` **antes** de testar `msg == 0x312` (WM_HOTKEY). Em processo x64, `IntPtr.ToInt32()` lança `OverflowException` quando o valor não cabe em `Int32`, inclusive para mensagens alheias a atalhos que trafegam pelo hook durante automação/fechamento de janela.

**Limites:** a pilha histórica não registrou a mensagem nem o wParam exatos, e o log não foi instrumentado para isso. A regressão reproduz o defeito de estreitamento do código anterior; **não identifica retroativamente** o par `msg`/`wParam` da ocorrência original. Não afirmar reprodução do evento original sem evidência.

## 2. Arquivos alterados nesta rodada

- `src/UI/Native/R3_2_84/BenchmarkSettings.cs` — somente o corpo do método `Hook` (filtro de mensagem + leitura segura do ID). Nenhum outro membro, layout, contrato de backup/Apply/Verify/Undo ou backend foi alterado.
- `tests/fixtures/HotkeyWParamFixture.cs` (novo) — fixture DLL-only, sem `Main`, sem qualquer fonte retida e sem geradores/executáveis coletores; usa o Hook privado real de produção via delegate `HwndSourceHook`.
- `tests/Test-Fase7-R3.2.84-HotkeyWParam.ps1` (novo) — runner da regressão comportamental `REG-HOTKEY-001` (compila produção + fixture em DLL, x64, HWND WPF em thread STA).
- `tests/regression/cases.json` — acréscimo único de `REG-HOTKEY-001`; contagem real derivada: **27 casos**.
- `release/review.json` — `activeFiles` estendido a 41 entradas (fixture/runner incluídos); `requiredIds` com `REG-HOTKEY-001`.
- `release/security-incidents.json` — `manifestSHA256` do review atualizado; cadeia preservada e nenhum bloqueio afrouxado.
- `release/escopo-R3.2.84.json` — bloco `hotkeyWParamCorrection` e `requiredWindowsSuites: 27`.
- `specs/FASE7-R3.2.84-baseline.json` — hashes reprocessados após as atualizações legítimas.
- `RETOMADA-R3.2.84-AV.md` e `docs/OCORRENCIA-UI-HOTKEY-WPARAM-20261024.md` — continuidade atualizada distinguindo correção implementada, gate aprovado e validação visual pendente.
- `docs/HANDOFF-CODEX-UI-HOTKEY-WPARAM-20261024.md` — este handoff (substitui o provisório `HANDOFF-CODEX-HOTKEY-R3.2.84-20261026.md`, removido).

## 3. Correção mínima aplicada

Antes (defeito):

```csharp
private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
{
    int index = wp.ToInt32() - 0x5710;
    if (msg == 0x312 && index >= 0 && index < 3) { handled = true; Dispatch(index); }
    return IntPtr.Zero;
}
```

Depois (corrigido):

```csharp
private IntPtr Hook(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
{
    if (msg != 0x312) return IntPtr.Zero;
    long id = wp.ToInt64();
    if (id >= 0x5710 && id <= 0x5712) { handled = true; Dispatch((int)(id - 0x5710)); }
    return IntPtr.Zero;
}
```

Filtro da mensagem antes de interpretar parâmetros específicos de atalhos; ID lido por `ToInt64()` e comparado no intervalo completo `0x5710..0x5712` antes de subtrair/converter. Sem truncamento/`unchecked` e sem captura genérica de exceções. Comportamento preservado: `Dispatch`, estados `Suspended`/`Capture`, `handled` (marcado apenas para WM_HOTKEY reconhecida; mensagens alheias mantêm o valor recebido), `Apply`/rollback e `Dispose`.

A fixture `tests/fixtures/HotkeyWParamFixture.cs` e o runner `tests/Test-Fase7-R3.2.84-HotkeyWParam.ps1` são DLL-only, sem `Main` e sem qualquer fonte retida: compilam a produção real + fixture em DLL x64, vinculam o Hook privado via delegate `HwndSourceHook`, criam HWND WPF em thread STA dedicada e entregam mensagens por `SendMessage` nativo antes e depois do `Dispose`. Matriz coberta: mensagens alheias (inclusive WM_CLOSE/WM_GETOBJECT) com wParam zero, de largura nativa 64 bits e extremos; WM_HOTKEY com IDs válidos (despacho do índice exato), desconhecidos, negativos, extremos e alias com bit alto; `handled` preservado para mensagens ignoradas; combinações `Suspended`/`Capture`; HWND/lParam nulos; `Apply` inválido/nulo/duplicado e falha simulada de registro com restauração de bindings/registrações anteriores; arquivo de configuração preservado em raiz isolada. Nenhum atalho global não vazio registrado, nenhuma otimização aplicada ao host do desenvolvedor.

## 4. Regressão antes/depois e resultados

| Verificação | Resultado / evidência |
| --- | --- |
| Regressão **antes** da correção | **48/113 checks falharam com `System.OverflowException`**, exit 1; `logs/hotkey-wparam-7c16f43b20474aa4ab69a6f3240eb700/` |
| Regressão **depois** da correção | **113/113 checks passaram**, exit 0; `logs/hotkey-wparam-0bd4346141874881b3fe1a06dc9600fd/` (execução repetida confirmada em `logs/hotkey-wparam-841b019d3841488eb5d9093009a05768/`) |
| Suíte diretamente afetada | `tests/Test-Fase7-R3.2.84-BenchmarkOverlay.ps1` (usa `BenchmarkSettings.cs`) — aprovada dentro do gate |
| Gate completo atual | `Iniciar-Validacao.bat /ci`, exit 0; **27/27 casos distintos, completos e da mesma execução**; `logs/regressao-20261026-202917-579-72e70a75/resultado.json` |
| Resumo da candidata | `logs/candidato-r3284-20261026-202917-242-57c45b78/summary.json`; `TechnicalPassed=true`, `ProductionApproved=false` |
| Build oficial + self-test WPF | `Build-NativeUI-R3.2.84.ps1` e self-test WPF aprovados dentro de `REG-UI-001` no gate; log `logs/build-native-r3.2.84.log` registra `ExitCode: 0` e `BuildPublished: true` |
| Testes do empacotador | `python -m unittest discover -s tests -p test_package_release.py`: 22 testes passaram; validação final de cadastro único/scripts/hashes: 27 casos, 232 hashes OK |

A contagem de 27 suítes é derivada do cadastro real (`tests/regression/cases.json`), não fixada artificialmente. Os resultados históricos 26/26 da candidata `8B3ADD13...` **não** aprovam o novo executável; o gate acima foi executado após a correção, sobre a build atual.

## 5. Nova build: caminho e hash

- **Executável:** `bin/WinSlim.UI.Native.R3.2.84.exe`
- **SHA-256:** `9479c20c1569c98ac8d042d795cad0285048d2a9157d5b0db20fac9aeb96524e`
- Candidata anterior (substituída, histórica): `8B3ADD130E0F916B38C58F7E4B9E1FF15EB57F6453EC8C0B3B7747D4CE1E7AEF`
- Config: `bin/WinSlim.UI.Native.R3.2.84.exe.config` (copiado pelo build oficial após compilação válida)
- Proveniência e cópia dos arquivos antes da rodada: `logs/hotkey-fix-20261026/verification.json` e `logs/hotkey-fix-20261026/before/`

## 6. Logs e evidências (host)

- `logs/hotkey-wparam-7c16f43b20474aa4ab69a6f3240eb700/` — execução **antes** com 48 falhas `OverflowException` (evidência do defeito no código anterior)
- `logs/hotkey-wparam-0bd4346141874881b3fe1a06dc9600fd/` e `logs/hotkey-wparam-841b019d3841488eb5d9093009a05768/` — execuções **depois** 113/113
- `logs/hotkey-wparam-300f6bf6e56f4854b34296555d70eccf/` — execução intermediária conservada
- `logs/hotkey-wparam-after-console.log` — console pós-correção
- `logs/regressao-20261026-202917-579-72e70a75/` — gate completo 27/27 (resultado.json + stdout/stderr por caso)
- `logs/candidato-r3284-20261026-202917-242-57c45b78/` — resumo técnico da candidata
- `logs/edge-ui-aceite-20261024/` — evidências históricas do aceite Edge UI na VM (preservadas; não reexecutadas nesta rodada)

## 7. Estado atual da VM

- VM **`teste win-slim-win11`**, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`
- Snapshot **`WINSLIM_BASELINE`**, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`
- **Desligada**, com a baseline restaurada desde 24/10. Nenhuma VM foi iniciada nesta rodada de correção; o estado atual não foi inspecionado por esta rodada — **verificar antes de usar**.
- Aceite EDGE-006/007 pela interface concluído em 24/10 permanece válido (evidências em `logs/edge-ui-aceite-20261024`); os 31 aceites de backend Edge e os aceites P4/P7/P9 (inclusive captura real de 30 s no Cities.exe) permanecem preservados. Não repetir Apply/Undo dos contratos Edge sem regressão/mudança relacionada.

## 8. Preparação da cópia interna de teste (obrigatória e completa)

A tentativa anterior de copiar **apenas EXE + CONFIG** causou “XAML da Native UI não encontrado”. Para evitar isso, a cópia de teste dentro da VM deve ser completa e coerente, com a candidata atual:

1. Partir do workspace do host `D:\Desktop\winslim_fase7_r3_2_84` e copiar para a VM a árvore `src\UI\Native\R3_2_84` inteira (todos os `.cs`, os `.xaml` — `WinSlimShell.xaml`, `WinSlimScrollbars.xaml`, `WinSlimTweakDetail.xaml`, `WinSlimCustom.xaml` —, os `.ps1` de backend, `Strings.en.json`, `Theme.palette.json`, `WinSlim.ico`, `WinSlim.NativeUI.manifest`, `WinSlim.UI.Native.exe.config`) **da mesma revisão da build**, mais `bin\WinSlim.UI.Native.R3.2.84.exe` e `bin\WinSlim.UI.Native.R3.2.84.exe.config`.
2. Não misturar arquivos de candidatas antigas (a cópia de 24/10 com o binário `8B3ADD13...` está defasada; descartá-la ou isolá-la em pasta separada de arquivo morto).
3. Manter a estrutura de diretórios original: o executável resolve XAML/backend relativos à raiz (`--root`), então a raiz de trabalho passada ao abrir deve ser a pasta copiada com `src`, `bin`, `config` etc.
4. Antes de abrir, conferir o SHA-256 do EXE copiado: `9479C20C1569C98AC8D042D795CAD0285048D2A9157D5B0DB20FAC9AEB96524E`. Qualquer divergência interrompe a validação.

## 9. Roteiro operacional para o Codex (validação visual na VM)

1. **Conferir integridade da candidata** no host e na cópia da VM: SHA-256 `9479C20C1569C98AC8D042D795CAD0285048D2A9157D5B0DB20FAC9AEB96524E` de `bin\WinSlim.UI.Native.R3.2.84.exe`; gate técnico aprovado em `logs\regressao-20261026-202917-579-72e70a75\resultado.json` (27/27).
2. **Verificar o estado da VM** `teste win-slim-win11` (UUID `b71b4588-2e83-461c-9585-64ee77b9c851`): esperava-se desligada na baseline `WINSLIM_BASELINE` (UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`). Se houver dados novos não preservados (logs, backups, artefatos), copiá-los para o host antes de prosseguir.
3. **Preparar cópia interna de teste completa** conforme a seção 8 (XAML, catálogos e backend necessários, estrutura de diretórios preservada).
4. **Evitar misturar arquivos de candidatas antigas**; usar exclusivamente os arquivos da revisão corrigida.
5. **Abrir na sessão interativa** com raiz/diretório de trabalho corretos: executar `WinSlim.UI.Native.R3.2.84.exe` a partir da raiz copiada (a partir do launcher equivalente ou com `--root` apontando para a raiz da cópia), sessão de usuário não elevado primeiro, como no aceite de 24/10.
6. **Exercitar `WindowPattern.Close` por UI Automation** na janela principal (mesmo padrão da ocorrência) e, em outra execução, o **fechamento normal** (Alt+F4/botão fechar). Repetir o ciclo abrir→fechar algumas vezes.
7. **Conferir visualmente ausência dos diálogos de estouro** (“Operação aritmética resultou em um estouro”) durante e após os fechamentos, e **verificar os novos logs** do aplicativo (ex. `logs\ui-native-r3.2.84.log` da cópia) sem `System.OverflowException` em `BenchmarkHotkeys.Hook`.
8. **Fazer somente o teste de atalhos necessário** para validar a alteração: com atalhos configurados, confirmar que um WM_HOTKEY válido continua despachando (comportamento preservado) e que o fechamento/cancelamento não gera erro; sem expansão de cenários.
9. **Preservar evidências no host antes de restaurar a baseline**: copiar os logs da sessão, diálogos (se houver) e os hashes conferidos para `logs\` do host (ex. `logs\hotkey-vm-<data>\`), confirmando cada arquivo.
10. **Encerrar e confirmar o estado final da VM**: desligar a VM e restaurar/confirmar o snapshot `WINSLIM_BASELINE`; registrar o estado final no retorno.

Restrições que permanecem: Kaspersky ativo na VM; famílias PresentMonHarness/MonitorHarness retidas (sem geração/compilação/execução); incidente histórico AV-20261021-001 documentado e sem resolução do fabricante; publicação e produção pendentes; multimonitor físico e CI Windows hospedada fora do escopo desta validação; capturas de benchmark, quando necessárias, em 30 segundos.

## 10. Prompt pronto para colar no Codex

```
Continue o projeto Win-Slim Suite. Sua etapa é exclusivamente a VALIDAÇÃO VISUAL na VM; a implementação, a correção UI-HOTKEY-WPARAM-001, a regressão REG-HOTKEY-001 e o gate técnico 27/27 já foram concluídos pelo GLM e NÃO devem ser refeitos. Não repita o gate técnico nem alterne código sem falha concreta.

Leia primeiro: docs/HANDOFF-CODEX-UI-HOTKEY-WPARAM-20261024.md (roteiro completo), docs/OCORRENCIA-UI-HOTKEY-WPARAM-20261024.md e RETOMADA-R3.2.84-AV.md.

Candidata corrigida: bin/WinSlim.UI.Native.R3.2.84.exe, SHA-256 9479C20C1569C98AC8D042D795CAD0285048D2A9157D5B0DB20FAC9AEB96524E. Gate: logs/regressao-20261026-202917-579-72e70a75/resultado.json (27/27, exit 0).

Execute na VM "teste win-slim-win11" (UUID b71b4588-2e83-461c-9585-64ee77b9c851), snapshot WINSLIM_BASELINE (UUID 4aa21603-c0b4-4139-9630-1e5d0acaef20), seguindo os 10 passos da seção 9 do handoff:
1) conferir integridade da candidata (hash acima);
2) verificar o estado da VM e preservar quaisquer dados novos no host antes de prosseguir;
3) preparar cópia interna de teste COMPLETA na VM (src\UI\Native\R3_2_84 inteiro: XAML, catálogos, backend .ps1, config, manifest + bin\WinSlim.UI.Native.R3.2.84.exe e .exe.config) — NÃO copiar apenas EXE/CONFIG, que já causou "XAML da Native UI não encontrado";
4) não misturar arquivos de candidatas antigas (a cópia de 24/10 com binário 8B3ADD13... está defasada);
5) abrir na sessão interativa a partir da raiz copiada (diretório de trabalho correto), usuário não elevado primeiro;
6) exercitar WindowPattern.Close por UI Automation na janela principal e também o fechamento normal (Alt+F4/botão), repetindo abrir→fechar;
7) conferir visualmente ausência dos diálogos "Operação aritmética resultou em um estouro" e verificar os logs da sessão sem System.OverflowException em BenchmarkHotkeys.Hook;
8) fazer somente o teste de atalhos necessário para validar a alteração (WM_HOTKEY válido continua despachando; sem expansão de cenários);
9) preservar as evidências no host (logs, capturas, hashes) em logs\hotkey-vm-<data>\ ANTES de restaurar a baseline;
10) desligar a VM, restaurar/confirmar o snapshot WINSLIM_BASELINE e registrar o estado final.

Não repetir Apply/Undo dos contratos Edge, os 31 aceites de backend ou os aceites P4/P7/P9 sem regressão/mudança relacionada. Kaspersky permanece ativo; PresentMonHarness/MonitorHarness permanecem retidos; publicação e produção pendentes; multimonitor físico e CI hospedada fora do escopo. Atualize a ocorrência e a retomada ao final: com a validação visual aprovada, a UI-HOTKEY-WPARAM-001 pode ser encerrada; registre evidências e limites. Depois da sua validação, a revisão de código, logs e resultados em texto será feita pelo Nemotron 3 Ultra.
```