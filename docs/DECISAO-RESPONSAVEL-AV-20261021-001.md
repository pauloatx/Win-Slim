# AV-20261021-001 — avaliação e autorização do responsável pelo projeto

22/10/2026. **O responsável pelo projeto considera a detecção um falso positivo.** Trata-se de avaliação do usuário, não de conclusão do Kaspersky ou de veredito independente sobre a amostra original.

## Evidências confirmadas com o responsável

O usuário declarou: “erro no banco de dados atualizei e rodei o teste e passou”. Em seguida confirmou o alcance: “Autorizar compilação e execução local controladas dos auxiliares e retomada do gate completo, sem liberar produção.”

| Informação | Origem / alcance |
| --- | --- |
| Atualização das bases e teste posterior aprovado | Relato explícito do responsável. Nome/data/log do teste, versão das bases e hash do objeto retestado não foram informados |
| Erro no banco de dados como causa | Avaliação do responsável; causa interna não confirmada independentemente |
| Origem local de teste, fontes e dependências | Revisões estáticas e relatórios anteriores preservados; não provam identidade dos bytes originais removidos |
| SHA-256 da primeira amostra | Continua indisponível. Não substituído por hash de recompilação |
| Parecer ou protocolo do Kaspersky | Não fornecido. Não atribuir ao fabricante concordância com a avaliação |

[Registro estruturado](../release/security-owner-assessment-AV-20261021-001.json). [Investigação e limitações anteriores](INCIDENTE-KASPERSKY-R3.2.84.md), [revisão estática](REVISAO-ESTATICA-HARNESS-R3.2.84.md). Permanecem preservados, sem reescrever os fatos históricos.

## Alcance da decisão, antes de revisar a política

Autorizadas **somente compilação/execução local controladas de PresentMonHarness/MonitorHarness e retomada do gate completo**. A autorização do responsável permite revisar a retenção local sem exigir um parecer do fabricante como se ele tivesse sido fornecido. Isso não resolve a identidade da amostra original nem converte ausência de alerta em prova de inocuidade.

**Publicação de pacote do aplicativo e produção permanecem bloqueadas.** Produção continua dependente da validação completa, WPF, CI e aceites físicos restantes. O aceite de contratos/backend Edge permanece concluído; interação pela UI, efeitos condicionais e testes físicos do overlay continuam separados. Leitura física NVIDIA continua pendente por falta de hardware; não instalar driver NVIDIA no host RX 480.

O estado antigo `cleared` libera execução e empacotamento de uma vez. Não representa esta decisão restrita. Será usado um estado explícito de **validação local controlada**, validando resolução, autoridade, escopos autorizados e retenção de publicação/produção. Testes comportamentais precisam demonstrar permissão da ação local inerte, recusa de autorização incompleta/escopo indevido e preservação do bloqueio de pacote antes da ativação da política real.

## Condições operacionais

- Manter antivírus ativo, sem exclusões, alteração de proteção, renomeação para evitar detecção ou restauração automática de quarentena.
- Usar fontes atuais identificadas, registrar compilador/fontes/hash de cada novo artefato antes de executá-lo. Artefato novo não representa a amostra original desconhecida.
- Gate novo, sem importar resultados históricos/parciais. Interromper a rodada controlada na primeira falha, preservar evidências e corrigir/verificar o componente afetado antes de nova rodada. Nova detecção exige parar a execução afetada e registrar o evento, sem repetir sob outro nome.
- Nenhum ajuste real no computador principal; manter fixtures e self-test WPF. Testes reais de políticas Edge continuam exclusivos da VM e sem repetir lotes já aprovados sem regressão relacionada.

A consulta somente leitura `avp.com STATUS` desta rodada retornou código 0, com `Protection`, `SW2` e `File_Monitoring` em execução. [Registro](../logs/av-owner-review-20261022/antivirus-status-before.log). Isso demonstra estado das tarefas nesse instante; não comprova a versão das bases nem o teste relatado pelo usuário. Nenhum comando de configuração do antivírus foi emitido.

## Resultado posterior à autorização

A atualização relatada foi parcialmente corroborada pelo relatório local: tarefa concluída às 05:34:16. Entretanto, na tentativa autorizada às **06:58:39**, o Kaspersky voltou a detectar o novo auxiliar e negou sua execução. O gate parou e a autorização operacional foi suspensa, conforme sua condição de parada. **A avaliação do responsável continua registrada como tal**; a recorrência é evidência nova separada. [Relatório e SHA-256 desta nova compilação](AV-RECORRENCIA-20261022-R3.2.84.md). Sem nova tentativa, exclusão ou restauração de quarentena; produção permanece bloqueada.
