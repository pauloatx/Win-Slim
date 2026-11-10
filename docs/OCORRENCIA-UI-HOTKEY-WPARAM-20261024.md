# UI-HOTKEY-WPARAM-001 — ocorrência durante o aceite Edge UI

24/10/2026; atualização em 26/10/2026. **Encerrada: correção, gate técnico e validação visual na VM aprovados em 26/10.** A ocorrência original usava a candidata com SHA-256 `8B3ADD130E0F916B38C58F7E4B9E1FF15EB57F6453EC8C0B3B7747D4CE1E7AEF`, exclusivamente na VM `teste win-slim-win11`.

Durante o fechamento da instância não elevada pelo padrão `WindowPattern.Close` de UI Automation, a interface exibiu erro inesperado: **Operação aritmética resultou em um estouro**. Tentativas de automação subsequentes encontraram a janela com diálogos de erro. O log registra `System.OverflowException` em `WinSlim.NativeUI.BenchmarkHotkeys.Hook`, primeiro em **00:53:57.537**, com recorrências até **00:56:03.255**, horário local do convidado.

Evidências: [captura dos diálogos](../logs/edge-ui-aceite-20261024/14-admin.png), [log original coletado](../logs/edge-ui-aceite-20261024/collection-final/logs/ui-native-r3.2.84.log), [auxiliar da tentativa](../logs/edge-ui-aceite-20261024/ui-functions.ps1). A pilha não registra o número da mensagem nem o valor de `wParam`; não se afirma um par específico desses parâmetros.

A inspeção histórica de 24/10 de [BenchmarkSettings.cs](../src/UI/Native/R3_2_84/BenchmarkSettings.cs) mostrava que `Hook` executava `wp.ToInt32()` **antes** de verificar `msg == 0x312` (WM_HOTKEY). Essa conversão pode lançar exceção para parâmetros nativos de 64 bits em mensagens que nem são atalhos. A associação exata entre cada mensagem da automação e a exceção não foi instrumentada nesta rodada.

Os diálogos foram dispensados por mouse virtual, e a instância anterior foi fechada por Alt+F4. A instância elevada concluiu o fluxo Edge por mouse/teclado virtuais. Não houve Apply antes dessa recuperação; o bloqueio sem administrador e a ausência de mudanças foram documentados. Os aceites físicos anteriores de atalhos/overlay não foram repetidos ou reclassificados.

Os critérios definidos em 24/10 exigiam identificador de regressão em `tests/regression/cases.json` e teste comportamental do hook real com mensagem alheia a WM_HOTKEY e `wParam` de 64 bits, verificando ausência de exceção/despacho e preservação de `handled`, além de atalhos válidos, IDs inválidos/extremos, suspensão/captura, indisponibilidade, demonstração antes da correção e gate completo. Foram atendidos em 26/10 conforme abaixo.

Nenhuma alteração do hook, novo EXE ou expectativa de regressão foi feita na execução de aceite de 24/10. A candidata e os 87 arquivos de preparação permaneceram intactos naquela rodada. Publicação e produção continuam pendentes.

## Correção e evidências de 26/10/2026

`REG-HOTKEY-001`: [fixture](../tests/fixtures/HotkeyWParamFixture.cs) e [runner](../tests/Test-Fase7-R3.2.84-HotkeyWParam.ps1) compilam somente a classe de produção e a fixture em DLL sem Main. O Hook privado é vinculado ao delegate `HwndSourceHook`, sem copiar sua implementação. O teste cria HWND WPF em thread STA e usa SendMessage para comprovar entrega e remoção no Dispose; registros de teclas não vazias são simulados, e o arquivo de configuração fica em diretório isolado.

