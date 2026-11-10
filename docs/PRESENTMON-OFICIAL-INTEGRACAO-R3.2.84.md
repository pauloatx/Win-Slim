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
