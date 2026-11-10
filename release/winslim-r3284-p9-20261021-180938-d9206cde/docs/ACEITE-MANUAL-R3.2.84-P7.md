# Teste real curto — P7

Execute `Iniciar-Validacao.bat` da pasta P7. O aplicativo só deve abrir após o gate completo aprovar. Não aplicar ajustes do catálogo neste lote. P4/P6 e seus aceites permanecem preservados.

1. Abra um jogo em janela sem bordas. Em Desempenho em jogo, deixe Detectar tela cheia ativo, volte ao jogo e retorne ao Win-Slim: o processo deve ser o mesmo. Escolha manualmente outro processo para comprovar que a seleção manual é respeitada.
2. Use Monitorar jogo e Mostrar overlay, sem benchmark. Volte ao jogo: “Coletando amostras” deve dar lugar a quatro valores em aproximadamente 500 ms por atualização após amostras suficientes. Médio deve desenhar a linha laranja. Alterne FPS médio/atual e varie uma cena pesada/leve. Confira a referência azul quando guardada para esse jogo.
3. Inicie Gravar benchmark (10 s). Durante a gravação, alterne Pequeno/Médio, FPS, ocultar/mostrar e Mover/Travar. Cancele: monitor e curva continuam, resultado completo anterior e referência permanecem. Grave novamente até concluir: resultado novo é completo e monitor continua. O alvo deve ficar fixo durante toda a gravação.
4. Travado, clique numa ação verificável do jogo sob a área das métricas: o jogo deve receber o clique. Pequeno/Médio e Mover/Travar devem continuar clicáveis sem minimizar o jogo. Em Mover, arraste o corpo; em Travar, ele fica fixo e volta a deixar os cliques passarem.
5. Arraste entre dois monitores, incluindo escalas DPI diferentes. Troque tamanho e escala/opacidade. Volte a selecionar o mesmo jogo: restaure posição, monitor e preferências. Mude a resolução/desconecte o segundo monitor: overlay e controles devem continuar visíveis. Reative sensores e confira leituras ou “Indisponível”. Não instalar provedor/driver para aprovar este teste.
6. Configure os três atalhos em Overlay / atalhos; confira mostrar/ocultar, iniciar/cancelar gravação e Mover/Travar. Tente um atalho ocupado e um duplicado: deve haver erro claro. Deixe vazio para desativar. Pause/minimize o renderizador e encerre o jogo: dados antigos não podem permanecer como atuais; jogo encerrado deve finalizar a coleta própria. Feche o Win-Slim com monitor ativo e confirme que o coletor dessa sessão encerra.

Registre jogo/modo/API, resolução, DPI, monitores, leituras, desvios e resultado do lote. Exclusivo e jogos com restrições podem ocultar o overlay externo: registrar, sem técnicas de contorno; testar a apresentação em janela sem bordas.

**Edge real: pendente, somente na VM. CI Windows hospedada: pendente. Produção: não aprovada.** Não repetir manualmente lotes antigos aprovados sem regressão relacionada. Use `Coletar-Diagnostico.bat` para obter um ZIP de evidências.
