# R3.2.83 — fluxo de candidata e benchmark PresentMon

## O que mudou

- Um comando de aceite técnico: Iniciar-Validacao.bat. Executa todo o cadastro, compila e testa WPF, gera diagnóstico e abre o aplicativo depois de sucesso completo. Falha impede essa abertura. O launcher normal continua disponível para uso habitual.
- Dez suítes que a interface repetia agora são delegadas ao harness na execução integrada. Todas continuam cadastradas e obrigatórias, inclusive quando a suíte nativa falha; o modo isolado da suíte nativa mantém os testes internos completos. Não foi introduzido cache que reaproveite aprovações de outra versão.
- Coletar-Diagnostico.bat reúne evidências em um ZIP, inclusive após aplicar/restaurar, sem repetir as regressões. O ZIP é local: nenhum dado é enviado automaticamente.
- CI Windows preparada em .github/workflows/windows-candidate.yml para push, pull request e execução manual. Ao colocar o conteúdo deste pacote na raiz do repositório, o workflow roda o gate e preserva logs. Ele não publica o aplicativo. Ainda não foi executado/instalado no repositório remoto nesta entrega.
- PresentMon opcional incorporado: coletor oficial 2.6.0 x64, SHA-256 fixado, licença MIT e avisos de terceiros preservados. Não é preciso instalar serviço, driver ou sobreposição externa. O botão fica em Análise do Sistema; os indicadores demonstrativos antigos dessa página continuam identificados como demonstração.

## Benchmark incorporado

Escolha um processo já aberto e uma duração de 10 a 120 segundos. O processo de captura roda em segundo plano, fora da thread da interface, usando sessão ETW exclusiva WinSlim-GUID. Cancelamento tenta encerrar somente essa sessão; não usa stop global, não encerra o jogo, não solicita elevação silenciosa e não altera grupos/permissões do Windows. Fechar o Win-Slim solicita cancelamento. O polling do Dashboard pausa durante a captura; fora dela, o coletor fica inativo.

A coleta usa --v1_metrics e MsBetweenPresents, com GPU/display/input tracking desativados neste primeiro módulo. É FPS de apresentação da aplicação: não é contador de quadros efetivamente exibidos, captura de tela ou medição de input lag. Este módulo não incorpora a telemetria de potência/temperatura nem o overlay do serviço Intel PresentMon.

O parser agrupa PID e swap chain separadamente e utiliza o fluxo com mais intervalos válidos. Não soma janelas, processos ou swap chains para fabricar FPS. Intervalos não numéricos, não finitos, zero/negativos ou acima de 120 segundos são ignorados e contados; CSV truncado, colunas ausentes/duplicadas e menos de 30 intervalos válidos são rejeitados. Limites de 256 MB, dois milhões de registros e 256 fluxos limitam o consumo de memória. O gráfico preserva a ordem da captura e mostra até 360 amostras reduzidas; os cálculos usam todos os intervalos válidos do fluxo escolhido.

- FPS médio = 1000 / média dos intervalos em ms.
- P99 = percentil 99 por nearest rank dos intervalos.
- 1% low = 1000 / média do 1% de intervalos mais lentos, arredondando a quantidade para cima.
- Comparação antes/depois exige aplicativo, duração conhecida e métrica iguais. Repita a mesma cena, resolução, opções gráficas e aquecimento; uma única execução não prova ganho. Use várias repetições para reduzir variação.

CSV bruto, stdout/stderr e summary.json ficam em Benchmarks, em pasta exclusiva por execução concluída. Exportar resultado salva JSON, incluindo a referência da sessão. Importar CSV aceita dados compatíveis com MsBetweenPresents e informa versão desconhecida; importação sem duração conhecida não vira referência comparável. Dados cancelados não geram um resultado aceito. Falta de permissão ETW ou ausência de quadros gera erro explícito. Use administrador ou uma conta já autorizada a logs de desempenho; o aplicativo não muda essa autorização.

## Validação concentrada

