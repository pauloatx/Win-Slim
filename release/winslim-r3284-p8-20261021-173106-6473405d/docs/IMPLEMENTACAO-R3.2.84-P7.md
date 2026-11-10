# P7 — monitoramento contínuo e benchmark compartilhado

Escopo consolidado a partir do pedido anexado à conversa em 21/10/2026. P6, P5 e P4 permanecem preservadas em suas pastas isoladas. FrameTime comparativo e cancelar/capturar novamente da P4 continuam com aceite manual registrado. Edge real continua pendente, exclusivamente na VM. Nenhum ajuste de produção foi aplicado.

## Dados em tempo real

A P6 acompanhava o arquivo CSV ainda aberto. No [código oficial fixado do PresentMon 2.6.0](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/PresentMon/CsvOutput.cpp), o flush por linha é condicionado à saída padrão. A combinação de arquivo e stdout também não serve: o [parser oficial](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/PresentMon/CommandLine.cpp) prioriza o arquivo. A P7 usa somente `--output_stdout`, com leitura incremental em tarefa separada. A interface lê snapshots a cada 500 ms. Não há callbacks WPF por quadro.

`logs/p7-buffering-reproducer.log` registra a falha esperada do transporte antigo com uma fixture que reproduz o arquivo sem flush. O coletor simulado da regressão nova envia linhas imediatamente pela saída padrão, sem arquivo, e comprova números/amostras antes do término da gravação. A reprodução antiga permanece disponível com o argumento `reproduce-buffered-file` no harness PresentMon; ela é um diagnóstico negativo, não uma suíte que deve aprovar.

`PresentMonMonitor` mantém uma única sessão `WinSlim-<GUID>`, valida o binário oficial por SHA-256 na entrada de produção e compartilha o parser incremental existente. Monitoramento contínuo não grava CSV por quadro. Buffers: até 16 swap chains, até 4096 intervalos por cadeia e até cinco segundos por janela; linha incompleta limitada a 64 KiB; stderr limitado a 4 KiB. O gráfico reduz a série visual para até 360 pontos. Nova sessão possui parser/buffer próprios.

Benchmark grava apenas as amostras recebidas enquanto seu gravador está anexado à coleta. Duração de 10–120 s; limite de dois milhões de linhas e 128 MiB de texto UTF-16. Ao concluir, a escrita do CSV e o cálculo completo usam tarefa separada e o parser estatístico aprovado. Limite, cancelamento ou indisponibilidade reprovam a gravação e preservam o monitor e o resultado completo anterior. Uma gravação cancelada durante a escrita pode deixar um CSV incompleto na pasta exclusiva daquela tentativa; ele não vira resultado nem referência. Não há segunda sessão ETW para gravar benchmark. O monitor continua após concluir ou cancelar. Parar explicitamente o monitor cancela uma gravação ativa; o botão fica indisponível durante a gravação, evitando parada acidental.

Coletando amostras, monitorando, gravando, dados desatualizados, coleta interrompida e jogo encerrado têm estados distintos. Menos de 30 intervalos válidos não produz estatísticas. Após dois segundos sem amostras, os valores atuais desaparecem; a referência continua identificada. Para retomar depois de erro do coletor, pare o monitor e inicie novamente. Não há reinício silencioso do alvo durante benchmark.

## Métricas e interface

- FPS médio = 1000 / média dos intervalos de apresentação. Monitor: até cinco segundos/4096 quadros; benchmark: toda a captura.
- FPS atual = 1000 / média dos intervalos recebidos no último segundo. Sem amostra nessa janela, o indicador atual fica indisponível.
- 1% low = 1000 / média do 1% de intervalos mais lentos, arredondando a quantidade para cima.
- Tempo por quadro = média em ms. P99 = percentil por posto mais próximo, arredondado para cima.

São FPS de apresentação (`MsBetweenPresents`), sem promessa de FPS efetivamente exibido ou latência de entrada. As definições completas e a comparação por aplicativo/duração/métrica foram preservadas.

Pequeno tem quatro métricas. O controle “FPS: médio/atual” substitui apenas a primeira. Médio acrescenta FrameTime atual laranja contínuo e referência azul tracejada, com escala comum, legenda e explicação de posição relativa das amostras. A referência é copiada; o overlay não a altera. O resultado comparativo da página continua exigindo duração compatível.

Pequeno | Médio, Mover/Travar e seleção de FPS continuam clicáveis em janela nativa separada. Travado, o corpo usa a passagem de entrada do HWND layered para o jogo. Ambas as janelas recusam ativação. Arraste cruza monitores e só termina/clampa ao soltar. Mudanças de modo, posição e visibilidade não alteram gravador, PID, referência ou sessão.

Preferências são identificadas pelo caminho estável do executável, com fallback pelo nome quando o Windows nega acesso ao módulo. Perfis v1/v2 anteriores são migrados/preservados. Posição relativa, monitor, tamanho, trava, escala, opacidade, FPS e sensores ficam por jogo. Topologia indisponível preserva o último perfil; monitor removido usa um disponível. Escala efetiva se reduz se necessário para caber na tela, mantendo a escala escolhida no perfil. DPI físico permanece sujeito ao teste real descrito no roteiro.

Seleção automática prioriza tela cheia/sem bordas em primeiro plano; voltar ao Win-Slim preserva o último jogo. Escolha manual desliga a seleção automática. Benchmark fixa PID e início do processo; jogo encerrado cancela a gravação e encerra somente a sessão própria. Troca automática ou manual de alvo fora do benchmark encerra a sessão anterior antes de iniciar a próxima.

