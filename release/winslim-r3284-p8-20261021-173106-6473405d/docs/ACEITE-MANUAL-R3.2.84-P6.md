# Aceite real — R3.2.84 P6: complemento do overlay

Uma candidata consolida todo o complemento: referência no gráfico, controles compactos que recebem cliques, métricas que deixam os cliques chegarem ao jogo quando travadas e posicionamento livre entre monitores. O overlay continua acompanhando a medição iniciada pelo usuário, sem alterações nos contratos de coleta, comparação final, Apply/Verify/Undo ou backup.

## Aceites preservados e pendências

As duas capturas da conversa registram o aceite do usuário para comparação do FrameTime e cancelar/capturar novamente (21/10/2026). Evidências P4 e a candidata P5 anterior permanecem preservadas. Não é necessário repetir os lotes manuais anteriores.

**Edge EDGE-019/020/024/025 continua pendente**, exclusivamente na VM com o fluxo normal de revisão, backup e restauração. Nenhum ajuste do catálogo foi aplicado ao computador principal. CI Windows hospedada e aceite real do novo overlay permanecem pendentes; produção não aprovada.

## Roteiro curto do novo lote

1. Abra `bin\WinSlim.UI.Native.R3.2.84.exe` na nova pasta isolada indicada na entrega. Selecione o jogo, marque **Overlay durante a medição**, escolha **60 segundos**, meça e guarde a referência. Se já houver referência compatível na sessão, use-a. Inicie outra medição de **60 segundos**, na mesma cena e configuração, com o jogo em janela sem bordas/tela cheia, e retorne ao jogo. Use um menu do jogo que libere o cursor, se necessário.
2. No próprio overlay, alterne **Pequeno | Médio** várias vezes: o tamanho ativo deve ficar destacado, sem pausa da captura ou perda de números. Pequeno mostra somente FPS médio, quedas de fluidez (1% low em FPS), tempo médio por quadro (ms) e picos de demora (P99 em ms), além dos controles. Médio mantém essas quatro métricas e acrescenta o FrameTime **atual laranja contínuo**, com **referência azul tracejada** e legenda quando houver referência compatível. Ambas as curvas usam a mesma escala; a posição horizontal é relativa às amostras, não ao mesmo instante das duas capturas.
3. Em **Travar** (botão oferecendo Mover), clique numa área das métricas sobre um botão/menu do jogo: o jogo deve receber o clique. Os controles Pequeno/Médio/Mover continuam recebendo cliques. Em **Mover** (botão oferecendo Travar), arraste qualquer área do painel fora dos controles, tanto no Pequeno como no Médio. Com dois monitores, atravesse a divisão e deixe o painel no segundo monitor. A captura deve continuar, com o jogo conservando o foco. Clique **Travar**; clicar/arrastar nas métricas agora volta a atingir o jogo.
4. Alterne tamanhos perto das bordas e confirme que o painel inteiro fica visível no monitor escolhido. Faça nova medição no mesmo jogo: posição, monitor, tamanho e trava voltam. Com um segundo jogo, confirme que as posições são independentes. Se for viável no ambiente, mude a resolução ou desconecte o monitor do overlay: ele deve reaparecer dentro de um monitor disponível, mantendo números/referência e controles acessíveis. Não é preciso repetir o teste real de cancelamento já aceito.

Registre uma imagem de cada tamanho (Médio com referência), jogo/modo de tela, escala dos monitores, resultado do clique através das métricas e do arraste entre monitores. Esse é o aceite real novo solicitado; resultados automatizados ficam em `logs\candidate-p6.json` e no relatório de regressões dessa candidata.

## Limites relevantes

Uma janela WPF pode não aparecer em tela cheia exclusiva ou em determinadas configurações de anti-cheat. Registrar o resultado e usar janela sem bordas para o teste. Acesso ETW, cursor capturado, cliques efetivamente recebidos pelo jogo e monitores com DPI diferentes exigem validação real; os testes automatizados não injetam cliques no jogo do usuário, não movem seu cursor e não executam ETW real.

Na ausência de novos quadros, os valores atuais viram traços; a referência válida permanece guardada. Falha temporária da topologia não apaga o perfil. Perfis antigos são lidos e migrados para posição relativa com identificação do monitor; quando ele desaparece, a posição é ajustada para um monitor disponível. A preferência é por executável, independente do PID. Falha de gravação preserva o perfil anterior e mostra um aviso.

Para nova validação técnica completa, `Iniciar-Validacao.bat` permanece o ponto de entrada; a entrega já inclui os resultados da execução da candidata. `Coletar-Diagnostico.bat` reúne as evidências.
