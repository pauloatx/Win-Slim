# Retomada R3.2.84 — estado atual único

22/10/2026. Este resumo substitui as prioridades históricas abaixo, sem reclassificar os aceites anteriores. [Cronograma](docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md), [escopo](release/escopo-R3.2.84.json).

## Estado atual

| Frente | Comprovado / concluído | Pendência e próximo passo |
| --- | --- | --- |
| **Edge — 31 contratos** | **Etapa concluída: contratos revisados, backend real, Apply/Verify, reconhecimento no navegador e Undo exato na VM.** Oito aceites originais preservados + 23 IDs em sete lotes; nenhum lote repetido nesta continuidade | Não reabrir o aceite do backend sem regressão/mudança relacionada. [Conclusão](docs/CONCLUSAO-EDGE-R3.2.84.md), [31 IDs](docs/ESTADO-CATALOGO-EDGE-R3.2.84.md) |
| Edge — evidências reais | Backup antes de escrita, restauração da ausência original, capturas reais de políticas OK. Mais recentes: 276 arquivos do convidado conferidos antes da baseline; VM desligada, WINSLIM_BASELINE restaurada | DOM parcial não substitui os PNG reais inspecionados. Edge do host não foi configurado. Nesta rodada, sem boot/aplicação na VM |
| Edge — interação pela UI | [Roteiro curto preparado](docs/ROTEIRO-ACEITE-EDGE-UI-R3.2.84.md): seleção, dependência 007→006, notas, prévia/cancelamento, Apply e restauração | **Não executado.** `Iniciar-Validacao.bat` exige gate completo antes de abrir; `FullRegressionGate` está retido pelo AV. Resolver incidente, revisar hold e passar gate novo + WPF; depois executar roteiro somente na VM, sem abrir candidata antiga como contorno |
| Edge — compatibilidade e efeitos | Reconhecimento no Edge 155.0.4283.62 comprovado. 014/015 depreciadas ainda suportadas, filtro revisado até 155 | Acima de 155: nova revisão/migração, sem forçar liberação. Efeitos 018 exigem OptionalData e 021 perfil Entra adequados; **não aprovados**. Outros efeitos de conta/rede e causa histórica de erros não inferidos |
| **Limitador — SDK/ABI e leitura** | **Retomado por autorização posterior:** oito textos oficiais fixados por commit/hash/licença, leitor independente x64 sem Set/Save, 114 verificações comportamentais/ABI com fixtures passaram | [Relatório e limites](docs/LIMITADOR-SDK-ABI-LEITURA-R3.2.84.md). Comparação ctypes/.NET não é chamada ABI física nem ensaio C++. Protótipo anterior intacto; sem integração no aplicativo e `CanApplyToDriver=false` |
| Limitador — ambiente físico | Host Radeon RX 480, sem `nvapi64.dll`. Compilação sem fixture e consulta negativa real: `Unavailable / DriverLibraryMissing`, valor nulo, nenhum driver carregado/chamado | Próximo item: matriz somente leitura em laboratório **NVIDIA x64 com driver instalado/assinatura válida**. Ausência concreta de hardware/driver impede sucesso físico aqui. Não instalar driver nem usar simulação como aprovação física. Escrita/recuperação/FPS e integração são etapas futuras |
| **AV-20261021-001** | **Investigando, sem diagnóstico de falso positivo. PresentMonHarness/MonitorHarness e variantes permanecem sem geração/execução** | Resposta correlacionável do fabricante, amostra/hash originais ou resolução documentada da ausência. [Dossiê](docs/INCIDENTE-KASPERSKY-R3.2.84.md), [envio manual/lacunas](logs/kaspersky-investigation-20261021/static-review-02/ENVIO-MANUAL.md). Nada enviado automaticamente |
| **Gate / distribuição / produção** | **Bloqueados.** Política de segurança preservada; nenhuma nova candidata/ZIP de aplicativo | Resolução técnica/de segurança e revisão do hold; gate fresco das **24 suítes** + self-test WPF. Depois CI e aceites físicos. Resultados independentes não substituem esse gate; P9 não é autorização de produção |
| Overlay/UI e métricas | Aceite visual/funcionamento observado do usuário e aceites P4 preservados. Executável, fontes C#/XAML/estatísticas e fontes dos auxiliares retidos intactos | Funções físicas restantes de foco/cliques/atalhos, Salvar/Cancelar, sensores/DPI/múltiplos monitores e CI permanecem pendentes; nenhum novo aceite WPF foi atribuído |

