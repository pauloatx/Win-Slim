# Win-Slim Suite — continuidade para outro agente

**Preparado em 23/10/2026. Último estado técnico documentado: 22/10/2026, após a validação do PresentMon oficial.**

Este documento permite retomar o trabalho sem reconstruir toda a conversa. É uma consolidação de relatórios fornecidos pelo responsável e do histórico da sessão; não é uma auditoria nova do repositório, nem um pacote de código. Os resultados descritos foram registrados pelo agente local no Windows. Nenhum teste Windows foi executado para produzir este handoff.

## 1. Leia primeiro: objetivo e ação imediata

Você continuará o **Win-Slim Suite**, aplicativo Windows de otimização com interface C#/WPF e motor PowerShell. O responsável quer concluir o escopo do projeto antes do lançamento, preservar as funções e o acabamento já aceitos e reduzir trabalho manual repetitivo.

**Prioridade atual:** concluir as lacunas de validação do transporte/preview da integração PresentMon, revisar tecnicamente o alcance do bloqueio do gate e, quando os critérios forem atendidos, executar uma rodada completa atual de regressão + WPF. Depois preparar aceite em jogo no host e aceite Edge pela UI na VM.

**Não começar pelo limitador AMD/NVIDIA nem redesenhar a interface.** Essas frentes têm pendências próprias e não são a prioridade imediata.

**Não presumir que o MonitorHarness substituía o PresentMon.** A inspeção confirmou que o runtime já utilizava o console oficial Intel PresentMon 2.6.0. PresentMonHarness e MonitorHarness eram exclusivamente auxiliares de teste.

O gate completo e a produção ainda não estão aprovados. A troca dos testes para fixtures e a captura oficial sem alerta não são uma resolução do incidente histórico dos auxiliares.

## 2. Onde trabalhar e como confirmar o estado

| Item | Local ou identificação conhecida |
| --- | --- |
| Raiz de desenvolvimento no PC | `D:\Desktop\winslim_fase7_r3_2_84` |
| Repositório informado | `https://github.com/pauloatx/Win-Slim` |
| Estado canônico no checkout | `RETOMADA-R3.2.84-AV.md` |
| Cronograma atual | `docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md` |
| Escopo atual | `release/escopo-R3.2.84.json` |
| Instruções locais | `AGENTS.md` e eventuais arquivos mais específicos |
| Fontes UI atuais | `src/UI/Native/R3_2_84/` |
| Catálogo de regressão | `tests/regression/cases.json` |
| Registro do incidente | `release/security-incidents.json` |
| Política de execução | `tools/TestExecutionPolicy.ps1` |
| Empacotador | `tools/package_release.py` |
| Baseline de arquivos | `specs/FASE7-R3.2.84-baseline.json` |

O estado local pode ser mais recente que este MD e que o GitHub. Não sobrescrever alterações locais com uma cópia antiga. Branch, commit, estado de push e lista exata de arquivos modificados não foram fornecidos: determinar no checkout. Não executar reset/clean para obter uma árvore “limpa”.

Se você estiver em um agente remoto, não terá acesso automático ao disco D: do usuário. Nesse caso, obtenha o checkout/pacote atual e os relatórios necessários; não afirme ter editado arquivos do PC. Prefira continuar no agente local do VS Code com a pasta correta aberta.

### Inspeção inicial no Windows — somente leitura

```powershell
Set-Location -LiteralPath 'D:\Desktop\winslim_fase7_r3_2_84'
Get-Location
git status --short
git branch --show-current
git log -5 --oneline
Get-Content -LiteralPath '.\AGENTS.md' -Raw
Get-Content -LiteralPath '.\RETOMADA-R3.2.84-AV.md' -Raw
Get-Content -LiteralPath '.\docs\CRONOGRAMA-INDEPENDENTE-R3.2.84.md' -Raw
Get-Content -LiteralPath '.\release\escopo-R3.2.84.json' -Raw
```

Se a pasta não for um checkout Git, registre isso e use o manifesto/identidade do pacote existente. Descubra as instruções dos subdiretórios antes de editá-los. Confira scripts e parâmetros atuais antes de executar qualquer comando de validação: os nomes abaixo descrevem o fluxo conhecido, não autorização para contornar um bloqueio.

## 3. Modo de colaboração e requisitos permanentes

- Comunicação em português brasileiro, explicações simples e ações concretas.
- Avançar automaticamente após cada etapa passar nas verificações previstas. Em falha, diagnosticar e corrigir antes de avançar. Não pedir confirmação repetida para trabalho já autorizado.
- Fazer testes proporcionais à mudança; não repetir lotes aprovados sem alteração relacionada ou preocupação demonstrada.
- Preservar evidências e distinguir simulação, integração real, interação pela UI e efeitos físicos.
- Não declarar produção pronta por compilação, contagem de asserts ou aprovação de uma suíte isolada.
- Não fornecer percentual global ou prazo preciso sem inventário verificável do escopo e estimativa explícita.
- Preservar o acabamento visual aceito. O usuário cancelou a proposta de migrar para Rust; manter a arquitetura atual.
- O objetivo do produto continua sendo compatibilidade Windows 10/11, detecção de versão e ajustes compatíveis com hardware/edição.
- Presets Equilibrado, Gamer e Extremo; cada ajuste deve ter Apply/Verify/Undo, risco, compatibilidade, dependências e conflitos.
- Backup e restauração devem distinguir valor ausente de valor existente, preservar tipos/dados e lidar com falha parcial.
- SysMain e Windows Search são opções. Não desligar Defender, Firewall ou Windows Update por padrão.
- Não prometer ganho de desempenho com base em uma única captura; medir a mesma cena, duração e configurações.

## 4. Arquitetura e evolução resumidas

Motor PowerShell, com providers de Registro, serviços, BCD, PowerCfg, rede, Appx, tarefas agendadas e comandos; transações, prévia, backup, verificação e Undo. O histórico das fases 0–6.5 inclui conformidade dos providers, journaling, recuperação e rollback. Essas aprovações são históricas: não equivalem a uma nova validação integral do checkout atual.

Fase 7 introduziu a UI nativa C#/WPF/.NET Framework e a integração progressiva com o motor. Ambiente conhecido: Windows PowerShell 5.1. A compilação usa ferramentas locais do Windows/.NET; conferir dependências efetivas nos scripts. Python é utilizado em ferramentas de empacotamento, sem presumir dependência do usuário final.

