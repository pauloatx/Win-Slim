# Aceite EDGE-006/007 pela interface — 24/10/2026

**Fluxo EDGE-006/007 concluído e observado na VM autorizada.** Seleção/dependência, cancelamento sem escrita, Apply com backup/Verify e Undo exato foram exercitados pela interface da candidata. Há uma ocorrência separada de UI Automation no hook de atalhos, ainda sem correção. Publicação e produção permanecem pendentes.

## Ambiente e integridade

- VM: `teste win-slim-win11`, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`; computador convidado `TESTE`, VirtualBox, Edge **155.0.4283.62**.
- Executável: `bin/WinSlim.UI.Native.R3.2.84.exe`; SHA-256 **8B3ADD130E0F916B38C58F7E4B9E1FF15EB57F6453EC8C0B3B7747D4CE1E7AEF**. Na VM: `C:\WinSlim\Testes\edge-ui-r3284\WinSlim.UI.Native.R3.2.84.exe`.
- Os **87 arquivos** do manifesto de preparação v2 conferiram no início e no fim. Interface carregada, catálogo **230 ajustes**, categoria Microsoft Edge **31 itens**.
- A captura anterior `05-app-sozinha-catalogo-ok.png` foi inspecionada. O log original preserva a falha de XAML e a falha de pipe anteriores; a estrutura v2 contém XAML, catálogos, presets e backend. Não houve recompilação ou alteração de produto nesta rodada.
- Gate anterior **26/26 + WPF** preservado, sem repetição. Os 31 aceites de backend Edge e os aceites anteriores de overlay/P9/Cities.exe permanecem preservados.

## Execução observada

| Etapa | Resultado | Evidência na coleção nova |
| --- | --- | --- |
| Sem administrador | Seleção de 007 gerou uma dependência; ambos bloqueados por `RequiresAdmin`. Políticas e backups intactos | `12-preview-noadmin-details.json/png`, `noadmin-preserved.json` |
| Elevação | Candidata reaberta pelo UAC normal, aprovado pelo responsável nesta conversa; dashboard mostrou administrador | `18-altf4.png` |
| Seleção | Preset de aceite importado pela UI com somente 007; item desmarcado/selecionado; detalhes e retorno preservaram seleção e filtro | `aceite-edge007.json`, `22-selected007.png`, `23-deselected.png`, `25-details007-ready.png`, `26-selection-preserved-after-details.png` |
| Notas | 014/015: depreciação e limite até Edge 155; 018: OptionalData e redundância com 031; 021: conta Entra corporativa | `notes-EDGE-014/015/018/021.png` |
| Plano | Um selecionado + uma dependência; ordem **006 → 007**, dois aptos, zero bloqueados, risco baixo | `29-preview-plan.json`, `34-preview-reopened.json`, `reopened-plan-verified.json` |
| Cancelamento | Revisão abandonada por Voltar à prévia e Voltar ao Personalizado. Nenhuma política ou backup criado; seleção preservada. Reabertura com o mesmo fingerprint | `32-review-before-cancel.png`, `33-cancel-selection-preserved.png`, `35-review-reopened.png`, `cancel-preserved.json` |
| Apply | Botão **Criar backup e aplicar** acionado uma única vez. Dois `AppliedVerified`, zero excluídos/erros | `36-apply-requested.png`, `state-after-apply.json`, diário do backup |
| Navegador | Instância própria com perfil separado. Ambas reconhecidas como **true / Plataforma / Dispositivo / Obrigatório / OK** | `collection-final/logs/applied-edge-policy.png` |
| Undo | **Restaurar tudo** no backup desta execução; confirmação informou ID, dois ajustes e duas operações; UI informou restauração concluída e verificada | `38-backups-ui.png`, `39-undo-review.png`, `40-undo-result.png`, `41-after-undo-backups.png` |
| Exatidão | Comparação antes/depois de HKLM/HKCU, Registry64/Registry32: presença das chaves, nomes/tipos/dados dos valores e nomes de subchaves iguais. Os dois valores voltaram à **ausência**, sem DWORD 0 residual | `state-before.json`, `state-after-undo.json`, `undo-exact.json` |
| Navegador restaurado | Edge reaberto após Undo: **Nenhuma política definida** | `collection-final/logs/restored-edge-policy.png` |

Destinos únicos da aplicação: `HKLM\SOFTWARE\Policies\Microsoft\Edge\SleepingTabsEnabled` e `AutoDiscardSleepingTabsEnabled`, ambos `DWord = 1`. Nenhum outro ID foi aplicado.

Backup original: **`8a696ea46c5440f2bf4c39db0e4a8056`**. SHA-256 do snapshot: `6D611412A3235D3B398FC9765123B14CE614A426F372FB55AC26186CDB94262E`, conferido com o manifesto. Duas capturas, zero exclusões, ambos os valores originalmente ausentes. Snapshot criado antes do início do diário de escrita. O código de produção inspecionado salva/verifica o backup antes da transação; o diário registra escrita/Verify de 006, escrita/Verify de 007 e conclusão.

Backup anterior ao Undo: **`c1e42de4ee1246238d5b26f35843cea7`**, também conferido por manifesto; preserva os dois DWORD 1 aplicados. Diário de restauração registra `Started → Writing → Writing → Completed`, duas operações, vinculadas ao backup original.

## Coleta e baseline

Diretório no host: [logs/edge-ui-aceite-20261024](../logs/edge-ui-aceite-20261024). A coleção anterior [edge-ui-aceite-20261023](../logs/edge-ui-aceite-20261023) permaneceu preservada.

**22 arquivos** de logs/backups da coleta final foram comparados individualmente com os hashes calculados na VM **antes da restauração da baseline**. Capturas da UI, estados do Registro, planos copiados do relatório da UI e auxiliares de operação estão na raiz da coleção nova. [Recibo da coleta](../logs/edge-ui-aceite-20261024/collection-final/receipt.json).

`verify-evidence.ps1` executou **144 conferências de evidência**, todas aprovadas, incluindo integridade, cobertura dos backups, estados, sequência dos diários e ausência de processos de aceite ao final. Isso é validação da evidência desta execução, **não nova execução do gate nem nova suíte de regressão do produto**. [Resultado detalhado](../logs/edge-ui-aceite-20261024/acceptance-verification.json).

Aplicativo fechado normalmente; navegador de teste encerrado somente pelo seu próprio endpoint. VM desligada via ACPI; gravação de **44.064.693 bytes** copiada e conferida no host como `vm-session-recording.webm`, SHA-256 `86B3CA295081275787852BA956FB909BE8BB259FE987FE89D0D299F5D2BA0107`.

Baseline **WINSLIM_BASELINE**, snapshot `4aa21603-c0b4-4139-9630-1e5d0acaef20`, restaurada; VM **desligada**, `CurrentStateModified=0`. Confirmado que o pai do novo disco é o disco da baseline. O progresso de restauração em stderr interrompeu o wrapper PowerShell após 100%; a operação não foi repetida. O estado final foi conferido separadamente por COM e `showvminfo`. [Recibo](../logs/edge-ui-aceite-20261024/baseline-restore-receipt.json), [prova do disco](../logs/edge-ui-aceite-20261024/baseline-disk-proof.json).

## Limites e ocorrência separada

- **UI-HOTKEY-WPARAM-001, pendente:** tentativa de fechamento por UI Automation produziu `OverflowException` em `BenchmarkHotkeys.Hook`. Diálogos foram dispensados e a instância anterior fechada por entrada física virtual; o fluxo elevado foi concluído com mouse/teclado virtuais. Não houve nova exceção registrada nesse trecho. [Ocorrência e próximo teste](OCORRENCIA-UI-HOTKEY-WPARAM-20261024.md). O aceite deste fluxo não aprova UI Automation nem corrige essa falha.
- A consulta DOM do navegador retornou metadados, mas texto/linhas vazios. O reconhecimento e a restauração das políticas foram **conferidos visualmente nas capturas reais**, sem atribuir validação estruturada ao JSON vazio. A primeira abertura do perfil ficou em Nova guia; a captura válida foi feita após navegação explícita para `edge://policy`.
- A resolução inicial da VM cortava o cabeçalho da janela; foi ajustada para obter a revisão completa em tela. A baseline foi restaurada ao final.
- Reconhecimento de políticas não demonstra descarte após 1,5 dia, economia adicional de memória, efeitos de conta/rede ou funcionamento sob todas as condições de perfil. Não houve aceite novo de efeitos condicionais 018/021, execução acima de Edge 155 para 014/015, teste físico multimonitor ou hardware NVIDIA.
- Nenhuma otimização foi aplicada ao host. `PresentMonHarness`/`MonitorHarness` continuam sem geração/compilação/execução. Incidente histórico AV preservado; CI Windows, publicação e produção permanecem pendentes. Nenhum ZIP de distribuição foi produzido.
