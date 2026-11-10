# Retomada R3.2.84 — estado atual único

21/10/2026. [Conclusão independente Edge](docs/CONCLUSAO-EDGE-R3.2.84.md), [inventário completo](docs/ESTADO-CATALOGO-EDGE-R3.2.84.md) e [compatibilidade oficial](docs/COMPATIBILIDADE-EDGE-R3.2.84.md). Não tratar históricos antigos como situação atual.

## Estado atual

| Frente | Comprovado | Pendência / próximo passo |
| --- | --- | --- |
| Oito aceites Edge anteriores | EDGE-003/004/005/006 e EDGE-019/020/024/025 preservados, sem substituir seus relatórios/coleções | Somente EDGE-006 exercitado como dependência de 007, sem repetir a suíte Core. Alcance original preservado |
| Demais 23 IDs Edge | Sete lotes na VM concluídos: revisão oficial 008/011/012/016; busca e teste atual 001/002; 17 contratos novos. **31 contratos, 31 IDs com backend/Registro e reconhecimento OK no navegador** | [Tabela por ID](docs/ESTADO-CATALOGO-EDGE-R3.2.84.md); não é aprovação de produção nem de todos os efeitos |
| Backend | Backup verificado antes da escrita, Apply/Verify, Undo exato à ausência original; handshake real anuncia 52 contratos, 31 Edge | Estados reais presentes/diferentes e falhas por etapa foram testados em fixtures, sem classificação física |
| Navegador | Sete PNG aplicados reais inspecionados; todos os nomes/valores/status OK no Edge 155.0.4283.62 | DOM parcial não é exportação completa. 018 sem condição OptionalData e 021 sem perfil Entra: efeitos não aceitos; demais efeitos específicos também não inferidos |
| Interação pela UI do Win-Slim | Contratos/anúncio e notas de compatibilidade implementados no backend/catálogo; C#/XAML e acabamento preservados | Cliques Review/Apply/Undo e leitura física das novas notas pendentes; não aprovados por automação do backend |
| Autofill 014/015 | Depreciadas ainda suportadas, reconhecidas OK em 155; máximo revisado 155 aplicado no filtro | Bloquear versão posterior até nova revisão/migração para AutofillSettings; sem liberação forçada |
| **AV-20261021-001** | **Investigando; sem conclusão de falso positivo. PresentMonHarness/MonitorHarness bloqueados para geração/execução** | Resposta correlacionável do fabricante, amostra/hash originais ou resolução explícita de sua ausência. [Dossiê](docs/INCIDENTE-KASPERSKY-R3.2.84.md), [envio manual/lacunas](logs/kaspersky-investigation-20261021/static-review-02/ENVIO-MANUAL.md). Nada enviado automaticamente |
| **Gate completo / distribuição / produção** | **Bloqueados.** Nenhuma nova candidata/ZIP de aplicativo | Resolução técnica/de segurança, revisão do hold e gate novo das **23 suítes** + WPF. Depois CI/aceites físicos. Não somar testes independentes nem reaproveitar P9 |
| Overlay/UI P9 | Aceite visual/funcionamento observado e aceites P4 preservados; executável, fontes visuais/estatísticas e dois fontes de harness intactos | Funções físicas restantes de foco/cliques/atalhos, Salvar/Cancelar, sensores/DPI/múltiplos monitores continuam sem aceite adicional |
| Limitador | Protótipo puro preservado; nenhuma expansão de SDK/ABI/adaptador | **Pausado.** Contratos/backend Edge independentes concluídos, porém UI/efeitos condicionais e gate continuam pendentes; não retomado nesta tarefa |

## Evidências e verificações desta rodada

- `logs/edge-completion-20261021/`: **276 arquivos** de convidado coletados e conferidos antes da baseline; resultados por lote, sete backups originais e recuperação, hashes, capturas e revisão visual. [Resumo real](logs/edge-completion-20261021/batch-results.json).
- VM TESTE / VirtualBox, Edge 155.0.4283.62, sessão 1 elevada. Undo real verificado antes da restauração; consulta independente HKLM/HKCU 32/64 igual ao inicial. Desligamento normal ACPI, WINSLIM_BASELINE restaurada, estado final poweroff. [Comprovante agregado](logs/edge-completion-20261021/baseline-all-batches-receipt.json). Edge do host não foi aberto/configurado pelos roteiros.
- REG-EDGECOMP-001: falha inicial antes dos contratos preservada; **975 verificações comportamentais finais simuladas passaram**. Suítes familiares na VM também passaram (155/47/88/120/240/60/44), separadas das escritas reais. **125** verificações de Apply existentes e **28** do coletor passaram. Cadastro atual: **23 suítes para gate futuro**, sem execução completa.
- Sem exclusões AV, alteração de proteção, restauração de quarentena, renomeação do auxiliar para evitar detecção ou execução/compilação da família bloqueada. Sem produção aprovada.
- Conferência final: **445 evidências anteriores e 21 arquivos protegidos P9 intactos**, oito aceites e política AV/protótipo preservados, runtime final igual ao último staging real. Sintaxe PS 5.1 de **dez scripts válida**; cadastro/scripts/hashes validados sem empacotar: **23 suítes únicas, 189 hashes**. [Resumo](logs/edge-completion-20261021/verification-summary.json). Não é gate completo nem teste de interação WPF.

## Critérios para retomar o gate

1. Preservar resposta/protocolo, identidade e alcance da análise do fabricante. Fontes ou outra compilação não identificam a amostra original desconhecida.
2. Correlacionar amostra/hash originais ou resolver/documentar a ausência com o fabricante; parecer inconclusivo mantém bloqueio.
3. Registrar resolução técnica/de segurança e correções justificadas com regressões. Só então revisar investigating; resposta recebida não libera automaticamente.
4. Após revisão do hold, registrar proveniência antes de execução autorizada e executar gate fresco completo + WPF. Falhas/parcialidade impedem empacotamento. CI e aceites físicos ainda condicionam produção.

## Histórico preservado — separado do estado atual

- [Retomada imediatamente anterior à conclusão Edge](docs/historico/RETOMADA-R3.2.84-AV-antes-conclusao-edge.md), com inventário inicial de 14 contratos e oito aceites.
- [Retomada AV anterior ao levantamento](docs/historico/RETOMADA-R3.2.84-AV-antes-catalogo-edge.md): investigação, revisão estática e protótipo.
- [Relatório original EDGE-019/020/024/025](docs/EDGE-VM-ISOLADO-R3.2.84.md), [EDGE-003/004/005/006](docs/EDGE-CATALOGO-PROXIMO-LOTE-R3.2.84.md), [P8](RETOMADA-R3.2.84-P8.md), [P7](RETOMADA-R3.2.84-P7.md), [P4](RETOMADA-R3.2.84-P4.md). Aceites e evidências não reescritos; pendências e prioridades antigas são históricas.
- [Cronograma](docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md) e [escopo](release/escopo-R3.2.84.json) acompanham este estado.
