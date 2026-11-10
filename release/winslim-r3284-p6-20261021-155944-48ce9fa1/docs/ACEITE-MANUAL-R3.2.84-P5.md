# Aceite real — R3.2.84 P5: seleção automática e overlay

Escopo congelado em 21/10/2026 (America/Sao_Paulo): reconhecimento do aplicativo em tela cheia; overlay opcional durante a medição, com quatro métricas ao vivo, gráfico no tamanho Médio, seletor imediato e arraste com trava/posição por jogo. Catálogo, ajustes, transações e comparação de resultados mantêm os contratos anteriores.

## Aceites preservados

O usuário confirmou em 21/10/2026, com as duas capturas anexadas à conversa, a comparação de FrameTime (atual laranja, referência azul tracejada e hover) e o fluxo de cancelar/capturar novamente no jogo. Aceites P4 concluídos: não repetir o lote manual anterior sem regressão relacionada. As capturas são evidência da conversa; não foram criados arquivos de imagem ou hashes fictícios no projeto.

**Edge EDGE-019/020/024/025: aceite real pendente**, exclusivamente na VM, usando revisão, backup e Apply/Verify/Undo do aplicativo. Não aplicar essas políticas no computador principal. O roteiro P4 permanece disponível para esse item. CI Windows hospedada e aceite real do novo overlay também continuam pendentes. Aprovação de produção: não concedida.

## Teste curto do novo lote (um jogo, cerca de 3 minutos)

1. Na pasta isolada informada na entrega, abra `bin\WinSlim.UI.Native.R3.2.84.exe`. Em Análise do Sistema → Desempenho em jogo, deixe **Detectar tela cheia** marcado. Abra/retorne ao jogo em tela cheia ou janela sem bordas por 2 segundos e volte ao Win-Slim: deve estar selecionado o executável do jogo, sem iniciar captura sozinho. Se houver vários aplicativos em tela cheia, o último em primeiro plano tem prioridade. A descoberta inicial só escolhe um candidato inequívoco. Escolher manualmente na lista desmarca a detecção; Atualizar preserva uma seleção ainda válida.
2. Marque **Overlay durante a medição**, use **60 segundos**, clique **Medir** e retorne ao jogo. **Pequeno** mostra FPS médio, 1% low em FPS, FrameTime médio em ms e P99 em ms. **Médio** deve manter os mesmos números e acrescentar o gráfico de FrameTime. Alterne os dois botões no overlay: a mudança ocorre na hora, sem reiniciar a captura ou retirar o foco do jogo. Os valores usam os últimos 240 intervalos válidos do mesmo PID/nome/swap chain, com as mesmas fórmulas do resultado. Eles podem diferir das estatísticas da captura inteira. Até chegar o primeiro lote de dados do coletor, ou numa pausa de renderização, aparecem traços/“Aguardando quadros…”, nunca FPS zero inventado.
3. Clique **Mover**, arraste o título até outro ponto e clique **Travar**. O título deve mover livremente dentro do monitor do jogo e parar de mover quando travado; os seletores permanecem utilizáveis. Alterne Pequeno/Médio perto das bordas: o painel deve continuar visível. Faça Alt+Tab: o overlay deve sumir sobre outros aplicativos e reaparecer ao voltar ao jogo. Encerrar/cancelar a medição fecha o overlay e não fecha o jogo.
4. Inicie outra medição no mesmo jogo: posição, tamanho e trava devem voltar como salvos. Reabra o Win-Slim e repita, se necessário, somente essa verificação de persistência. Se houver segundo jogo disponível, movê-lo não deve alterar a posição do primeiro. Guarde uma captura do overlay Pequeno e outra do Médio, e informe jogo, modo de tela e escala/monitor utilizados.

## Limites e diagnóstico

O overlay é uma janela WPF sobreposta, sem injeção no jogo, driver ou serviço. Tela cheia exclusiva pode impedir sua composição; nesse caso, registrar o resultado e testar janela sem bordas. A sobreposição em jogos reais, anti-cheat, captura do mouse pelo jogo e monitores com escalas diferentes exigem aceite real e não são declarados aprovados pelos testes de fixtures. Não há autoelevação: se o PresentMon precisar de permissões ETW, a mensagem deve ser registrada e a decisão de elevar permanece com o usuário.

A captura só começa ao clicar em Medir; o overlay funciona pelo tempo escolhido (10–120 segundos). A prévia incremental não vira resultado, referência ou exportação parcial. O fim/cancelamento usa somente a sessão ETW exclusiva `WinSlim-<GUID>`. Posições ficam em `config\benchmark-overlay\<hash-do-executável>.json`, relativas ao monitor, independentes do PID. Quando o caminho do processo é inacessível, a identidade usa o nome do executável. Falha de gravação deixa um aviso no overlay e preserva o perfil anterior. Resultados e evidências da candidata ficam em `logs`; use `Coletar-Diagnostico.bat` para reuni-los.

`Iniciar-Validacao.bat` é o ponto de entrada para uma nova validação técnica completa; só abre o aplicativo após sucesso. A candidata entregue terá o gate executado e documentado, sem exigir repetição manual dos lotes aprovados.
