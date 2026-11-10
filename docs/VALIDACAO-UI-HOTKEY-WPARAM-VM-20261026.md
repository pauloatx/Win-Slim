# UI-HOTKEY-WPARAM-001 — validação visual na VM

**26/10/2026, America/Sao_Paulo, aproximadamente 22:37–22:46. Resultado: aprovado no escopo abaixo; ocorrência encerrada.** Codex realizou a interação com a aplicação completa e inspecionou diretamente as capturas reais do VirtualBox. Revisão posterior de código/logs pelo Nemotron 3 Ultra permanece uma etapa separada, não executada aqui.

## Identidade e preparação

VM `teste win-slim-win11`, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`. Estado inicial efetivamente consultado: **poweroff**, snapshot atual `WINSLIM_BASELINE`, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`. Nenhum snapshot foi restaurado antes de inspecionar o convidado. Não existiam raízes `C:\WinSlim`/`C:\WinSlim-Integracao` com dados pendentes; desktops inspecionados sem artefatos Win-Slim. A gravação anterior foi comparada por SHA-256 com sua cópia já coletada em 24/10 antes da inicialização.

Gate de 26/10 conferido, sem reexecução: **27/27 IDs distintos e correspondentes ao cadastro atual, todos Passed/exit 0**, com build oficial e self-test WPF incluídos. [Resultado](../logs/regressao-20261026-202917-579-72e70a75/resultado.json). Nenhum fonte de produção, teste, política de segurança ou executável foi alterado nesta etapa.

EXE no host, no staging e na VM: SHA-256 **`9479C20C1569C98AC8D042D795CAD0285048D2A9157D5B0DB20FAC9AEB96524E`**. A cópia nova em `C:\WinSlim\Testes\hotkey-r3284-fab8e664` contém **89 arquivos da revisão atual**, incluindo toda a árvore Native R3_2_84, XAML, catálogos, presets, Core, Providers, backend e EXE/config. Todos conferidos no convidado antes da abertura e novamente ao final, com zero divergências. A transferência ZIP foi apenas operacional interna, sem publicação de candidata. A UI carregou **230 ajustes / 15 categorias**; a seleção inicial Balanceado de 103 itens não foi aplicada.

## Testes e resultados

Seis instâncias abertas na sessão interativa 1 de `vboxuser`, sem RunAs/UAC. O fechamento por UI Automation usou o **WindowPattern.Close da janela principal real**; Alt+F4 foi enviado pelo teclado virtual da VM.

| Ciclo | Cenário e fechamento | Resultado |
| --- | --- | --- |
| 1 | Início, UI Automation | Processo encerrou, desktop sem diálogo; exit code não capturado |
| 2 | Benchmark, atalho real, abrir/cancelar editor; Alt+F4 | Processo ausente após fechamento; desktop sem diálogo |
| 3 | Personalizado com catálogo carregado; UI Automation | Encerrou, exit 0; desktop sem diálogo |
| 4 | Início ainda carregando; Alt+F4 | Processo ausente após fechamento; desktop sem diálogo |
| 5 | Benchmark sem coleta; UI Automation | Encerrou, exit 0; desktop sem diálogo |
| 6 | Início ainda carregando; Alt+F4 | Processo ausente após fechamento; desktop sem diálogo |

Atalho provisionado somente na configuração da cópia descartável: `Ctrl+Alt+F9`, comando Mostrar overlay. Teclado virtual real: **OFF → ON → OFF**; abertura do editor e **Cancelar**; novo acionamento **ON**, depois retorno a **OFF**. O monitor permaneceu parado, nenhum jogo/benchmark/coletor/ETW iniciado. O arquivo `benchmark-hotkeys.json` manteve o hash `C2340029460BBA1099A3B4FC2171149B34032F9A2E4C7700FF1EB3F2390B9901`. O cancelamento foi acionado pelo controle `SettingsCancel` da janela proprietária, sem Salvar.

**Nenhum diálogo de estouro ou erro inesperado observado.** As 17 capturas foram inspecionadas diretamente, incluindo antes/depois dos fechamentos, atalho e cancelamento. O log novo `ui-native-r3.2.84.log` não contém `OverflowException`, `BenchmarkHotkeys.Hook`, erro `BenchmarkHotkey` ou exceção; registra apenas Performance, Selection e CustomWarmup. Nenhum evento Application 1000/1001/1026 referente a WinSlim encontrado na janela consultada. Nenhum processo WinSlim remanescente ao final.

Não há log dedicado para cada tecla; a evidência do despacho válido é a alteração observada do controle após o teclado virtual, documentada também por UI Automation. A ausência de erros é circunscrita às execuções acima; não identifica retroativamente o par msg/wParam da ocorrência de 24/10.

## Preservação e encerramento da VM

Evidências em [logs/hotkey-vm-20261026-013704-fab8e664](../logs/hotkey-vm-20261026-013704-fab8e664/):

- `candidate-manifest.json`, `guest-staging-verification.json`, `guest-final-checks.json`: 89 arquivos e hash do EXE, antes/depois.
- `cycle-01-uia.json` a `cycle-06-after-normal.json`, `hotkey-*.json`, `settings-cancel-result.json`, `catalog-ready.json`, `procedure.json`: operações e resultados.
- `01-boot.png` a `17-after-normal-close.png`, `visual-review.json`: capturas reais e observações do Codex.
- `collection/`: log novo, configuração isolada e estados Edge antes/depois; **quatro arquivos copiados e conferidos individualmente por SHA-256 antes de desligar/restaurar**, inventário e recibo adjacentes.
- `vm-session-recording.webm` e `recording-receipt.json`: gravação preservada e conferida por hash antes da restauração; não foi analisada quadro a quadro.
- `vm-before.txt`, `vm-after-shutdown.txt`, `vm-after-baseline.txt`, `baseline-disk-info.txt`, `baseline-restore-receipt.json`: estado efetivo inicial/final e vínculo de disco.

**Edge preservado:** estados HKLM/HKCU, Registry64/Registry32, iguais antes/depois. Nenhum Apply/Undo, nenhuma escrita de política, nenhum backup criado; não se repetiu o aceite EDGE-006/007 nem os demais lotes.

**Proteção observada:** a baseline contém **Windows Defender**, com serviço, antivírus e proteção em tempo real ativos antes/depois; não há Kaspersky instalado nesse convidado. Isso corrige a suposição do handoff, sem instalar, desativar ou reconfigurar antivírus. Não houve nova varredura Kaspersky ou declaração sobre resolução do incidente histórico.

Após a coleta, foi solicitado desligamento normal por ACPI, confirmado **poweroff**, sem desligamento forçado. Snapshot restaurado: **WINSLIM_BASELINE**. Confirmação final: snapshot UUID correto e novo disco diferencial `640addcd-0d67-408f-b62c-468eeaeb463a`, parent `d8a1bd3b-6fa4-40d2-94ae-83460803b0bc`, igual à imagem de disco do snapshot. A saída de progresso do restore no stderr interrompeu sua captura PowerShell; não se atribui exit code ao comando. A restauração foi confirmada em consulta posterior pelo estado/snapshot e pela nova cadeia do disco, sem repetir o restore.

**Estado final: VM desligada, baseline restaurada, evidências preservadas no host.** Sem repetição do gate, recompilação ou publicação. Incidente AV histórico e famílias retidas permanecem com sua disposição anterior; CI hospedada, multimonitor físico e aprovação de produção não são abrangidos por este aceite.
