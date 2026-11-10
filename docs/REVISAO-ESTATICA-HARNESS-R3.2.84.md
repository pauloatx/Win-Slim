# Revisão estática complementar — AV-20261021-001

21/10/2026. **Resultado inconclusivo quanto à amostra detectada.** Origem e propósito de teste rastreados; nenhum laudo de falso positivo. Não houve compilação, execução, renomeação ou alteração dos auxiliares nesta continuação. UI e política de bloqueio preservadas. O gate completo e a produção continuam pendentes.

## Escopo e rastreabilidade

Revisão dos quatro fontes do gerador: `tests/PresentMonHarness.cs`, `PresentMonBenchmark.cs`, `PresentMonMonitor.cs` e `BenchmarkLive.cs` em `src/UI/Native/R3_2_84/`; também do gerador PowerShell, do build da UI e do auxiliar similar `tests/MonitorHarness.cs`. As linhas abaixo referem-se à árvore atual, congelada como texto com SHA-256 em [static-review-02](../logs/kaspersky-investigation-20261021/static-review-02/independent-results.json). Os snapshots anteriores permanecem separados e inalterados; não há prova de identidade byte a byte entre eles e o executável removido.

Os relatórios do incidente registram 16 eventos/seis caminhos. No primeiro caminho há detecção às 15:03:27 e iniciador PowerShell; em outro, às 15:07:23, aparece `csc.exe`. Isso sustenta a origem local, mas não revela a linha de comando completa, os módulos carregados, as chamadas executadas ou a regra interna que acionou o antivírus. Presença de código não demonstra sua execução no evento.

## Comportamentos observados nos fontes

| Fato estático e referência | Finalidade observável e limite da conclusão |
| --- | --- |
| Gerador atual, linhas 6–28: política antes da criação da pasta; `csc.exe`, quatro fontes, `/noconfig`, referências explícitas `System.dll`/`System.Core.dll`, saída temporária, registro de hashes e lançamento direto. | O ponto de entrada de validação gera um programa local; não baixa o harness. A política atual impede essa geração. Não comprova quais bytes foram compilados anteriormente. |
| `PresentMonHarness.cs:59–73`: reproduções dedicadas, modo simulado para argumentos `--`, caso contrário suíte. Linhas 66 e 100–121 usam o próprio caminho como coletor em `CaptureCore`. | O teste inicia outros processos do mesmo executável. Não é injeção em um processo de jogo. A simulação não consulta o PID real do jogo nem inicia ETW por conta própria. |
| `PresentMonBenchmark.cs:78–91,95–147`: `UseShellExecute=false`, janela oculta, stdout/stderr redirecionados, leitura assíncrona, esperas, timeout e cancelamento. | Testa o protocolo do coletor e evita bloqueio de pipes. Há criação de processos sem janela; não há comando de shell, `runas` ou autoelevação nesse caminho. |
| `PresentMonHarness.cs:21–56`: CSV sintético, erro 7, PID divergente, flush atrasado, 200.000 caracteres em cada saída, marcadores `.fake-stop`. | Dados artificiais exercitam sucesso, indisponibilidade e cancelamento. O volume é deliberado para verificar pipes. Marcadores comunicam parada entre as cópias. |
| `PresentMonHarness.cs:14,23–28,35–37,56`: `--output_file` e `--session_name` são usados em escrita/combinação de caminhos sem validação própria de confinamento. | O modo simulado confia no chamador local. Argumentos arbitrários poderiam criar/sobrescrever arquivos acessíveis ao usuário, inclusive um marcador fora do temporário se a sessão contiver caminho absoluto ou segmentos relativos. Não foi identificado receptor remoto. Não é uma interface segura para entradas não confiáveis nem prova de exploração no incidente. Os chamadores de teste normais constroem caminhos descartáveis e sessão GUID. |
| `PresentMonHarness.cs:98`: escreve o texto `tampered` em um caminho com nome do coletor e extensão `.exe`. | Fixture para rejeição de hash antes da execução. Não contém payload PE; ainda assim é uma escrita com extensão executável relevante para apresentar ao fabricante. |
| `PresentMonHarness.cs:69,132,146` e `MonitorHarness.cs` no `finally`: exclusão de fixtures/pastas temporárias. | Limpeza de testes. O gerador antigo também removia a pasta externa em falha, prejudicando a prova. Não se pode atribuir a ausência do primeiro objeto exclusivamente ao AV ou à limpeza. Os fontes C# não foram alterados para contornar a detecção. |
| `PresentMonBenchmark.cs:68–90,115–145` e `PresentMonMonitor.cs:99–118`: parada por sessão própria e, se necessário, `Kill()` no objeto de processo criado. | Não foi encontrado encerramento global por nome nem takeover de sessão de terceiros. O método interno de parada confia na sessão construída pelo chamador; não significa validação de toda entrada arbitrária. |
| `PresentMonBenchmark.cs:44–59` e `PresentMonMonitor.cs:51–70`: entrada de produção verifica coletor fixado; métodos internos `CaptureCore`/`StartCore` recebem um binário injetável. | A injeção permite usar a simulação nos testes, sem verificação do hash nesses métodos internos. `CaptureAsync`/`StartAsync` são os caminhos verificados. O harness não é o coletor Intel. |
| `BenchmarkLive.cs:53–130`, `PresentMonBenchmark.cs:169–210`, `PresentMonMonitor.cs:125–150`: leitura incremental/CSV, filtros, limites e gravação local de benchmark. | Não foi encontrada rota de envio dos dados para rede nos quatro fontes. Estatísticas não foram modificadas nem reexecutadas nesta rodada. |

