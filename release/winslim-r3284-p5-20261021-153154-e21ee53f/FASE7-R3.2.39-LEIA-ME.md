# Win-Slim Suite — R3.2.39

Extraia em uma pasta nova e abra Executar-WinSlim-R3.2.39.bat. Confirme R3.2.39 no rodapé para evitar abrir o executável anterior.

Animações agora são ativadas por padrão no aplicativo, independentemente da preferência de animações do Windows. Em Configurações > Geral, “Animações da interface” permite desligar os efeitos. Alto contraste continua sem movimento. A preferência é salva neste computador.

Botões e categorias têm realce laranja progressivo e escala de hover 1.018 em 180 ms, pressão 0.96 em 90 ms e retorno suave. Chaves deslizam 18 px em 260 ms com transição verde/cinza. O template não substitui mais o transform durante a troca de estado. Checkboxes e overlays confirmam a troca com expansão do indicador em 240 ms. Telas usam entrada com opacidade de 0.25 a 1 e deslocamento de 18 px em 300 ms; abas e categorias em 280 ms. Não há espera para executar cliques, alteração do tamanho da janela ou novas janelas.

Execute Validar-Animacoes-R3.2.39.bat. O teste antigo que cobrava literalmente 160 ms foi atualizado para as durações atuais, preferência e camada visual. O log R3.2.38 confirmou compilação e self-test WPF, mas o gate teve essa única falha; não comprovou fluidez visual.

Nesta revisão, XML, nomes de controles, integridade das versões anteriores e arquivo ZIP são conferidos localmente. A compilação e avaliação das animações desta revisão permanecem pendentes no Windows. Confira botões com mouse/teclado, alternâncias rápidas de chaves, checkboxes, overlays, troca de telas/categorias e retorno. Execução de otimizações continua em consulta/demonstração.