Os interruptores maiores mostram ON/OFF e acento laranja quando ativos. “Monitorar jogo” e “Gravar benchmark” são ações separadas. “Overlay / atalhos” concentra escala (75–175%), opacidade do fundo (35–100%), FPS, sensores, restauração padrão e três atalhos. Atalhos começam desativados; vazio desativa. Exemplos: Ctrl+Alt+F9, Ctrl+Alt+F10, Ctrl+Alt+F11. Registro usa MOD_NOREPEAT, reporta conflitos e restaura registros anteriores disponíveis se houver falha. F12 e teclas sem modificador são rejeitadas. Atalhos são globais do aplicativo e persistem separadamente; restaurar o perfil de um jogo não os apaga.

## Sensores opcionais

Ativados em conjunto na configuração, sem substituir nem aumentar as quatro métricas padrão. Consultas em segundo plano a cada cinco segundos, sem sobreposição; leitura envelhecida ou ausente aparece como “Indisponível”, nunca zero inventado. CPU/GPU/RAM reutilizam `Get-WinSlimUiPerformanceSnapshot`. GPU mantém a definição existente: maior uso entre os motores informados pelo Windows. RAM mostra percentual do sistema.

VRAM mostra MiB de memória dedicada do adaptador com maior uso, conforme a classe de desempenho GPUAdapterMemory do Windows; não é uma atribuição ao jogo nem soma com memória compartilhada. Essa [distinção de contadores](https://github.com/prometheus-community/windows_exporter/blob/master/internal/collector/gpu/gpu.go) também separa memória do adaptador da memória por processo. Driver/WDDM sem contador válido resulta em indisponível.

Temperaturas só são lidas de um provedor WMI já disponível, em `root/LibreHardwareMonitor` ou `root/OpenHardwareMonitor`. O vínculo usa Hardware/Parent e nomes específicos de CPU package/core e GPU core; não apresenta temperatura ACPI, distância a TjMax ou memória da GPU como temperatura do processador. Ver [contrato WMI do Open Hardware Monitor](https://openhardwaremonitor.org/wordpress/wp-content/uploads/2011/04/OpenHardwareMonitor-WMI.pdf). Versões do Libre Hardware Monitor que não expõem WMI não oferecem essa leitura nesta candidata. Ausência de provedor/permissão/sensor válido fica indisponível. Nenhum desses programas, DLLs, serviços ou drivers é iniciado, instalado ou redistribuído. A compatibilidade física de sensores permanece pendente; a regressão usa fixtures para leituras válidas, inválidas e ausentes.

## Etapa posterior, fora da implementação P7

| Recurso | Avaliação necessária antes de implementar | Critério de validação |
| --- | --- | --- |
| Limitador de FPS por jogo | Escolher integração cooperativa do jogo ou API documentada do fabricante; analisar permissões, distribuição/licença e interação com VSync/VRR | Limite efetivo, frame pacing, consumo e latência em múltiplas APIs/GPU; desfazer por jogo |
| Sincronização com objetivo semelhante ao Scanline Sync | Definir mecanismo próprio/documentado de sincronização; estudar resolução/taxa/VRR, tearing e dependências de apresentação | Medição externa de tearing e latência; matriz de monitores e frequência; desligamento seguro |
| Tela cheia exclusiva ampliada | Overlay externo topmost não garante composição no exclusivo. Avaliar APIs/integradores autorizados, licenças e compatibilidade de cada jogo | Matriz DX11/DX12/Vulkan, alternância de foco/DPI, captura, permissões e restrições do jogo |

Nenhum componente RTSS proprietário foi copiado ou redistribuído; nenhum desvio de anti-cheat foi implementado. Escolha de arquitetura e integração autorizada são pendências concretas dessa etapa. Por ora, usar janela sem bordas onde o overlay externo não aparece.

## Evidências e limites

As regressões novas abrangem fluxo stdout antes do fim, monitor sem benchmark/sem CSV, cancelamento e regravação na mesma sessão, buffers, FPS atual versus médio, stale, PID alheio, coletor com falha e encerramento. WPF cobre o fluxo real de iniciar/cancelar/reiniciar com gravador pendente injetado, preservando resultado e referência; seletor/arraste/trava, alvo fixo, preferências/escala, fonte indisponível e conflitos de atalhos têm testes comportamentais. As dez suítes delegadas pelo gate continuam sem duplicação. Relatório final e hashes estão na retomada P7 e em `logs/candidate-p7.json`.

Primeira execução completa P7: `regressao-20261021-164847-786-f93349dc`, 17/18. A única reprovação foi o contrato existente que proíbe `Thread.Sleep` nas fontes da UI: o adaptador de compatibilidade tinha uma espera em worker. A espera foi convertida para `await Task.Delay(...).ConfigureAwait(false)`, sem remover nem afrouxar o teste. Esse relatório não autoriza empacotamento; a candidata exige uma nova execução completa aprovada. Os artefatos da tentativa foram preservados.

Aceite em jogo, entrega real de cliques, captura de cursor, DPI e múltiplos monitores físicos, sensores físicos e exclusivo/anti-cheat continuam pendentes. ETW real não foi iniciado durante as regressões. CI Windows hospedada pendente. Produção não aprovada. Edge somente na VM, ainda pendente.