Comece por COMECE-AQUI.md. A R3.2.83 reúne a R3.2.82; não exige validá-las separadamente. Nenhum novo tweak foi liberado nesta revisão. O lote ainda pendente é EDGE-019 UserFeedbackAllowed=0, EDGE-020 MicrosoftEdgeInsiderPromotionEnabled=0, EDGE-024 AlternateErrorPagesEnabled=0 e EDGE-025 SearchSuggestEnabled=0, todos DWORD em HKLM\SOFTWARE\Policies\Microsoft\Edge. Mínimos locais do Edge: 77/98/80/77. Exigem Windows 10/11 cliente e administrador.

Essas preferências desativam feedback manual, promoção Insider, sugestões web em erros e sugestões web na barra de endereços. Histórico/favoritos locais permanecem; atualizações do Edge não são desativadas. Não prometem FPS. EDGE-019 exige fechar/reabrir o navegador. EDGE-020/024/025 têm limitações em perfis de conta Microsoft; confira aceitação no perfil usado.

Para o lote pendente: importe Teste-Lote-Edge-R3.2.83.json, confira quatro IDs, revise destinos/exclusões, crie backup e aplique. Salve o trabalho, feche/reabra o Edge, recarregue edge://policy e confira os quatro nomes/valores/status. Restaure a cópia Antes da aplicação deste lote, feche/reabra/recarregue novamente. O esperado é o estado real salvo: existente retorna ao valor anterior; ausente volta a ser ausente. Se houver erro, expanda Mostrar mais. A coleta única de diagnóstico inclui os backups para conferir Apply/Undo; não envie cada arquivo separadamente.

Não repetir manualmente UI, QoL e lotes Edge anteriores já aprovados, salvo mudança relacionada ou falha de regressão. O aceite da R3.2.81 continua válido no cenário recebido, com 13 suítes e quatro valores aplicados/verificados/restaurados; não substitui as verificações desta candidata.

## Critérios de produção

O catálogo tem 230 IDs para seleção, mas a aplicação real de Registro está limitada a 35 IDs revisados e à compatibilidade local; outros módulos mantêm suas próprias restrições. Isso não significa 230 otimizações executáveis. O inventário do escopo está em release/escopo-R3.2.83.json. Backup, revisão, Verify/Undo e gates permanecem obrigatórios.

Critérios desta candidata: 16 suítes Windows completas sem falhas; abertura e navegação WPF; aplicação/restauração do lote ainda pendente; captura ETW real, cancelamento e comparação em jogo. Depois, congelar correções, gerar a candidata final e preparar distribuição do escopo aceito. Novas famílias podem seguir em versões posteriores. Não ampliar a lista real apenas para cumprir o número do catálogo.

## Evidência disponível

Linux: seis testes Python do empacotador passaram; JSON/XAML, referências de controles/tema, registro/delegação, hashes e preservação da base foram conferidos. Não há PowerShell 5.1, compilador .NET Framework ou WPF neste ambiente. Compilação C#, 16 suítes Windows, execução de CI e captura ETW real estão PENDENTES. Não foi medido tempo total do novo gate, portanto não se promete fator de aceleração.

REG-PIPELINE-001 testa o harness real com filhos descartáveis: dez suítes executadas uma vez, modo isolado preservado, delegação incompleta rejeitada antes dos filhos, relatórios inválidos/ausentes/falhos rejeitados e ZIP automático sem alterar configurações. REG-PRESENTMON-001 compila coletor simulado junto ao módulo: estatísticas com valores conhecidos, CSV inválido, PID/swap chain, hash ausente/adulterado, stdout/stderr acima do buffer, saída 7, PID reutilizado, cancelamento e comparação incompatível. O self-test WPF cobre a página, estado inicial inativo, navegação, idiomas e temas.

## Referências

- https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0
- third_party/PresentMon/README-ConsoleApplication.md: documentação da versão incorporada.
- third_party/PresentMon/provenance.json: origem e hash do binário.
- https://docs.github.com/en/actions/tutorials/store-and-share-data