A linha atual é **R3.2.84**. Houve candidatas P4, P5, P6, P7, P8 e P9. P9 é a última candidata identificada no histórico antes das revisões bloqueadas; ela não é automaticamente distribuível. O relatório mais recente registra recompilação local da UI para verificação, mas **nenhum novo ZIP de candidata**.

### Interface a preservar

Tema escuro com laranja, janela compacta, sidebar estreita, cards densos, animações curtas, tooltips didáticas e navegação interna. Há suporte a tema claro/escuro; não reconstruir telas a partir de descrições antigas se o checkout contém acabamento mais recente.

Fluxos: início/dashboard, presets, personalizado, detalhes, prévia, aplicação, conclusão, backup/restauração, análise do sistema e configurações. Seleção por categoria, preservação de outras seleções, dependências explícitas, prévia antes de escrever, resultado por item e restauração clara são requisitos importantes. CPU/RAM/carregamento de Personalizado já receberam otimizações aceitas.

## 5. Estado atual por frente

| Frente | Evidência registrada | Pendente |
| --- | --- | --- |
| PresentMon oficial | Console 2.6.0, origem/hash/licença/assinatura verificados, captura ETW real | Aceite em jogo e lacunas de transporte/preview |
| Dados PresentMon | 36 + 20 verificações determinísticas | Não confundir TextReader em memória com pressão de pipes do SO |
| Integração oficial | 9 verificações, capturas reais do desktop, cancelamento/reinício | Cliques de UI e comportamento físico do jogo |
| UI/overlay | Build/self-test WPF, 82 verificações overlay + 118 configurações | Foco, cliques, DPI físico, sensores e múltiplos monitores |
| Edge | 31 contratos, backend real, reconhecimento pelo navegador e Undo na VM | Aceite pela UI e efeitos condicionais |
| AV histórico | Evidências preservadas e família retida | Análise histórica sem parecer do fabricante |
| Gate | Segurança/22 testes inertes do empacotador passaram | Gate completo retornou Security hold antes das suítes |
| Limitador NVIDIA | Modelo e leitor somente leitura, fixtures/ABI | Hardware NVIDIA e implementação real do limitador |
| Limitador AMD | Revisão documental e inventário estático | Licença/ABI, leitor físico e contrato por jogo |
| CI/distribuição | Estrutura e validações parciais documentadas | CI hospedada, gate integral, aceites e aprovação de produção |

## 6. PresentMon: implementação que deve continuar

### Provedor oficial

- Repositório: `https://github.com/GameTechDev/PresentMon`.
- Release fixada no relatório: `v2.6.0`, console x64.
- Binário: `third_party/PresentMon/PresentMon-2.6.0-x64.exe`.
- SHA-256 registrado: `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`.
- Tamanho registrado: 980.320 bytes.
- Assinatura observada no host: Valid, Intel Corporation. Recursos FileVersion/ProductVersion ausentes; versão confirmada por release, hash e banner.
- Licença MIT e avisos preservados. Confirmar `provenance.json` no checkout.

Esses são dados da verificação registrada em 22/10; conferir identidade antes de novas execuções ou distribuição. Não atualizar para outra release sem revisar contrato e compatibilidade.

### Fluxo de coleta

`MainWindowController` → `PresentMonMonitor.StartAsync` → console oficial → CSV stdout → `BenchmarkLiveReader` → snapshots da UI/overlay.

`PresentMonMonitor.RecordAsync` grava um benchmark a partir da sessão contínua. Cancelar gravação deve preservar monitoramento e resultado anterior. `PresentMonBenchmark.CaptureAsync` cria e encerra sua própria sessão para a API isolada. O overlay não deve iniciar um segundo coletor.

Argumentos registrados: `--output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input`, PID explícito e sessão `WinSlim-<GUID>`. Conferir argumentos completos no código. Encerrar somente sessões/processos pertencentes à execução.

As métricas usam intervalos de apresentação `MsBetweenPresents`; não anunciar FPS exibido ou latência de entrada a partir dessas métricas. Fórmulas existentes de média, 1% low, P99, janelas temporais e redução visual por máximos foram preservadas.

### Arquivos importantes

- `src/UI/Native/R3_2_84/PresentMonBenchmark.cs`
- `src/UI/Native/R3_2_84/PresentMonMonitor.cs`
- `src/UI/Native/R3_2_84/BenchmarkLive.cs`
- `tests/Test-Fase7-R3.2.84-PresentMonData.ps1`
- `tests/Test-Fase7-R3.2.84-MonitorData.ps1`
- `tools/validation/WinSlimCaptureData.ps1`
- `tools/integration/Invoke-WinSlimOfficialPresentMonProbe.ps1`
- `tools/integration/Test-WinSlimOfficialPresentMonIntegration.ps1`
- Evidências: `logs/presentmon-official-20261022/`.

O cadastro mantém `REG-PRESENTMON-001` e `REG-MONITOR-001`, agora apontando para testes de dados. Verificar se os identificadores e descrições continuam representando a cobertura real. Os novos testes compilam somente classes de produção como DLL sem Main; não incluem os dois fontes de harness.

### Resultados e lacunas específicas

Captura isolada de 3 segundos: saída 0, 969 linhas. Integração final: duas capturas de 10 segundos de `dwm.exe`, com 610 e 605 intervalos válidos. Não são medições de desempenho de jogo.

Lacunas: saída não zero do processo, falha de preview externo e pressão simultânea de stdout/stderr em pipes reais do sistema operacional. Os testes de TextReader drenaram 200.000 caracteres de erro com retenção limitada a 4.096 e exercitaram CSV grande; isso não cobre automaticamente pressão de pipes.

Projetar fronteira de transporte testável e revisar cenários antes de executar. Não alterar o executável oficial para induzir retorno 7; usar testes comportamentais independentes e falhas legítimas quando apropriado. Não regenerar os auxiliares retidos como “novo” executável para escapar do bloqueio. Registrar cobertura perdida/substituída e lacunas restantes com clareza.

## 7. Overlay e aceite em jogo

Requisitos aceitos:

