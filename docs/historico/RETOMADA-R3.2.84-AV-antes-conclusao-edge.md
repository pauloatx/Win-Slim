# Retomada R3.2.84 — estado atual único

Atualizado em 21/10/2026. Prioridade: pendências Edge independentes do incidente AV; protótipo do limitador preservado, expansão de SDK/ABI/adaptador pausada. O [inventário completo](docs/ESTADO-CATALOGO-EDGE-R3.2.84.md) contém ID, função, implementação, evidência e pendência para os **31 IDs Edge**.

## Estado atual e próxima ação

| Frente | Estado comprovado | Pendência / próximo passo |
| --- | --- | --- |
| **EDGE-019/020/024/025** | **Lote concluído e preservado, sem repetir testes nesta rodada.** Apply/Verify real elevado, backup verificado, quatro políticas false/OK, Undo à ausência original. 40 arquivos conferidos antes da baseline | Alcance restrito ao backend/Registro e carregamento no navegador; cliques da UI e efeitos externos não foram inferidos. [Aceite preservado](docs/EDGE-VM-ISOLADO-R3.2.84.md) |
| **EDGE-003/004/005/006** | **Próxima pendência executada e concluída nesta rodada no mesmo escopo real.** Quatro AppliedVerified, três false e SleepingTabs true/OK, Undo exato. 41 arquivos conferidos antes da baseline | [Resultado e evidências](docs/EDGE-CATALOGO-PROXIMO-LOTE-R3.2.84.md). Cliques da UI e efeitos dos recursos permanecem fora do aceite |
| Demais seis contratos UI Edge | EDGE-001/002 e EDGE-008/011/012/016 implementados no Apply UI, com 47/155 verificações históricas simuladas; sem evidência real individual localizada | Prioridade seguinte: revisar vigência por versão/perfil de 008/011/012/016 antes do teste real; para 001/002, localizar artefatos dos ciclos citados nos READMEs. Não repetir automaticamente um lote antes aprovado só por lacuna documental |
| Outros 17 IDs Edge | Declarados no catálogo; ainda sem liberação do contrato Apply UI revisado | Revisar políticas, dependências/compatibilidade, completar contratos e regressões, depois aceite real. Provider genérico e declaração Phase7 não aprovam essa implementação |
| **AV-20261021-001** | **investigating; sem conclusão de falso positivo.** PresentMonHarness e MonitorHarness bloqueados para geração/execução; evidências preservadas | Resposta do fabricante e correlação da amostra/hash originais, hoje indisponíveis; [dossiê](docs/INCIDENTE-KASPERSKY-R3.2.84.md), [revisão estática](docs/REVISAO-ESTATICA-HARNESS-R3.2.84.md), [envio manual e lacunas](logs/kaspersky-investigation-20261021/static-review-02/ENVIO-MANUAL.md). Nada enviado automaticamente |
| **Gate completo, distribuição e produção** | **Bloqueados.** Não foi criada candidata/ZIP de aplicativo nesta rodada | Resolução técnica/de segurança documentada, revisão do hold e gate novo de todo o cadastro atual (22 suítes) + self-test WPF. Depois, CI e aceites físicos remanescentes; testes independentes não se somam para aprovar o gate |
| Overlay / UI P9 | Aceite visual do usuário e funcionamento observado sobre o jogo preservados; P4 comparação e cancelar/capturar novamente preservados | Aceites físicos funcionais restantes: foco/cliques/atalhos, estados Salvar/Cancelar, sensores, DPI 100/125/150 e múltiplos monitores. Aplicativo e fontes visuais/estatísticas não foram alterados |
| Limitador por jogo | Protótipo puro preservado, 64 verificações históricas do modelo em memória | Expansão pausada; não implementa limitação física, SDK/ABI/adaptador ou UI. Ainda há trabalho Edge independente; não retomar o limitador por concluir somente um lote |

## Verificações e ambiente desta rodada

- Inventário conferido contra os seis catálogos canônicos, o contrato real e o escopo: **31 IDs únicos, 14 contratos UI, oito IDs com aceite real no escopo descrito, seis outros contratos e 17 declarações sem contrato UI**. Fontes/relatórios e hashes no [inventário estruturado](logs/edge-vm-catalog-20261021/catalog-inventory.json).
- **24 verificações comportamentais do coletor/seleção de lote passaram.** **154 fixtures EdgeBatch passaram na VM**, com Registro simulado; separadas do Apply/Verify/Undo real posterior. Nenhuma execução de EdgePrivacy nem dos auxiliares bloqueados.
- VM TESTE / VirtualBox, Edge 155.0.4283.62, sessão 1 elevada na execução real. Backup 4df087e546404cfe8540cece012338db; recuperação 75266a7f0c774cb6bf95514005350483. Leituras independentes HKLM/HKCU 32/64 idênticas antes/depois. Classificação OK por PNG real; DOM parcial explicitamente limitado.
- Evidências da nova rodada: `logs/edge-vm-catalog-20261021/collection-224614614/`. Após coleta/verificação dos 41 arquivos e Undo, desligamento normal ACPI e restauração de WINSLIM_BASELINE; estado final poweroff. Edge do host não foi configurado/aberto pelos roteiros.
- Nenhuma exclusão AV, restauração de quarentena, contorno de UAC ou renomeação do auxiliar para evitar alerta. Política de segurança preservada; gate não executado e produção não aprovada.
- Conferência final: **323 arquivos das quatro coleções anteriores e 21 arquivos protegidos P9 intactos por SHA-256**; protótipo e política de segurança também preservados. Sintaxe PowerShell 5.1 dos quatro scripts alterados aprovada. Validação somente de cadastro/scripts/hashes pelo empacotador: **22 suítes únicas, 180 hashes**; não é execução do gate nem empacotamento. [Resumo verificável](logs/edge-vm-catalog-20261021/verification-summary.json).

## Critérios para retomar o gate

1. Preservar protocolo/resposta do fabricante, identidade da detecção e alcance da análise. Fontes ou outra compilação não identificam automaticamente a amostra original desconhecida.
2. Correlacionar amostra/hash originais ou resolver/documentar com o fabricante a ausência e o artefato efetivamente analisado. Sem resposta conclusiva aplicável, manter o bloqueio.
3. Registrar resolução técnica/de segurança e correções justificadas com regressões. Só então revisar o estado investigating; resposta recebida não libera automaticamente o componente.
4. Após revisão do bloqueio, gerar rastreabilidade antes de qualquer execução autorizada e executar o gate completo fresco + WPF. Falhas/parcialidade impedem empacotamento. CI e aceites físicos ainda condicionam produção. Não reutilizar P9 nem somar fixtures.

## Histórico preservado — não representa o estado atual

- [Retomada AV integral anterior a este levantamento](docs/historico/RETOMADA-R3.2.84-AV-antes-catalogo-edge.md): investigação, revisão estática, protótipo, elevação/primeiro lote Edge e testes antigos. Expressões antigas “Edge pendente” ou “próximo SDK/ABI” pertencem àquelas rodadas.
- [Histórico P8](RETOMADA-R3.2.84-P8.md), [P7](RETOMADA-R3.2.84-P7.md), [P4](RETOMADA-R3.2.84-P4.md). Artefatos P9 e aceites anteriores continuam preservados, sem autorização de nova validação da família bloqueada.
- [Cronograma atual](docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md) e [escopo estruturado](release/escopo-R3.2.84.json) acompanham este resumo. O relatório e a coleção do lote anterior não foram reescritos.
