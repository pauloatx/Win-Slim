# Continuidade do cronograma durante AV-20261021-001

## Atualização vigente — 10/11/2026

Esta atualização prevalece sobre os quadros históricos de 29/10 e 22/10 abaixo, que ficam preservados como registo. [Estado atual único](../RETOMADA-R3.2.84-AV.md), [CI e evidências](CI-WINDOWS-HOSPEDADA-R3.2.84.md).

| Frente | Situação comprovada | Próximo passo elegível |
| --- | --- | --- |
| CI Windows hospedada | **Aprovada**: run [43032309531](https://github.com/pauloatx/Win-Slim/actions/runs/43032309531) (evento `push`, SHA `67786ae`) com conclusão **success**, job 12/12, **31/31 casos de regressão**, `Passed=true`, `ExitCode=0`, `TechnicalPassed=true`, `FreshCandidateEvidence=true`. Diagnóstico do `REG-UI-001` encerrado: a área de trabalho do runner (1024x728) não comporta a janela contratada de 1180x760 e o SO restringe-a; corrigido com o instrumento revisto `tools/validation/HostedDisplayPreparation.ps1` (falha fechada) e o caso `REG-HOSTEDDISPLAY-001`, **sem** afrouxar a expectativa do self-test nem alterar fontes de produção. Validação nativa na VM Windows 11 aprovada com `ExitCode=0`. `WS-BUG-0007` corrigido por `REG-RESTORE-001`: duas candidatas locais consecutivas passaram 32/32 e repuseram o EXE aceite sem intervenção manual | Conservar as evidências CI/VM e a revisão textual. `productionApproved=false`: a aprovação técnica não autoriza publicação; manter pendentes os restantes critérios de produção |
| Segurança e gate | `component-contained`, 53 activeFiles; PresentMonHarness/MonitorHarness retidos, guard-only/fontes intactos; incidente histórico sem resolução do fabricante. Corrida da CI não alterou escopo, contratos nem hashes da cadeia de revisão | Preservar escopo e evidências. O workflow mantém `contents: read`, ações fixadas por commit, checkout sem credencial persistente e nenhum pacote de distribuição |
| Temas/overlay/hotkey/Edge | Aceites anteriores da VM, jogo real com troca de tema, P9 funcional, correção UI-HOTKEY-WPARAM-001 e Edge Apply/Verify/Undo preservados | Não repetir sem regressão relacionada. Nenhuma alteração de produção nos fontes C#/XAML/backend nesta rodada de infraestrutura |
| Multimonitor físico | Não demonstrado; simulação WPF e runner não substituem hardware | Arraste livre com overlay visível entre monitores, quando houver ambiente apropriado; seguir janela automaticamente não é requisito |
| Próxima frente técnica independente do limitador | Revisões AMD/NVIDIA e leitor NVIDIA de fixtures preservados | Licença/ABI e leitor AMD restrito, quando retomado, sem escrita por jogo; NVIDIA física continua sem laboratório |
| Efeitos Edge condicionais | 018/OptionalData e 021/Entra sem aceite; 014/015 exigem revisão acima de 155 | Somente com condições específicas disponíveis; não repetir lotes aceitos |
| Publicação/produção | Pendentes/hold; nenhum pacote de distribuição criado ou enviado; `productionApproved=false` | CI hospedada real bem-sucedida e demais requisitos de escopo/revisão/aceite antes de qualquer decisão de produção |

Correção aplicada nesta data: as regras de exclusão do repositório passaram a ignorar apenas conteúdo gerado, e o repositório passou a rastrear **os 248 ficheiros do baseline byte a byte**, incluindo o executável nativo aceite `62eb3819580efa1d...` e o binário oficial de terceiros fixado `b2a706bc6ad47574...`. O runner passou a preparar um ecrã compatível com a janela contratada de 1180x760 antes do gate, porque o SO restringe a janela quando a área de trabalho é menor. Nenhuma fonte de produção, contrato Apply/Verify/Undo, harness retido ou aceite físico foi alterado. [Registo completo](CI-WINDOWS-HOSPEDADA-R3.2.84.md).

## Atualização anterior — 29/10/2026

Esta atualização prevalece sobre os quadros históricos de 22/10 abaixo. [Estado atual único](../RETOMADA-R3.2.84-AV.md), [CI e evidências](CI-WINDOWS-HOSPEDADA-R3.2.84.md).

| Frente | Situação comprovada | Próximo passo elegível |
| --- | --- | --- |
| CI Windows hospedada | Workflow implementado sobre o pipeline oficial; actionlint exit 0 e seis blocos PowerShell válidos. Gate **local** atual **30/30 + build/WPF**, exit 0; oito testes de CI e 13 checks de integridade. **Nenhuma execução hospedada**, URL/ID inexistentes | Associar a candidata a checkout autenticado do repositório correto, executar o runner real e conservar URL/SHA/ID/tentativa/artefatos. Pasta atual sem `.git`/remoto e sem credencial disponível. Não encerrar esta frente nem declarar CI aprovada por validação local |
| Segurança e gate | `component-contained`, 53 activeFiles; PresentMonHarness/MonitorHarness retidos, guard-only/fontes intactos; incidente histórico sem resolução do fabricante. Primeiro gate local falhou por identidade de EXE recompilado e a causa foi corrigida com regressão | Preservar escopo e evidências. Revisão textual para Nemotron 3 Ultra preparada, ainda não realizada; o gate de 30 casos substitui contagens históricas como cadastro atual |
| Temas/overlay/hotkey/Edge | Aceites anteriores da VM, jogo real com troca de tema, P9 funcional, correção UI-HOTKEY-WPARAM-001 e Edge Apply/Verify/Undo preservados | Não repetir sem regressão relacionada. Nenhuma alteração de produção nos fontes C#/XAML/backend nesta rodada |
| Multimonitor físico | Não demonstrado; simulação WPF e runner não substituem hardware | Arraste livre com overlay visível entre monitores, quando houver ambiente apropriado; seguir janela automaticamente não é requisito |
| Próxima frente técnica independente do limitador | Revisões AMD/NVIDIA e leitor NVIDIA de fixtures preservados | Licença/ABI e leitor AMD restrito, quando retomado, sem escrita por jogo; NVIDIA física continua sem laboratório |
| Efeitos Edge condicionais | 018/OptionalData e 021/Entra sem aceite; 014/015 exigem revisão acima de 155 | Somente com condições específicas disponíveis; não repetir lotes aceitos |
| Publicação/produção | Pendentes/hold; nenhum pacote de distribuição criado ou enviado | CI hospedada real bem-sucedida e demais requisitos de escopo/revisão/aceite antes de qualquer decisão de produção |

Próximo item imediato da frente solicitada: **executar a CI hospedada com acesso ao repositório**, não repetir validações físicas aprovadas. Em paralelo lógico de cronograma, sem iniciar novo escopo nesta rodada, licença/ABI AMD é a pendência técnica independente que dispensa novos aceites físicos. Os registros seguintes são históricos e não revogam a disposição atual.

22/10/2026. Este registro explicita a ordem e as dependências já autorizadas; não libera o incidente ou a produção. Fontes: pedido de monitoramento contínuo, item 10; [etapa posterior P7](IMPLEMENTACAO-R3.2.84-P7.md#etapa-posterior-fora-da-implementação-p7); [avaliação P9](AVALIACAO-RECURSOS-AVANCADOS-R3.2.84-P9.md). A avaliação P9 é histórica e seu gate anterior não constitui liberação AV.

**Estado atual:** [conclusão independente dos 31 IDs Edge](CONCLUSAO-EDGE-R3.2.84.md): revisão oficial, 31 contratos, backend/Registro e reconhecimento no navegador concluídos no escopo real da VM. Oito aceites originais preservados; 23 IDs adicionais validados em sete lotes, com 276 arquivos antes da baseline e Undo exato. EDGE-006 foi exercitado apenas como dependência de 007. Interação pela UI e efeitos condicionais permanecem sem aceite. **SDK/ABI e adaptador somente leitura retomados por autorização posterior:** pin de oito arquivos oficiais, leitor independente e 114 verificações de fixtures/ABI concluídos; caminho negativo real sem DLL NVIDIA confirmado. Sucesso físico NVIDIA pendente. [Relatório atual](LIMITADOR-SDK-ABI-LEITURA-R3.2.84.md). Incidente, auxiliares, gate e produção continuam bloqueados. [Estado atual único](../RETOMADA-R3.2.84-AV.md).

## Prioridade atual — integração oficial PresentMon, 22/10/2026

Por instrução posterior, a revisão/coleta oficial teve precedência sobre a expansão do limitador. **Concluída no escopo técnico independente:** runtime já usava console oficial 2.6.0; caminho/hash internos endurecidos, testes determinísticos migrados para dados sem os fontes dos auxiliares. **56 verificações de dados**, captura ETW isolada real (**969 linhas**) e **nove verificações integradas** com desktop real passaram. Binário coincide com release/digest oficial, Authenticode válido Intel; Kaspersky atualizado/ativo, scan **zero detecções**, sem alerta observado nessas execuções. [Relatório e lacunas](PRESENTMON-OFICIAL-INTEGRACAO-R3.2.84.md).

Build/self-test nativo WPF, **82 testes de overlay + 118 de configurações** e segurança/22 testes do empacotador passaram separadamente. DPI 100/125/150 é simulação WPF, sem aceite físico novo. `Validar-Regressoes.bat` continua recusado pelo hold antes das suítes; não há gate completo aprovado.

**Próximo passo:** fechar falhas forçadas/pressão de pipes e callback de prévia sem recriar coletor de teste; revisar o escopo do gate com essas evidências, mantendo a investigação histórica independente. Depois de gate novo, aceite físico da coleta/overlay e roteiro Edge UI pela VM. Aceites Edge/backend preservados sem repetição; efeitos condicionais/CI/produção pendentes. Auxiliares, publicação e produção retidos. AMD/NVIDIA preservados; licença/ABI AMD é o próximo item do limitador quando retomado.

## Histórico operacional — autorização e recorrência AV

O responsável registrou avaliação de falso positivo, relatou atualização/teste aprovado e autorizou compilação/execução local e gate, sem produção. [Decisão](DECISAO-RESPONSAVEL-AV-20261021-001.md). A rodada controlada foi executada; compilação/WPF passaram, mas nova detecção do PresentMonHarness às 06:58:39 interrompeu o gate e suspendeu a autorização operacional. **15 suítes aprovadas, uma falha e nove não executadas de 25**; não há aprovação completa. [Recorrência e próximo passo](AV-RECORRENCIA-20261022-R3.2.84.md).

Publicação/produção permaneceram bloqueadas em todo o período; família/gate estão novamente retidos. Antivírus ativo, sem exclusões. Etapas independentes AMD continuam permitidas; nenhuma escrita de driver autorizada, nenhum teste Edge real repetido. O cadastro atual é de **25 suítes** após REG-CATALOGBASE-001; contagens anteriores abaixo são históricas.

## Prioridade anterior do limitador — hardware confirmado em 22/10/2026

**RX 480 de 8 GB; sem laboratório NVIDIA.** Consulta física NVIDIA fica pendente por falta de hardware, preservando o adaptador e sem instalar driver NVIDIA neste computador. A revisão anterior à implementação AMD foi concluída: [APIs, compatibilidade e limites](LIMITADOR-AMD-RX480-R3.2.84.md). Treze fontes oficiais fixadas e inventário estático de metadados/exports; nenhuma chamada ao driver ou alteração gráfica.

**Próximo item independente do limitador após a prioridade PresentMon acima:** fechar licença e ABI/contrato de leitor AMD restrito antes de consulta nativa. ADLX é o caminho recomendado para estudo; ADL é alternativa legada delimitada. API por GPU/global não equivale a controle por executável. FRTC atual não confirma RX 480; Chill possui dependências e herança. Escrita por jogo e suporte físico seguem pendentes. [Contrato documental](../specs/LIMITADOR-AMD-RX480-R3.2.84.json).

## Histórico do protótipo puro preservado

A avaliação P9 identifica o **limitador por jogo como primeiro recurso** e propõe começar por fixtures de driver, distinguindo perfis, herança, ausência e mudanças externas. Foi executada a parte independente: **modelo de planejamento e transição de estado em memória**, separado do aplicativo, em `tools/prototypes/FrameLimitPlan.ps1`.

O modelo recebe somente dados identificados como fixture e retorna propostas/snapshots. Não carrega NVAPI, não consulta GPU, não abre ETW, não inicia processos, não compila auxiliares, não escreve no Registro/driver e não entra no build da UI. `CanApplyToDriver=false` identifica explicitamente esse limite. Não é um limitador de FPS disponível no aplicativo.

Comportamentos cobertos:

- Associação pelo caminho completo do executável; outro jogo com o mesmo nome permanece isolado. Associação ausente/ambígua e perfil global/compartilhado bloqueiam a proposta.
- Valores precisam pertencer à capacidade ilustrativa fornecida; tipos incorretos, dados indisponíveis/incompletos e contrato incompatível falham sem modificar a entrada. A lista `0,30,60,120` pertence apenas às fixtures; não comprova faixa/unidade suportada por driver.
- Backup em memória conserva origem explícita, herdada, ausente ou predefinida. Valor zero não representa ausência. Valor já efetivo não materializa um override desnecessário.
- Transição copia dados, preservando outros perfis/configurações. Verify compara o estado esperado; Undo devolve o estado original somente se o snapshot atual ainda corresponder ao esperado. Mudanças externas, inclusive em outro perfil, exigem nova revisão; a recusa é conservadora.
- Digests identificam proposta/snapshot e detectam alterações acidentais. Não são assinatura nem fronteira de autorização; não substituem backup persistente autenticado ou controle de concorrência de um adaptador real.
- Injeções `Backup/Set/Save/Verify` exercitam a recusa **antes de publicar a saída do modelo**. Não são falhas de chamadas NVAPI reais nem comprovam rollback de escrita física. Esse teste continua pendente para o futuro adaptador.

Regressão independente: `REG-FRAMELIMITPLAN-001`, em `tests/regression/Test-FrameLimitPlan-R3.2.84.ps1`, cadastrada para execução futura do gate completo. **64 verificações comportamentais passaram**: resultados, entradas inválidas/ausentes e preservação do estado, sem depender de busca de strings nos fontes. Passou também `REG-SECURITY-001` isoladamente, incluindo 21 testes Python com arquivos inertes; os pontos de entrada da família foram recusados antes de criar/compilar auxiliares. Naquela rodada havia 21 suítes; o cadastro atual exige **24**, após `REG-VMEDGE-001`, `REG-EDGECOMP-001` e `REG-NVAPIRO-001`. O gate completo permanece bloqueado.

## Ordem e situação — histórico de 22/10/2026

| Item | Situação | Próxima dependência/critério |
| --- | --- | --- |
| Edge — lote original EDGE-019/020/024/025 | **Concluído, preservado sem repetir testes** | [Relatório e evidências](EDGE-VM-ISOLADO-R3.2.84.md). Apply/Verify, quatro status OK e Undo exato; 40 arquivos antes da baseline. Causa histórica depende do registro anterior; cliques/efeitos não inferidos |
| Próxima pendência executada — EDGE-003/004/005/006 | **Concluída no escopo real backend/políticas/Undo; VM desligada e baseline restaurada** | [Novo relatório](EDGE-CATALOGO-PROXIMO-LOTE-R3.2.84.md). Quatro status OK, backup/Undo exato, 41 arquivos antes da baseline; 154 fixtures separadas |
| Edge — demais 23 IDs e contratos restantes | **Concluído o trabalho independente de contratos/backend/reconhecimento:** 31 contratos e 31 IDs no total, oito preservados + 23 atuais | [Matriz oficial](COMPATIBILIDADE-EDGE-R3.2.84.md), [sete lotes reais](CONCLUSAO-EDGE-R3.2.84.md). 001/002 com lacuna resolvida por teste atual; 975 fixtures finais separadas do aceite real |
| Edge — UI e efeitos condicionais | **Roteiro preparado, ainda não executado** | [Aceite UI](ROTEIRO-ACEITE-EDGE-UI-R3.2.84.md) depende de resolução AV e gate novo pelo fluxo oficial; efeito de 021 requer perfil Entra, efeito de 018 requer cenário OptionalData ausente. 014/015 exigem nova revisão acima de 155; não liberar versões por força |
| Avaliação de arquitetura/licenças — primeiro limitador | Concluída documentalmente em P9 | Não equivale à implementação/compatibilidade física |
| Contrato do planejador do limitador | Implementado e testado em memória nesta rodada | Resultado restrito ao modelo; nenhum controle de FPS real |
| AMD RX 480 — revisão anterior à implementação | **Concluída documentalmente; hardware de 8 GB confirmado** | Próximo: licença/ABI e leitor restrito. DLLs/export presentes inspecionados estaticamente não são IsSupported nem aceite físico. Controle por jogo depende de contrato de propriedades/herança/Undo |
| NVIDIA — validação física | **Pendente por falta de hardware/laboratório** | Adaptador e evidências preservados. Não instalar driver NVIDIA no host AMD; retomar quando houver ambiente NVIDIA adequado |
| SDK/ABI e adaptador somente leitura | **Etapa independente retomada e implementada; 114 verificações com fixtures/ABI passaram** | [Pin e revisão](LIMITADOR-SDK-ABI-LEITURA-R3.2.84.md). DLL própria de desenvolvimento, sem Set/Save, sem runtime/UI. Host AMD sem nvapi64.dll: indisponibilidade real confirmada; matriz física NVIDIA e comparação C++ pendentes |
| Escrita por jogo e recuperação | Pendente | Adaptador de leitura validado, backup persistente, falhas reais por etapa, associação/perfis compartilhados e concorrência. Depois, fluxo normal Review/Apply/Verify/Undo e aceite físico |
| Sincronização e exclusivo ampliado | Pendente de mecanismo cooperativo | Integração documentada, licença e instrumentação externa; não anunciar suporte do HWND externo |
| Família PresentMonHarness/MonitorHarness | **Bloqueada pelo incidente** | Resolução técnica/de segurança documentada após resposta do fabricante; não recompilar/executar variantes |
| Gate completo e nova distribuição/produção | **Bloqueados** | Resolução do incidente, gate fresco de todo o cadastro + WPF, demais aceites/CI; nenhuma soma de testes independentes libera essa etapa |
| Aceite funcional físico P9/CI | Pendente | Visual aceito preservado. Edge foi testado realmente apenas na VM, no alcance do relatório; fixtures não substituíram esse teste |

O contrato foi rechecado nas fontes oficiais: [`FRL_FPS_ID`/valores](https://raw.githubusercontent.com/NVIDIA/nvapi/main/NvApiDriverSettings.h), [DRS](https://raw.githubusercontent.com/NVIDIA/nvapi/main/nvapi.h), [licença](https://raw.githubusercontent.com/NVIDIA/nvapi/main/License.txt). DRS permite localizar perfil por caminho completo e distingue leitura/escrita/exclusão de setting. Isso orientou o modelo inicial; não comprovava ABI, retorno de um driver instalado ou semântica física de cada valor. As URLs `main` são referências consultadas, **não o pin do SDK atual**. A etapa posterior fixa commit/hashes de oito textos no manifesto NVAPI; nenhuma biblioteca/driver NVIDIA incorporada. O modelo inicial permanece sem dependência NVIDIA.

## Critérios para retomar o gate

1. Preservar a resposta do fabricante, protocolo, data, identificação da detecção e alcance da análise. Orientação de triagem ou parecer somente sobre fontes não libera automaticamente uma amostra desconhecida.
2. Correlacionar amostra/hash originais ou documentar, com o fabricante, a ausência deles e qual artefato/versão foi efetivamente analisado. Não atribuir hash de outra geração ao primeiro evento. Se a resposta for inconclusiva ou indicar ameaça, manter o bloqueio e tratar as pendências correspondentes.
3. Registrar a resolução técnica/de segurança e correções justificadas; adicionar regressões comportamentais para bugs corrigidos. Nenhuma exclusão AV, renomeação para evitar detecção ou restauração automática é critério de liberação.
4. Revisar a disposição `investigating` somente com resolução documentada. O recebimento de uma resposta não muda a política automaticamente. Preservar logs/candidatas antigas; uma futura geração autorizada deve registrar compilador, fontes e hash antes da execução.
5. Executar `Validar-Regressoes.bat`/pipeline normal em uma execução nova, com todo o cadastro atual e self-test WPF, sem resultados vazios/parciais/duplicados ou reaproveitados. Corrigir falhas e repetir as verificações afetadas e o gate exigido.
6. Somente então preparar nova candidata isolada pelo empacotador validado e perfil apropriado. Produção ainda exige CI Windows e aceites físicos pendentes. Não repetir manualmente famílias já aceitas sem mudança/regressão relacionada.

Evidências desta rodada ficam em `logs/independent-schedule-20261021/`, fora do dossiê congelado. [Retomada atual](../RETOMADA-R3.2.84-AV.md). Nenhum envio automático ao fabricante, nova candidata ou aprovação de produção.