- Priorização automática do jogo em tela cheia, com seleção manual disponível.
- Métricas em tempo real durante monitoramento e captura.
- Pequeno: FPS médio, 1% low em FPS, tempo médio por quadro em ms e P99 em ms. O checkout pode conter opção posterior de FPS atual/médio; preservar configuração já aprovada.
- Médio: mesmas métricas e gráfico de FrameTime; atual laranja contínuo e referência azul tracejada quando disponível.
- Seletor Pequeno/Médio no overlay, alteração imediata preservando dados, processo e referência.
- Mover/Travar; arraste livre inclusive entre monitores; métricas travadas permitem passagem de cliques ao jogo; controles continuam clicáveis.
- Persistência por jogo; reposicionamento para continuar visível após mudança de monitores/resolução.
- Atualizações não roubam foco. Configuração Overlay/Atalhos deve abrir a qualquer momento.
- Preservar aparência, atalhos, transparência/escala e comportamento de salvar/cancelar já implementados.

Após gate elegível aprovado, fazer roteiro curto: selecionar jogo; observar métricas ao vivo; capturar 30 segundos e guardar referência; repetir mesma cena; conferir curvas/hover/valores; cancelar outra captura; recapturar; alternar tamanho; mover/travar; conferir cliques e foco; abrir configurações durante coleta. Validar DPI físico e múltiplos monitores quando houver equipamento. Marcar indisponibilidade de laboratório como pendência, não aprovação.

O usuário já realizou testes anteriores de captura/comparação/cancelamento/recaptura e aceitou o visual. Não invalidar esses aceites; a nova revisão requer somente verificação proporcional às mudanças e às lacunas ainda abertas.

## 8. Kaspersky: incidente e alcance do bloqueio

### O que foi detectado

`PresentMonHarness.exe` é um executável interno produzido pelo compilador C# para testes. `MonitorHarness.exe` é outro auxiliar interno; não foi compilado na rodada que parou antes de sua etapa. Nenhum deles é produto Intel ou coletor real do runtime. Autoria individual não estabelecida pelos registros consultados.

Fontes/geradores antigos preservados:

- `tests/PresentMonHarness.cs`
- `tests/MonitorHarness.cs`
- `tests/Test-Fase7-R3.2.84-PresentMon.ps1`
- `tests/Test-Fase7-R3.2.84-Monitor.ps1`
- Variante histórica R3.2.83 do teste PresentMon.

Os auxiliares eram gerados em `%TEMP%\winslim-pm-regression-<GUID>` e `%TEMP%\winslim-monitor-harness-<GUID>` usando `csc.exe`, fontes internas e classes de produção.

### Evidências históricas

- Incidente `AV-20261021-001`.
- Ocorrência original: 21/10/2026 às 15:03:27 local. Arquivo original ausente; SHA-256 original desconhecido.
- Recorrência: 22/10/2026 às 06:58:39 local; execução negada pelo Kaspersky.
- SHA-256 da nova geração de 22/10: `b1cd7b2617e6cda191d3d01b053ecca38316b26dfd9caced2093f0438236e1d6`.
- Detecção exibida: `VHO:Trojan-PSW.Win32.Disco.gen`.
- Gate daquela rodada: 15 suítes aprovadas, uma falha, nove não executadas. Não usar como resultado da rodada atual.
- Responsável considera falso positivo; isso foi documentado como avaliação dele. Não há parecer do fabricante nem protocolo de envio confirmado nesta documentação.

O usuário buscou ajuda para submissão ao suporte Kaspersky/OpenTIP. A consulta por hash mostrou classificação Malware; pesquisar hash não equivale a solicitar reanálise. Não afirmar que algo foi enviado sem protocolo/evidência.

### PresentMon oficial verificado separadamente

Em 22/10/2026, atualização Kaspersky às 19:55:52 e scan do oficial concluído às 19:55:53 local: um objeto OK, zero detecções, suspeitas, ignorados ou erros. Proteções ativas antes/depois; capturas oficiais sem bloqueio observado. Isso é resultado dessas verificações, não garantia universal nem resolução do caso dos harnesses.

### Como prosseguir

Manter evidências originais, não desativar antivírus, não criar exclusões, não restaurar quarentena ou renomear auxiliares para contornar detecção. Essas são as condições de trabalho registradas; não inventar exigência de uma autorização nova a cada mudança independente.

A orientação mais recente é **revisar o alcance técnico do bloqueio após fechar as lacunas**: demonstrar se a família retida está fora do runtime e do fluxo ativo de validação, identificar dependências restantes, registrar a decisão e então atualizar a política quando os critérios forem atendidos. Não remover o bloqueio apenas para obter “verde”; também não assumir que um incidente histórico exige eternamente paralisar componentes independentes já revisados.

Até essa revisão documentada, o estado é: família retida, gate completo, publicação e produção bloqueados. Não declarar o incidente resolvido por um scan limpo do binário oficial.

## 9. Edge: preservar o que já foi concluído

31 contratos Edge concluídos com backend real, backup, Apply/Verify, reconhecimento em `edge://policy` e Undo exato na VM. Oito IDs previamente aceitos: 003/004/005/006 e 019/020/024/025. Os 23 restantes foram validados em sete lotes; 276 arquivos de evidência conferidos antes de restaurar baseline.

Não repetir os 31 lotes sem regressão relacionada. 975 verificações simuladas novas, 125 de Apply e 28 do coletor pertencem às rodadas relatadas; não somar com testes físicos como se fossem uma única aprovação.

Versão observada: Edge 155.0.4283.62. EDGE-014/015 estão depreciados e liberados apenas até a versão 155 revisada. Acima disso, revisar compatibilidade; não forçar liberação. EDGE-018 tem efeito condicionado a OptionalData; EDGE-021 depende de perfil Entra. Reconhecimento da política não prova esses efeitos.

Pendente: **interação pela interface do Win-Slim**, especialmente seleção/dependência, prévia, cancelamento sem escrita, Apply e restauração acionados pela UI. Roteiro existente usa lote pequeno EDGE-006/007 e inspeção das notas dos itens condicionais/depreciados.

O roteiro cita `AGENTS.md`: `Iniciar-Validacao.bat` é o ponto de entrada de aceite técnico, com gate completo, diagnóstico e abertura após sucesso. Confirmar instrução vigente no checkout. Não executar candidata antiga diretamente para simular cumprimento do pipeline.

Somente VM para ajustes reais Edge. Edge do host permaneceu intocado. Coletar logs/backups/capturas e verificar hashes no host **antes** de desligar/restaurar baseline. Em falha, preservar estado para diagnóstico.

