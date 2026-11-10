# P9 funcional — aceites manuais relatados pelo responsável

23/10/2026, America/Sao_Paulo. Registro de aceites **manuais relatados pelo responsável** nesta rodada de revisão. Sem execução de gate (o aprovado não foi repetido), sem alteração de código, política de segurança, hashes ou resultados de teste. Aceites anteriores preservados sem reclassificação.

## Aceites anteriores preservados

- **P4 (21/10):** comparação de frame time e **cancelar/capturar novamente**. O aceite P4 de cancelamento e nova captura **permanece válido**; não reclassificá-lo como pendente sem regressão demonstrada.
- **P7:** funcionamento do overlay observado sobre o jogo pelo usuário.

## Aceites funcionais relatados pelo responsável (23/10)

1. Troca Pequeno/Médio durante a captura, com métricas atualizando.
2. Mover/Travar, cliques atravessando a área das métricas e controles acessíveis.
3. Persistência de tamanho e posição ao reabrir e selecionar o mesmo jogo.
4. Salvar/Cancelar nas configurações (Save persiste; Cancel reverte).
5. Atalhos configurados.
6. Sensores disponíveis e indicação de indisponibilidade (valor nulo/indisponível é válido; não é falha).
7. Escala do Windows em 100%, 125% e 150%.

## Múltiplos monitores — requisito e estado

- Requisito corrigido: **arraste livre e manutenção do overlay visível**. Seguir automaticamente a janela do jogo **não é requisito**.
- **Validação física entre monitores: não demonstrada** (sem evidência nesta rodada). Permanece pendente, registrada separadamente dos itens acima; a persistência relatada no item 3 foi observada em um monitor.

## Classificação e limites

- Aceite manual relatado pelo responsável; não substitui regressões automatizadas nem o gate aprovado (**26/26 + WPF**, `logs/regressao-20261023-195445-660-664dd0da/resultado.json`), que não foi repetido nesta rodada e não deve ser repetido sem mudança relevante ou divergência de integridade.
- Efeitos condicionais de conta/rede e os itens EDGE-018/EDGE-021 seguem sem aceite.
- Incidente histórico **AV-20261021-001 preservado** (`historicalIncidentResolved=false`); os dois harnesses (`PresentMonHarness.cs`, `MonitorHarness.cs`) permanecem retidos, sem compilação/execução; **produção pendente** (`productionApproved=false`, `distribution: hold`).