## Trabalho desta continuidade e verificações

- Encerramento formal Edge e roteiro UI preparados a partir dos relatórios existentes. Não foram repetidos testes Edge aprovados, aplicadas políticas ou iniciada a UI.
- SDK NVIDIA/nvapi `70d337db9186e968eab622f7e786de7e437faf3d`, oito cabeçalhos/documentos/licença sem alteração. Nenhuma biblioteca de importação, instalador ou driver redistribuído. Leitor em `tools/prototypes/NvapiReadOnly.cs` / `.ps1`, fora do runtime.
- `REG-NVAPIRO-001`: **114 verificações com fixtures/ABI passaram**; duas falhas iniciais e correções preservadas (sintaxe de proveniência, overload PowerShell/Marshal). Inclui origens, ausência/zero, caminho completo, perfis compartilhados/globais, erros/indisponibilidade e limpeza. Nova DLL própria tem hashes de compilador/fontes/saída registrados antes de carregar; não é variante da família retida.
- Compilação independente sem fixture e teste negativo real do host passaram, sem NVAPI físico. [Resultado](logs/limiter-sdk-20261021/native-unavailable-result.json). Não comprovam funcionamento do limitador nem ABI física NVIDIA.
- Cadastro futuro: **24 suítes**. Conferência de sintaxe, cadastro/scripts/hashes e preservação registrados em [verificação consolidada](logs/limiter-sdk-20261021/verification-summary.json). Essa validação de fontes não cria pacote nem executa gate completo.
- Sem exclusões AV, alteração de proteção, restauração de quarentena, renomeação para evitar detecção ou compilação/execução de auxiliares retidos. Sem escrita de configurações de GPU/driver no host.

## Critérios para retomar o gate

1. Preservar resposta/protocolo, identidade e alcance da análise do fabricante. Fontes ou outra compilação não identificam a amostra original desconhecida.
2. Correlacionar amostra/hash originais ou resolver/documentar a ausência com o fabricante; parecer inconclusivo mantém bloqueio.
3. Registrar resolução técnica/de segurança e correções justificadas com regressões. Só então revisar `investigating`; resposta recebida não libera automaticamente.
4. Após revisão do hold, registrar proveniência antes da execução autorizada e executar gate fresco completo + WPF. Falhas/parcialidade impedem empacotamento. CI e aceites físicos ainda condicionam produção.

## Histórico preservado — separado do estado atual

- [Estado imediatamente anterior à retomada do SDK/leitor](docs/historico/RETOMADA-R3.2.84-AV-antes-retomada-limitador.md): Edge concluído e limitador então pausado.
- [Estado anterior à conclusão Edge](docs/historico/RETOMADA-R3.2.84-AV-antes-conclusao-edge.md) e [estado AV anterior ao levantamento](docs/historico/RETOMADA-R3.2.84-AV-antes-catalogo-edge.md).
- [EDGE-019/020/024/025](docs/EDGE-VM-ISOLADO-R3.2.84.md), [EDGE-003/004/005/006](docs/EDGE-CATALOGO-PROXIMO-LOTE-R3.2.84.md), [23 IDs adicionais](docs/CONCLUSAO-EDGE-R3.2.84.md). Registros e coleções reais preservados.
- [P8](RETOMADA-R3.2.84-P8.md), [P7](RETOMADA-R3.2.84-P7.md), [P4](RETOMADA-R3.2.84-P4.md). Pendências e prioridades históricas não substituem o quadro atual.