## 10. Ambiente host e VirtualBox

Hardware atual confirmado para este trabalho: **AMD Radeon RX 480 8 GB**. Menções antigas à RTX 3080 Ti referem-se ao histórico e não representam o laboratório atual. Não há hardware NVIDIA disponível para aprovação física.

| Item | Valor conhecido |
| --- | --- |
| VirtualBox informado | 7.2.20r175154; conferir instalação atual |
| Executável host | `C:\Program Files\Oracle\VirtualBox\VBoxManage.exe` |
| VM | `teste win-slim-win11` |
| UUID VM | `b71b4588-2e83-461c-9585-64ee77b9c851` |
| Windows convidado | Windows 11; confirmar build real, não inferir pelo nome da ISO |
| Hostname convidado | `TESTE` |
| Conta convidada | `vboxuser` |
| Snapshot | `WINSLIM_BASELINE` |
| UUID baseline conhecido | `4aa21603-c0b4-4139-9630-1e5d0acaef20`; reconferir antes de restaurar |
| Builds host | `C:\WinSlim-Integracao\Builds` |
| Builds convidado | `\\vboxsvr\WinSlim_Builds`, somente leitura |
| Logs host | `C:\WinSlim-Integracao\Logs` |
| Logs convidado | `\\vboxsvr\WinSlim_Logs`, gravável |
| Área local do convidado | `C:\WinSlim`, `C:\WinSlim\Testes`, `C:\WinSlim\Logs` |
| Integração histórica host | `C:\WinSlim-Codex-VirtualBox-Pacote-Unico\WinSlim-VirtualBox.ps1` |
| Credencial existente | `%LOCALAPPDATA%\WinSlim-Integracao\CredencialVM.xml`, protegida por DPAPI do usuário Windows |

Nenhuma senha está incluída neste handoff. Não imprimir/decriptar credenciais em logs. O XML salvo depende do usuário/máquina; um agente em outro ambiente não ganha acesso por copiar o arquivo.

Último estado documentado: VM desligada, baseline restaurada. Confirmar ao retomar; não assumir que continua assim. Comandos somente leitura no host:

```powershell
$vm = 'teste win-slim-win11'
$vbox = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
& $vbox showvminfo $vm --machinereadable
& $vbox snapshot $vm list
```

Lições da integração anterior: sempre usar caminho correto do script; variáveis não persistem em outra sessão PowerShell; progresso em stderr do VBoxManage não é por si só falha; avaliar exit code; compor caminho completo de copyfrom como argumento único; prontidão do GuestControl não é equivalente a desktop pronto/UAC aprovado; preservar logs antes da restauração. Essas falhas foram corrigidas em rodadas anteriores, verificar regressão antes de reimplementar.

Scripts isolados Edge citados no histórico: `Inspect-WinSlimEdgeVm.ps1`, `Invoke-WinSlimEdgeIsolatedVm.ps1`, `Test-WinSlimEdgeRealVm.ps1`. Localizar no checkout; não inventar parâmetros. O controlador genérico pode executar gate inteiro/copiar builds e não deve ser usado sem revisar seu escopo.

## 11. Limitador: estado real, não função concluída

Modelo por jogo: 64 verificações comportamentais, transições somente em memória. Não é prova de limitação física de FPS.

NVIDIA: adaptador somente leitura, 114 verificações de fixtures/ABI. No host AMD, resultado esperado `Unavailable / DriverLibraryMissing`, sem carregar driver NVIDIA. Leitura física de sucesso pendente por falta de hardware. Não instalar driver NVIDIA na RX 480. Não há aprovação de setters, Save, perfis reais ou integração final do limitador.

AMD: revisão de ADLX/FRTC/Chill e ADL legado, fontes oficiais fixadas e inspeção estática das DLLs instaladas. Nenhuma DLL carregada nessa revisão; presença de export/assinatura não confirma capacidade.

Próxima etapa AMD, após a prioridade atual: fechar licença/ABI e leitor restrito. ADLX consultado por GPU não estabelece controle por executável. ADL legado global também não representa limite por jogo. Faltam contrato de propriedades, identidade, herança, ausência versus override e Undo exato. Não usar alteração global ao mudar foco nem chaves especulativas como substituto.

Não classificar licença ADLX como MIT sem revisão; não copiar DLLs de driver para distribuição por conveniência. O documento AMD detalha ABI, booleano C de um byte, convenções de chamada, referências e limpeza. Consultá-lo antes de programar binding.

## 12. Sequência operacional recomendada

1. **Confirmar estado local:** instruções, Git/diff, retomada, cronograma, escopo, incidentes e catálogo. Verificar alterações após 22/10; este handoff não as substitui.
2. **Fechar lacunas PresentMon:** testes de transporte/preview com cobertura explícita, preservando funções e sem executar família retida.
3. **Revisar bloqueio:** provar composição do runtime e do gate atual; documentar decisão e dependências remanescentes. Atualizar política apenas quando critérios estiverem atendidos.
4. **Gate atual completo + WPF:** a última retomada prevê 25 suítes; conferir catálogo atual e justificar qualquer mudança. Não somar execuções antigas para declarar gate atual aprovado. Corrigir mensagem genérica de suíte que possa confundir aprovação parcial com integral, se ainda existir.
5. **Preparar candidata identificada:** versão/commit ou identidade de árvore, manifestos, hashes e origem de dependências. Testar o conteúdo efetivamente empacotado. Pacote runtime exclui ferramentas/testes/harnesses não autorizados; validação tem pacote próprio.
6. **Aceite físico PresentMon/overlay no host:** roteiro da seção 7, coleta e configurações, com Kaspersky ativo.
7. **Aceite Edge UI na VM:** roteiro existente, lote pequeno, evidências e restauração após coleta.
8. **Continuar cronograma:** CI Windows hospedada, efeitos condicionais e limitador conforme dependências/hardware. Não lançar incompleto por mudança unilateral do escopo.

Critério de pausa: falha real, nova detecção no componente executado, perda de evidência necessária, incompatibilidade do ambiente ou dependência indispensável indisponível. Registrar causa e próximo passo concreto; continuar trabalho independente autorizado quando possível.

## 13. Documentos e evidências que o agente deve consultar

