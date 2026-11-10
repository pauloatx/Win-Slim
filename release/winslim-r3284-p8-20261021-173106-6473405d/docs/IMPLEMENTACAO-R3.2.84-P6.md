# R3.2.84 P6 — complemento do overlay

Escopo único: quatro métricas no Pequeno; as mesmas quatro e duas séries no Médio; seletor compacto com tamanho ativo; arraste em qualquer área fora dos controles, entre monitores; trava, entrada atravessando as métricas e preferência por jogo. A captura continua opcional e iniciada pelo usuário. O catálogo e os mecanismos de produção não foram alterados.

## Implementação

A janela visual WPF usa `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE` enquanto travada. Uma segunda janela, ajustada apenas à faixa de controles, mantém os botões clicáveis sem ativação. Em posicionamento, a janela visual aceita entrada e o arraste acompanha coordenadas físicas do cursor somente durante a ação iniciada pelo usuário. Nenhum clique é encaminhado artificialmente ao processo do jogo. O mecanismo segue o contrato de [janelas em camadas do Win32](https://learn.microsoft.com/en-us/windows/win32/winmsg/window-features#layered-windows); a alternativa [HTTRANSPARENT](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-nchittest) tem alcance limitado à mesma thread.

O controlador passa uma cópia da referência compatível (aplicativo, duração, métrica e captura válida). O gráfico usa laranja contínuo para Atual e azul tracejado para Referência, com escala conjunta e posições horizontais relativas às amostras. Trocar de tamanho apenas reorganiza a janela; a referência original, os dados atuais, a tarefa de captura, o PID e o cancelamento permanecem intactos. Pequeno não acrescenta séries ou indicadores às quatro métricas solicitadas.

O perfil de posição versão 2 guarda o identificador do monitor, a posição relativa e a última coordenada física. Perfis versão 1 continuam válidos e migram quando usados. O arraste atravessa limites e espaços entre monitores; ao soltar, o painel se ajusta inteiro ao monitor com maior interseção ou ao mais próximo. Redimensionamento, alteração de resolução/origem e remoção de monitor recalculam a posição visível. O monitor do jogo não força mais o overlay a voltar após o usuário movê-lo. Consultas nativas de coordenadas físicas preservam o contexto DPI da thread.

## Regressões e evidências

- `REG-OVERLAY-001`: preserva os testes anteriores e acrescenta estilos nativos, recusa de ativação dos dois HWNDs, controles reais WPF, limites da faixa interativa, escalas/cores/tracejado da referência, comprimentos diferentes, repetição da troca com dados preservados, arraste nativo entre dois monitores simulados, travar, roundtrip do monitor, migração, resolução/origem diferente, remoção e indisponibilidade da topologia. Perfis bloqueados ou corrompidos não destroem o estado anterior/de outro jogo.
- `REG-UI-001`: o self-test do aplicativo usa a mesma fábrica do overlay da captura, com uma tarefa pendente e token real, e verifica que mover/trocar/travar não concluem, substituem ou cancelam essa tarefa nem mudam o alvo ou a referência. Testes antigos de comparação, viewport, tema/idioma e demais contratos seguem exigidos.
- `REG-PRESENTMON-001`: mantém o teste do processo simulado emitindo prévia durante a coleta, cancelamento sem resultado parcial e recaptura. Nenhuma otimização ou captura ETW real é executada.

Falha anterior demonstrada comportamentalmente antes da correção: o HWND travado não tinha passagem nativa de mouse (`logs/overlay-complement-before.log`). A restrição do arraste e a falta de referência foram verificadas na implementação P5; seus novos cenários exigem a nova entrada de referência e a topologia injetável, portanto a suíte ampliada completa não podia executar contra a assinatura antiga. A expectativa de passagem de entrada não foi reduzida.

Uma falha intermediária do teste de remoção usava a altura padrão de um HWND oculto (753 px), em vez da altura medida do painel. O fixture agora sincroniza o tamanho nativo à medida WPF, sem abrir janelas sobre o jogo nem alterar a expectativa de manter o painel inteiro dentro do monitor. Essa evidência foi preservada em `logs/overlay-complement-display-before.log`.

A primeira execução do gate P6 também encontrou `IOException` ao remover a pasta temporária exclusiva do self-test. A limpeza agora valida o caminho/identificador da fixture e repete somente erros de IO, com limite de dez tentativas; falha persistente continua reprovando. Testes determinísticos cobrem indisponibilidade transitória, persistente e rejeição de diretório alheio. O estado e os timers do controlador são restaurados mesmo se a limpeza falhar. O relatório da primeira execução foi preservado; somente a nova execução completa pode autorizar o pacote.

Os testes nativos verificam estilos e mensagens Win32 dos HWNDs e cliques nos controles WPF. A confirmação de cliques recebidos por um jogo de outro processo, interação com cursor capturado e DPI físico de vários monitores é aceite real pendente. Topologias de múltiplos monitores são fixtures determinísticas; não foram desconectados monitores do usuário.

Os resultados finais pertencem exclusivamente à execução apontada por `logs/candidate-p6.json`; relatórios vazios, parciais ou de execuções anteriores não autorizam a entrega. Aceites P4 preservados; Edge e CI hospedada pendentes. Roteiro: `ACEITE-MANUAL-R3.2.84-P6.md`.