- **Antes:** [113 checks, 48 falhas por OverflowException, exit 1](../logs/hotkey-wparam-7c16f43b20474aa4ab69a6f3240eb700/result.json); [checks completos](../logs/hotkey-wparam-7c16f43b20474aa4ab69a6f3240eb700/checks.log).
- **Depois:** [113 checks, zero falhas, exit 0](../logs/hotkey-wparam-0bd4346141874881b3fe1a06dc9600fd/result.json), com os mesmos testes/expectativas. Mensagens alheias, handled inicialmente true/false, IDs zero/desconhecidos/negativos/Int64 extremos e aliases com bits altos, três comandos válidos, quatro estados Suspended/Capture, Apply inválido, registro indisponível/rollback e preservação de bytes/IDs.
- **Correção mínima:** retornar para `msg != 0x312` antes de interpretar wParam; ler com `ToInt64()`, comparar o intervalo completo `0x5710..0x5712` e só então subtrair/converter para o índice. Não há truncamento, subtração antes da validação nem captura genérica de exceções.
- **Candidata:** `Iniciar-Validacao.bat /ci`, exit 0, **27/27 suítes** em [resultado completo](../logs/regressao-20261026-202917-579-72e70a75/resultado.json); [resumo](../logs/candidato-r3284-20261026-202917-242-57c45b78/summary.json) com TechnicalPassed=true e ProductionApproved=false. Build oficial e self-test WPF incluídos em REG-UI-001; REG-HOTKEY-001 também passou dentro dessa execução.
- **Empacotador:** 22 testes Python passaram; cadastro, scripts e hashes conferidos por `tools/package_release.py`, sem gerar ZIP de aplicação. O pipeline gerou somente seu diagnóstico habitual.

EXE local validado: `bin/WinSlim.UI.Native.R3.2.84.exe`, SHA-256 **`9479c20c1569c98ac8d042d795cad0285048d2a9157d5b0db20fac9aeb96524e`**. [Identidade e cópias dos logs de build](../logs/hotkey-fix-20261026/verification.json). Fontes, compilador e DLL são identificados em `provenance-before-load.json` de cada execução. A primeira tentativa do runner detectou erro de conversão PSObject/string antes dos checks; ele foi corrigido antes da demonstração válida acima, e a evidência inicial foi conservada.

O encerramento da rodada técnica, anterior à validação visual abaixo, registrou: a reprodução confirma a falha de estreitamento no código anterior. Não identifica retroativamente o par msg/wParam da ocorrência de 24/10. **WindowPattern.Close da aplicação completa na VM não foi repetido**; também não foram repetidos Apply/Undo Edge, os aceites físicos P9 ou multimonitor. Nenhuma VM foi iniciada nesta rodada. CI hospedada permanece pendente, incidente histórico sem resolução do fabricante, famílias retidas bloqueadas, distribuição em hold e produção não aprovada. [Handoff atual](HANDOFF-CODEX-UI-HOTKEY-WPARAM-20261024.md).

## Validação visual e encerramento em 26/10/2026

**Aprovada pelo Codex na VM autorizada:** três ciclos WindowPattern.Close e três Alt+F4, sem diálogos de estouro; Ctrl+Alt+F9 alternou Mostrar overlay e permaneceu funcional após Cancelar no editor. Catálogo completo de 230 ajustes carregado; 89 arquivos e EXE conferidos antes/depois. Logs sem OverflowException/BenchmarkHotkeys.Hook ou erros de atalho; estados Edge idênticos, nenhum Apply/Undo ou backup novo.

[Relatório completo e limites](VALIDACAO-UI-HOTKEY-WPARAM-VM-20261026.md), [resultado estruturado](../logs/hotkey-vm-20261026-013704-fab8e664/validation-results.json). Quatro arquivos do convidado, 17 capturas inspecionadas e gravação preservados/conferidos no host antes da restauração. **VM desligada, WINSLIM_BASELINE restaurada e cadeia do disco confirmada.** A baseline usa Defender ativo, sem Kaspersky instalado; proteção preservada. Código/build/gate 27/27 não foram alterados ou repetidos. Revisão textual posterior pelo Nemotron 3 Ultra pendente; publicação/produção continuam bloqueadas. UI-HOTKEY-WPARAM-001 encerrada no escopo técnico e visual, sem inferir os parâmetros exatos da ocorrência original.