Todos os caminhos abaixo são relativos à raiz Windows do projeto, salvo indicação contrária. Confirmar existência; não reconstruir conteúdo por nome.

| Documento | Finalidade |
| --- | --- |
| `RETOMADA-R3.2.84-AV.md` | Estado atual único e histórico separado |
| `docs/PRESENTMON-OFICIAL-INTEGRACAO-R3.2.84.md` | Provedor, fluxos, identidade, testes e lacunas |
| `docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md` | Ordem de execução vigente |
| `docs/AV-RECORRENCIA-20261022-R3.2.84.md` | Recorrência e hash da amostra nova |
| `docs/DECISAO-RESPONSAVEL-AV-20261021-001.md` | Avaliação e autorização do responsável |
| `docs/INCIDENTE-KASPERSKY-R3.2.84.md` | Registro histórico inicial |
| `docs/REVISAO-ESTATICA-HARNESS-R3.2.84.md` | Revisão estática e limites das conclusões |
| `docs/CONCLUSAO-EDGE-R3.2.84.md` | Conclusão backend dos 31 contratos |
| `docs/ESTADO-CATALOGO-EDGE-R3.2.84.md` | Matriz por ID |
| `docs/ROTEIRO-ACEITE-EDGE-UI-R3.2.84.md` | Aceite de interação pendente |
| `docs/LIMITADOR-SDK-ABI-LEITURA-R3.2.84.md` | Leitor NVIDIA e limites |
| `docs/LIMITADOR-AMD-RX480-R3.2.84.md` | Revisão AMD, licenças, ABI e condições |
| `logs/presentmon-official-20261022/` | Evidências da coleta oficial |
| `logs/av-owner-review-20261022/` | Decisão, recorrência e material de envio |

Os relatórios registram 1.376 arquivos de evidências anteriores conferidos na última rodada. Não apagar ou regenerar para substituir histórico. Resultado de execução nova deve ficar em coleção nova, com identidade, data/hora/fuso, comando, exit code e hashes quando aplicável.

### O que não está disponível neste handoff

Código-fonte completo, binários, todos os logs, commit atual, plano integral de todas as fases futuras, credenciais e resultado de testes posteriores a 22/10. Os anexos são documentação e não substituem o checkout. Solicitar apenas o que faltar após inspeção do ambiente.

## 14. Como registrar cada próxima entrega

Atualize a retomada canônica com estado atual e histórico separado. Informe ao responsável:

1. Problema corrigido e comportamento resultante.
2. Arquivos alterados e identidade da revisão.
3. Verificações executadas, resultado e evidência.
4. Limitações: simulação, desktop, jogo, UI ou hardware.
5. Estado do gate, incidente, candidata e produção separadamente.
6. Próxima ação automática e eventual ação manual exata do usuário.

Evitar relatório extenso de comandos sem conclusão e evitar uma nova rodada de documentação que não avance um critério de aceite. Documentação deve acompanhar a implementação e validação.

## 15. Prompt de entrada para o novo agente

> Leia este handoff, AGENTS.md e a retomada atual no checkout. Confirme branch/diff e alterações posteriores ao último relatório antes de editar. Continue pela cobertura de falhas de transporte/preview do PresentMon oficial. Preserve o acabamento visual, as fórmulas e os aceites Edge. Não regenere os harnesses retidos. Depois revise tecnicamente o alcance do bloqueio e, quando os critérios documentados permitirem, execute o gate completo atual + WPF e prepare a candidata para aceite em jogo e Edge UI na VM. Avance automaticamente entre etapas aprovadas, corrigindo falhas antes de prosseguir. Registre resultados reais sem equiparar fixtures a validação física. A produção ainda não está aprovada.

## 16. Anexos documentais integrais

Os anexos a seguir são cópias dos dois relatórios mais recentes enviados pelo usuário, conservadas como registro de 22/10/2026. Links relativos dentro deles referem-se ao projeto de origem. Se o checkout contiver versão posterior, use-a como estado atual e preserve estas cópias como histórico.


---

### Anexo A — Retomada recebida

