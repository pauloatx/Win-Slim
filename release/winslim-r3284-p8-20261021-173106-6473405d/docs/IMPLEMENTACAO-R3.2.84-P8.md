# P8 — acabamento e configurações do overlay

O usuário confirmou nesta conversa o funcionamento observado do overlay no teste real apresentado. Esse aceite foi registrado com esse alcance: não aprova automaticamente clique recebido pelo jogo, DPI físico, múltiplos monitores, sensores, atalhos ou comportamento novo das configurações. As candidatas P7/P6/P5/P4 e os aceites anteriores de FrameTime comparativo e cancelar/capturar novamente foram preservados. Edge real continua pendente, somente na VM.

## Implementação

“Configurar overlay” usa moldura escura com acento laranja, cantos de 12 px, fechamento integrado, arraste pela barra de título e foco visível nos controles. O subtítulo mostra “Preferências para <jogo selecionado>”. A janela é limitada à área útil do monitor e ajusta limites ao mudar DPI, monitor/resolução ou terminar um arraste. O conteúdo tem rolagem; ações de salvar/cancelar/restaurar ficam no rodapé fixo.

- **Aparência:** prévia identificada como “Prévia — valores ilustrativos”, usando o mesmo componente visual do overlay, sem iniciar coleta. Pequeno/Médio, escala com porcentagem e fundo com porcentagem e orientação “Mais transparente ↔ Mais opaco”. Alterações aparecem imediatamente no overlay e na prévia.
- **Informações:** seletor Atual/Médio para o primeiro indicador de FPS, com dica sobre as janelas de 1 s/até 5 s. Interruptor “Mostrar informações do computador” e área expansível para CPU, GPU, VRAM e RAM individualmente. As quatro métricas do jogo permanecem iguais. Ausência de leitura vira “Indisponível”, com dica simples. Explicações sobre origem/frequência dos sensores ficam em “Sobre as leituras”.
- **Atalhos:** captura por botão, “Pressione a combinação”, combinação registrada ou “Não definido”, e Limpar por campo. Duplicatas e falhas de registro aparecem junto ao campo afetado. Combinações aceitas mantêm o contrato anterior: Ctrl/Alt/Shift e letra ou F1–F24, exceto F12 reservado. Escape abandona a captura de uma tecla; fora dela, fecha como Cancelar. As ações globais ficam suspensas enquanto a configuração está aberta, permitindo capturar um atalho próprio sem executar o comando.

Salvar alterações registra os atalhos, grava o perfil do jogo de forma atômica, fecha a configuração e mostra confirmação discreta na página principal. Se a gravação falhar, os atalhos anteriores são restaurados e o erro mantém a janela aberta; não há falsa confirmação de salvamento. Cancelar e fechar recuperam aparência, seleções e posição de abertura, ajustadas apenas se a topologia exigir manter o painel visível. A prévia nunca grava implicitamente o perfil, inclusive quando relayout/posicionamento ocorrem durante uma edição.

“Restaurar padrão deste jogo” altera apenas o rascunho do jogo aberto: Pequeno, escala 100%, fundo 93%, FPS médio, informações opcionais desligadas, quatro categorias habilitadas para a próxima ativação e atalhos não definidos. Preserva a posição e a trava. É necessário Salvar para persistir; Cancelar/fechar desfazem também essa restauração.

Atalhos novos ficam por jogo no mesmo perfil das preferências. Os atalhos globais já existentes da P7 continuam como padrão de compatibilidade para jogos sem configuração própria. Abrir a configuração ou monitorar outro jogo ativa seu perfil; conflito é informado e não mantém silenciosamente os comandos do jogo anterior. Reset de um jogo não apaga perfis de outros jogos nem o arquivo global de compatibilidade.

No overlay, números usam maior destaque e algarismos de largura uniforme; unidades e qualificadores ficam menores, separados dos valores. Rótulos têm altura estável e quebra de linha prevista; valores longos reduzem sua escala visual para caber. Controles têm alturas e larguras fixas, impedindo saltos ao trocar Mover/Travar ou FPS atual/médio. O modo ativo tem acento laranja e contraste. Gráfico atual laranja contínuo, referência azul tracejada, escala comum e explicação da posição relativa foram mantidos.

A configuração só abre por ação explícita. As atualizações do overlay continuam sem ativação e sem reiniciar coletor ou benchmark. Durante a janela modal, a escolha automática de outro jogo é suspensa, mas amostras, gráfico, conclusão/cancelamento de benchmark e detecção de encerramento do jogo continuam. O subtítulo não reaproveita acidentalmente o perfil de um jogo anterior.

Os arquivos do coletor e do parser/estatísticas da P7 não foram alterados (`PresentMonMonitor.cs`, `BenchmarkLive.cs`, `PresentMonBenchmark.cs`). A prévia recebe valores próprios ilustrativos e cópia de referência; não injeta valores no fluxo real. A infraestrutura de sensores continua a mesma; apenas a apresentação e os filtros individuais mudaram.

## Regressões e evidências

`REG-OVERLAYSETTINGS-001` registra gravação prematura ao restaurar padrão sem salvar e ausência de restauração ao fechar/cancelar. Antes da correção, o teste chamou a mesma ação de reset usada pelo diálogo antigo e demonstrou que o perfil era sobrescrito: `logs/p8-settings-before.log`, saída 1 esperada. A tentativa inicial de automatizar o diálogo modal antigo não completou; portanto, a demonstração anterior é restrita à gravação prematura dessa ação. A versão nova testa os controles e a janela reais, sem precisar abrir uma janela visível ou iniciar ETW.

Cobertura comportamental: sliders e percentuais; preservação do modo e posição física quando há espaço; rascunho sem escrita; reset/cancelar/fechar; salvar/reabrir por executável; perfil bloqueado e recuperação dos atalhos; outra instalação/jogo preservada; prévia ilustrativa separada de novas amostras reais; ambos os modos e curvas; captura/limpeza, F12, duplicatas e conflito de registro; escolha individual dos sensores mantendo quatro métricas. O self-test WPF também abre/edita/fecha a configuração durante uma tarefa de captura pendente injetada e verifica tarefa, processo, cancelamento, dados, resultado completo e referência.

O layout foi medido e renderizado em WPF com transformações equivalentes a **100%, 125% e 150%**, viewport físico de altura limitada e rolagem até o último atalho. Os testes verificam rodapé visível, ações sem sobreposição e acesso ao último campo. Imagens dessa verificação ficam em `logs/p8-layout/`. Isso é **verificação automatizada de layout**, não alteração do DPI do Windows nem aceite em monitores físicos.

O gate obrigatório completo aprovou 19/19 suítes Windows/WPF. Seis testes Python do empacotador passaram; 19 IDs únicos e 152 hashes foram validados. Execução: `regressao-20261021-173120-911-ad234321`. Caminhos e hashes estão na retomada P8 e em `logs/candidate-p8.json`. A candidata não autoriza produção enquanto houver critérios obrigatórios pendentes.

## Pendências reais

Novo acabamento/configurações no jogo; cliques e foco no jogo durante interação; troca física de DPI entre 100/125/150%, monitores e resolução; atalhos frente a conflitos reais de outros programas; disponibilidade física de sensores. O funcionamento observado do overlay anterior está aceito pelo usuário, sem ampliar esse aceite para essas verificações. CI Windows hospedada pendente. **Edge real pendente, exclusivamente na VM. Produção não aprovada.** Nenhum ajuste do catálogo foi aplicado; VM não modificada.