O auxiliar similar `MonitorHarness.cs:12–35` também se relança, escreve marcadores e emite linhas sintéticas; `Main` injeta seu próprio caminho em `PresentMonMonitor.StartCore`, cancela/grava e remove fixtures. Continua bloqueado por precaução de família; não há evento apresentado que prove detecção desse segundo nome.

## Dependências e limites

- O comando do compilador usa as bibliotecas locais do .NET Framework, sem pacote NuGet, DLL privada, recurso externo ou passo de download. `mscorlib` é a referência básica implícita. `/noconfig` evita o arquivo de resposta padrão; não desativa o antivírus.
- Os metadados previamente preservados das três gerações relacionadas declaram apenas `mscorlib`, `System` e `System.Core`, versão de assembly 4.0.0.0; são auxiliares não assinados. Não foram carregados ou executados nesta continuação. Esses metadados não pertencem à amostra exata.
- Foram lidos hashes, versões e assinaturas do compilador e dessas três bibliotecas em `C:\Windows\Microsoft.NET\Framework64\v4.0.30319`. As quatro assinaturas retornaram `Valid / Microsoft Windows`; hashes completos em [framework-metadata.json](../logs/kaspersky-investigation-20261021/static-review-02/framework-metadata.json). Isso identifica os arquivos em disco agora, sem comprovar o conjunto efetivamente carregado às 15:03. Não foi auditado todo o CLR/Windows nem a cadeia transitiva nativa.
- O build da UI enumera fontes de produção explicitamente (`Build-NativeUI-R3.2.84.ps1:35`); não inclui os dois `Main` de teste. A auditoria anterior do ZIP P9 não encontrou harness compilado, inclusive no diagnóstico interno, mas encontrou fontes/geradores que o produzem durante validação. O pacote antigo permanece retido.
- Na leitura dos quatro fontes não foram identificados acesso a credenciais/cookies/perfis de navegador, comunicação de rede, persistência, execução de conteúdo baixado, carga dinâmica de assembly externo, P/Invoke, injeção, instalação de serviço ou driver. A busca textual foi apenas apoio à leitura do fluxo; não constitui teste de ausência ou laudo do binário indisponível. Bibliotecas do framework possuem capacidades mais amplas do que as chamadas usadas aqui.

## Hipóteses, sem atribuição de causa

Compilação/execução em diretório temporário, programa não assinado que se relança, processos sem janela, criação de arquivo `.exe` artificial e limpeza podem ser características consideradas por heurísticas. **Não existe evidência disponível de que qualquer uma tenha causado esta detecção.** Também não há base para deduzir roubo de senhas somente do rótulo `Trojan-PSW`, nem para excluir alteração do objeto original com base nos fontes atuais. O evento com iniciador `csc.exe` permite inclusive a hipótese de detecção na criação/acesso ao arquivo antes do `Main`; a ordem exata não está demonstrada.

Não se justifica modificar esses comportamentos para tentar silenciar o AV. As correções anteriores tratam rastreabilidade, retenção de evidências e distribuição; não removem o alerta nem liberam execução. Eventual endurecimento da interface de simulação deve ser avaliado separadamente e ter regressão comportamental, após resolver a investigação.

## Verificações desta continuação

- Integridade dos **69 arquivos** do manifesto anterior: confirmada. Hash da UI permanece `22EBCDC4F8CC6538CE8820E2F2F6FA7257BE0962BD75817CEA1BCFCD09E328D2`; política e fontes revisados inalterados antes/depois das fixtures.
- `Test-Fase7-R3.2.84-Performance.ps1`: passou; fórmulas, filtros, publicação progressiva, indisponibilidade e falha do callback, com `Get-CimInstance` simulado.
- `Test-Fase7-R3.2.84-OverlaySensors.ps1`: passou; associação de temperatura/dispositivo, VRAM, valores inválidos e provedor ausente sem zeros fictícios, com `Get-CimInstance` simulado.
- Antes dessas execuções, parse estático dos dois módulos importados: zero erros; somente definições de funções no nível superior. Não houve consulta física aos sensores ou alteração de otimização do sistema.
- Logs e resultado: [independent-results.json](../logs/kaspersky-investigation-20261021/static-review-02/independent-results.json). São verificações independentes de fixtures; não significam gate completo, aceite físico, análise AV ou produção aprovada. O gate completo não foi reexecutado nem contornado; continua retido.

Aceite visual do overlay/layout observado permanece separado. Testes funcionais físicos, DPI físico, múltiplos monitores, Edge real somente em VM e CI hospedada continuam conforme as pendências anteriores.

## Material para análise

O pedido antigo afirmava que o primeiro objeto não existia fora do backup protegido. **Essa afirmação excedia a evidência:** há backup para cinco gerações posteriores, sem vínculo comprovado do primeiro objeto com um container. O texto original e seu hash foram preservados. A versão complementar corrige isso e distingue snapshots antigos/atuais.

Usar [ENVIO-MANUAL.md](../logs/kaspersky-investigation-20261021/static-review-02/ENVIO-MANUAL.md) e a pasta `static-review-02/vendor-submission-v2/`. Nada foi enviado. A documentação oficial consultada é a [orientação de revisão de detecções](https://support.kaspersky.com/1870), que descreve envio de objeto/hash e contato com suporte; nenhum hash ou objeto local foi consultado externamente.