```markdown
# Retomada R3.2.84 — estado atual único

22/10/2026. [Cronograma](docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md), [escopo](release/escopo-R3.2.84.json). Este resumo substitui prioridades históricas, sem reclassificar aceites antigos.

## Estado atual

| Frente | Comprovado / concluído | Pendência e próximo passo |
| --- | --- | --- |
| **Coleta PresentMon oficial** | Runtime antes e depois: **console oficial 2.6.0 x64**, sem serviço adicional. Release/asset/hash conferidos, assinatura Intel válida, MIT/avisos preservados. Caminhos internos agora exigem provedor canônico/hash | [Relatório, origem e arquivos](docs/PRESENTMON-OFICIAL-INTEGRACAO-R3.2.84.md). Nenhum harness é coletor real; fontes/geradores retidos permanecem intactos e sem execução |
| Testes de dados e integração | **36 + 20 verificações determinísticas**, somente classes de produção em DLL sem Main. Oficial isolado: ETW real, 969 linhas; integrado: **9 verificações**, duas capturas de 10 s (610/605 intervalos), cancelar/recapturar, referência preservada, parar/reiniciar | Integração real do backend com **desktop/dwm.exe**, não aceite físico de um jogo ou de cliques na UI. Lacunas: falhas forçadas do processo/preview externo e pressão hostil de pipes do SO; fontes antigas preservadas, sem aprovação inferida |
| Kaspersky — binário oficial | Atualização **19:55:52 local** concluída; scan oficial **19:55:53**, **zero detecções/erros/ignorados**; proteções ativas antes/depois. Capturas oficiais concluíram sem detecção observada | Resultado circunscrito ao binário oficial e a essas execuções; não resolve a ocorrência dos auxiliares nem constitui parecer do fabricante |
| **Edge — 31 contratos** | **Concluídos contratos/backend real/Apply/Verify/reconhecimento no navegador/Undo exato na VM.** Oito aceites originais + 23 IDs em sete lotes; nada reaplicado nesta rodada. Evidências preservadas, baseline restaurada, VM desligada | [Conclusão](docs/CONCLUSAO-EDGE-R3.2.84.md), [31 IDs](docs/ESTADO-CATALOGO-EDGE-R3.2.84.md). Não repetir sem regressão relacionada. Host não configurado |
| Edge — UI e efeitos condicionais | [Roteiro UI preparado](docs/ROTEIRO-ACEITE-EDGE-UI-R3.2.84.md); reconhecidas no Edge 155.0.4283.62 | UI ainda depende de gate completo antes de abrir na VM. Efeitos 018/OptionalData, 021/Entra e outras condições continuam sem aceite. 014/015 depreciadas: revisão acima de 155; não forçar liberação |
| Overlay/UI/estatísticas | Aceites visuais do usuário/P4 preservados; layout/settings/seleção e fórmulas intactos. **Build/self-test WPF passaram**, mais **82 verificações do overlay + 118 de configurações**. DPI 100/125/150 simulado, 15 PNG de configurações | Isso não é novo aceite físico de foco/cliques/atalhos, sensores, DPI ou múltiplos monitores. Executável local recompilado; nenhuma candidata ZIP publicada |
| **AV-20261021-001 histórico** | Responsável avalia falso positivo; autorização local anterior e recorrência **22/10 06:58:39** preservadas separadamente. Hash da nova geração **b1cd7b2617e6cda191d3d01b053ecca38316b26dfd9caced2093f0438236e1d6**; original de 21/10 desconhecido | Família PresentMonHarness/MonitorHarness retida, sem recompilar/renomear/restaurar quarentena. Sem parecer do fabricante. [Ocorrência](docs/AV-RECORRENCIA-20261022-R3.2.84.md), [decisão do responsável](docs/DECISAO-RESPONSAVEL-AV-20261021-001.md) |
| **Gate / distribuição / produção** | Segurança/22 testes inertes do empacotador passaram. `Validar-Regressoes.bat` retornou **1 / Security hold antes das suítes**, sem gerar auxiliares | **Gate completo, publicação e produção permanecem bloqueados.** Fechar lacunas/revisar escopo, depois gate fresco de 25 suítes + WPF. CI e aceites reais restantes pendentes; resultados isolados não somam uma aprovação integral |
| Limitador — SDK/ABI e leitura NVIDIA | Adaptador somente leitura preservado; oito textos oficiais fixados, 114 verificações anteriores de fixtures/ABI; sem Set/Save/integração no aplicativo | **Leitura física NVIDIA pendente por falta de hardware.** Host confirmado RX 480 8 GB; não instalar NVIDIA. Comparação ctypes/.NET não equivale a chamada física/C++ |
| AMD RX 480 — revisão | Revisão oficial FRTC/Chill/ADLX/ADL e 13 textos fixados concluídos, inventário estático de DLLs/exports sem carga | Suporte físico não confirmado. Próximo item do limitador: licença/ABI e leitor restrito. Sem escrita por jogo até contrato de perfis/herança/Undo; preservar prioridade atual da coleta |

## Próxima ação e critérios do gate

1. Concluir cobertura independente para falhas do transporte/preview e pressão de pipes, sem recriar os coletores artificiais bloqueados. Parser, métricas, estado e transporte normal oficial já têm resultados separados, não aprovação completa.
2. Registrar revisão de escopo do gate a partir dessa cobertura e da recorrência histórica. A captura oficial sem alerta não é resolução do incidente dos harnesses. A política continua bloqueando a família, o gate, a publicação e a produção; não foi contornada para executar a UI.
3. Após decisão técnica documentada, executar gate novo de todo o cadastro e WPF, sem aprovar resultados parciais. Executar aceite em jogo e roteiro Edge UI somente no ambiente/fluxo autorizados. CI/efeitos condicionais seguem critérios próprios.
4. Antivírus ativo; sem exclusões, desativação, envio automático ou quarentena restaurada. Evidências originais e os dois hashes de amostras distintas continuam identificados corretamente. **1.376 arquivos de evidências anteriores conferidos** nesta rodada.

## Histórico preservado — separado do estado atual

- [Estado anterior à integração oficial PresentMon](docs/historico/RETOMADA-R3.2.84-AV-antes-integracao-presentmon-oficial.md): decisão do responsável, execução controlada e nova detecção; 15 passaram/1 falhou/9 não executadas, em rodada anterior de 25 suítes.
- [Antes da avaliação do responsável](docs/historico/RETOMADA-R3.2.84-AV-antes-decisao-responsavel.md), [antes da revisão AMD](docs/historico/RETOMADA-R3.2.84-AV-antes-revisao-amd.md), [antes do SDK/leitor](docs/historico/RETOMADA-R3.2.84-AV-antes-retomada-limitador.md).
- [Antes da conclusão Edge](docs/historico/RETOMADA-R3.2.84-AV-antes-conclusao-edge.md), [antes do catálogo Edge](docs/historico/RETOMADA-R3.2.84-AV-antes-catalogo-edge.md). [Quatro IDs originais](docs/EDGE-VM-ISOLADO-R3.2.84.md), [quatro seguintes](docs/EDGE-CATALOGO-PROXIMO-LOTE-R3.2.84.md), [23 adicionais](docs/CONCLUSAO-EDGE-R3.2.84.md).
- [P8](RETOMADA-R3.2.84-P8.md), [P7](RETOMADA-R3.2.84-P7.md), [P4](RETOMADA-R3.2.84-P4.md). Contagens/prioridades históricas não substituem este quadro.
```


---

### Anexo B — Integração oficial recebida

```markdown
# PresentMon oficial — provedor real e validação separada

22/10/2026. Trabalho autorizado de coleta e validação, sem publicação de candidata ou aprovação de produção. Evidências novas em `logs/presentmon-official-20261022/`; evidências anteriores do AV e do Edge preservadas.

## Inspeção: antes e depois

**O runtime já usava o console oficial PresentMon 2.6.0 x64, fixado por SHA-256.** Não foi encontrado uso de MonitorHarness ou PresentMonHarness como provedor real. A mudança mantém esse provedor, fecha entradas internas que aceitavam outro executável e separa testes de dados dos testes com ETW real.

| Caminho | Antes | Depois |
| --- | --- | --- |
| Monitoramento contínuo | `MainWindowController` → `PresentMonMonitor.StartAsync` → console oficial, stdout CSV | Mesmo fluxo; identidade oficial também exigida em `StartCore` |
| Benchmark da UI | `PresentMonMonitor.RecordAsync` usa a sessão contínua já existente | Mesmo fluxo; cancelamento da gravação preserva monitor e resultado anterior |
| API de benchmark isolado | `PresentMonBenchmark.CaptureAsync` inicia monitor oficial e encerra sua própria sessão | Mesmo fluxo; verificação de identidade centralizada |
| Overlay | Snapshots de `BenchmarkLiveReader`, atualização pela UI; não inicia outro coletor | Preservado, fontes visuais e de preferências intactas |
| Entrada antiga `CaptureCore` | Aceitava caminho arbitrário, usado pelos antigos testes de processo simulado | Exige caminho canônico e hash oficial antes da execução; não usada pela UI |
| Testes determinísticos | Dois executáveis internos simulavam o protocolo do coletor | CSV/estado/TextReader em memória, somente três classes de produção compiladas como DLL sem `Main` |
| Integração real | Não demonstrada pelo sucesso dos simuladores | Console oficial verificado e escaneado, ETW real isolado e integrado ao backend de coleta |

As definições de média, 1% low, P99, janelas temporais e redução visual por máximos não foram alteradas. A seleção automática/manual, referência, cores/tracejado, posições e configurações continuam nas mesmas classes da UI. O teste integrado chama as classes reais de coleta; não equivale a clicar na interface ou observar o overlay sobre um jogo.

## Origem dos auxiliares

`tests/PresentMonHarness.cs` e `tests/MonitorHarness.cs` são fontes internas de teste do Win-Slim. Não são produtos oficiais da Intel/PresentMon, não têm release externa usada pelo projeto e não são baixados como coletores. A análise local não identifica um autor individual com autoridade para representar um fabricante desses auxiliares.

| Auxiliar | Gerador preservado | Compilação e execução |
| --- | --- | --- |
| PresentMonHarness.exe | `tests/Test-Fase7-R3.2.84-PresentMon.ps1`; variante histórica R3.2.83 | `csc.exe` do .NET Framework, três fontes de produção + `tests/PresentMonHarness.cs`; `%TEMP%\winslim-pm-regression-<GUID>\PresentMonHarness.exe`; o próprio script executava o resultado |
| MonitorHarness.exe | `tests/Test-Fase7-R3.2.84-Monitor.ps1` | Mesmo compilador/três classes + `tests/MonitorHarness.cs`; `%TEMP%\winslim-monitor-harness-<GUID>\MonitorHarness.exe`; o script executava o resultado |

Os fontes e geradores antigos continuam intactos e bloqueados. Não foram recompilados, renomeados ou regenerados nesta rodada. O cadastro dos mesmos IDs `REG-PRESENTMON-001` e `REG-MONITOR-001` agora aponta para os novos testes de dados; mantém os identificadores de bugs antigos. A DLL nova não inclui nenhum dos dois fontes de teste, ponto de entrada ou coletor artificial. Proveniência de compilador/fontes/saída é registrada antes da carga.

Não há esses executáveis na lista do build de produção. A inspeção de distribuição anterior e o empacotador distinguem pacote técnico de validação de runtime: este proíbe `tests`, `tools`, fontes, nomes de harness e binários não autorizados. Nenhum ZIP novo de aplicativo foi montado nesta rodada; as candidatas históricas não são liberadas por este relatório.

## Binário oficial verificado

- Caminho: `D:\Desktop\winslim_fase7_r3_2_84\third_party\PresentMon\PresentMon-2.6.0-x64.exe`.
- [Repositório oficial](https://github.com/GameTechDev/PresentMon), [release v2.6.0](https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0), [asset oficial](https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe), asset ID **579508526**, publicação **21/09/2026 17:30:36 UTC**.
- SHA-256 **b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af**, **980.320 bytes**. Coincidem arquivo incorporado, download novo e digest informado pelo GitHub. O binário incorporado não precisou ser substituído.
- Licença MIT em `third_party/PresentMon/LICENSE.txt`; avisos de terceiros e documentação preservados. Metadados atualizados em `provenance.json`.
- Authenticode consultado nesta máquina: **Valid**, titular **Intel Corporation**, thumbprint **BF07AF4995EFFDB3CAA3466D6AB616136A1762CC**; carimbo de tempo Sectigo Public Time Stamping Signer R37. Evidência: `binary-before.json`. Isto registra a verificação efetiva, não uma suposição baseada no nome do arquivo.
- Recursos FileVersion/ProductVersion estavam ausentes. A versão **2.6.0** foi identificada pela release, hash e banner real de `--help`; não inventada a partir desses recursos. Nesta release, `--help` escreve em stderr e retorna 1; captura continua exigindo código 0 e quadros válidos.

## Escolha do console

As quatro métricas do produto usam intervalos de apresentação `MsBetweenPresents`. O console oficial fornece CSV por stdout em tempo contínuo, seleção por PID e sessão ETW própria. O [README oficial fixado em v2.6.0](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md) e as fontes oficiais [CommandLine.cpp](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/PresentMon/CommandLine.cpp) / [CsvOutput.cpp](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/PresentMon/CsvOutput.cpp) sustentam esse caminho: `--output_file` tem precedência sobre stdout, e o modo stdout envia linhas durante a captura.

Escolha mantida: **console, sem serviço/API adicional**. O monitor usa `--output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_display --no_track_input`, PID explícito e `WinSlim-<GUID>` exclusivo. Isso atende às métricas e à atualização contínua atuais, sem instalar serviço/driver, duplicar coleta ou exigir SDK para distribuição. Sensores opcionais continuam em seu provedor separado. Não há promessa universal para todo jogo/API/modo protegido; permissões ETW e renderização do processo continuam requisitos do teste real. Nenhuma autoelevação foi acrescentada.

## Cobertura e limites

| Comportamento | Verificação atual | Alcance |
| --- | --- | --- |
| Parser, média/1% low/P99, PID/nome/cadeias separados, CSV inválido/ausente, comparação | `Test-Fase7-R3.2.84-PresentMonData.ps1` | **36 verificações passaram**, dados determinísticos; sem ETW/processo coletor |
| Picos do gráfico, linha parcial/truncada, janela 5 s, FPS atual 1 s, obsolescência e limite de amostras | Mesmo teste, classes de produção | Incluído nas 36; estatísticas usam conjunto completo |
| Benchmark independente do monitor, cancelar/recapturar, concorrência, resultado anterior, perda de fluxo | `Test-Fase7-R3.2.84-MonitorData.ps1` | **20 verificações passaram**, produção alimentada por dados; mais fixtures de sensores opcionais |
| Leitura incremental stdout e stderr grande, linha malformada/truncada/>64 KB | Mesmo teste, métodos TextReader usados pelo transporte real | CSV > buffer de pipe e 200.000 caracteres de erro drenados em memória, diagnóstico retido limitado a 4.096; não é ensaio de pressão de pipes do SO |
| Hash/caminho interno inválidos e sessão de parada alheia/global | Teste de dados PresentMon | Rejeição antes de lançar processo. Falha anterior de `StartCore` demonstrada em `data-before-hardening-02.log` com caminho inexistente, sem executar auxiliar |
| Console oficial isolado | `Invoke-WinSlimOfficialPresentMonProbe.ps1`, `isolated-probe-04/result.json` | Captura ETW real de 3 s, saída 0, **969 linhas** de processos do desktop; não é aceite em jogo |
| Backend integrado de produção com console oficial | `Test-WinSlimOfficialPresentMonIntegration.ps1`, `integrated-final/result.json` | **9 verificações passaram**: métricas antes do benchmark, duas capturas reais de 10 s, cancelar sem perder monitor, comparar sem alterar referência, parar/reiniciar e cancelar API isolada |
| UI/seleção/overlay/preferências | Suíte nativa, build e self-test WPF passaram; testes de overlay e configurações separados | **82 + 118 verificações passaram**; configurações em 100/125/150% simulados, 15 PNG. Fixtures/layout não equivalem a aceite físico |
| Saída forçada 7 do processo, falha de preview externo e pressão simultânea hostil em pipes do SO | Fontes/cenários antigos preservados; **não repetidos com auxiliares** | Lacunas explícitas. Não forçar código de saída do binário Intel por substituição de executável; fechar com seam de transporte testável/revisado e teste de falha legítima do oficial antes de aprovação completa |

As falhas de desenvolvimento do runner isolado também ficaram preservadas: binding de Root, stderr informativo de help e código 1 de help, todos anteriores à primeira captura aceita. O código 1 de help não foi estendido a capturas nem tratado como detecção AV. A primeira integração passou; após extrair os leitores para fixtures, a integração foi repetida sobre a versão final, com nova sessão. Não se repetiram lotes Edge na VM.

## Kaspersky e incidente histórico

Proteções **Protection, File_Monitoring, HvmMonitorTask e AMSI** estavam `running` antes e após os testes. Atualização normal concluiu em **22/10/2026 19:55:52 local (UTC−03)**, saída 0/sem erro. Scan explícito do binário oficial, em modo somente relatório, iniciou **19:55:52**, terminou **19:55:53**, saída 0: **1 objeto OK, 0 detecções, 0 suspeitas, 0 ignorados, 0 erros**. Relatórios integrais em `kaspersky-update.txt`, `kaspersky-official-scan.txt` e exports posteriores dos três componentes.

As capturas oficiais isolada/integradas concluíram sem lançamento negado ou detecção observada nesses arquivos. A execução integrada final terminou **20:06:05 local / 23:06:05 UTC**, com **610 e 605 intervalos válidos** nas duas capturas de 10 s de `dwm.exe`, PID 1584. Os números comprovam transporte/cálculo reais do desktop, não ganho de desempenho ou funcionamento de um jogo específico. A referência anterior teve hash conferido após cancelar e recapturar.

**Isso não resolve AV-20261021-001.** A avaliação de falso positivo continua atribuída ao responsável, sem parecer do fabricante. A ocorrência de 22/10 06:58:39, SHA **b1cd7b2617e6cda191d3d01b053ecca38316b26dfd9caced2093f0438236e1d6**, pertence ao PresentMonHarness recém-gerado naquela rodada; SHA original de 21/10 continua desconhecido. Nenhum desses arquivos foi executado nesta continuidade. Sem exclusões, desativação, restauração de quarentena, envio ao fabricante ou renomeação para evitar alerta.

Revisão de alcance: fixtures de dados e captura oficial são independentes e foram autorizadas/executadas; **família retida, gate completo, publicação e produção permanecem bloqueados**. A migração não transforma lacunas de falha/pressão em aprovação. A política continua recusando o gate antes da compilação dos auxiliares; os testes de segurança verificam isso com cópias inertes dos pontos de entrada. O fabricante não analisou o incidente por inferência deste teste do binário oficial.

`REG-SECURITY-001` passou nesta rodada, incluindo **22 testes inertes do empacotador**, sem gerar/executar a família retida. `Validar-Regressoes.bat` foi chamado e retornou **1, Security hold**, antes das suítes: `logs/regressao-20261022-230933-944-a97d37e8/resultado.json`. Isso é **bloqueio esperado, não gate aprovado nem uma nova detecção**. O texto genérico “GATE TECNICO ... APROVADO” no log da suíte NativeUI designa somente aquela suíte isolada; a abertura recomendada pelo texto padrão não foi seguida.

## Arquivos e próxima execução

Runtime alterado somente em `PresentMonBenchmark.cs` e `PresentMonMonitor.cs`: verificação do provedor, alimentação/finalização de estado e extração dos leitores sem alterar as fórmulas. Novos scripts: dois testes `*Data.ps1`, `tools/validation/WinSlimCaptureData.ps1` e os dois runners em `tools/integration/`. Cadastro, proveniência oficial, baseline atual, escopo, cronograma e retomada atualizados; executável da UI recompilado para verificação local, sem ZIP publicado. Fontes de layout/overlay/settings, estatísticas e auxiliares permanecem intactas.

Próximos passos concretos:

1. Fechar as lacunas de falha de transporte/preview com testes comportamentais independentes, sem produzir variante dos auxiliares retidos, e registrar a decisão de escopo antes de retomar o gate completo. A investigação histórica do AV conserva seu próprio fluxo de análise manual.
2. Depois de gate novo + WPF aprovado no escopo revisado, executar aceite em jogo: seleção automática/manual, quatro métricas, Médio com referência, cancelar/recapturar, alternar tamanho/mover/travar e configurações sem reiniciar coleta. Foco, cliques, DPI físico, sensores e múltiplos monitores continuam sem novo aceite.
3. Preservar 31 contratos/aceites backend Edge; roteiro UI na VM ainda depende da abertura pelo pipeline. CI e aceites restantes continuam condições da produção. Limitador AMD/NVIDIA não foi modificado nesta rodada.
```
