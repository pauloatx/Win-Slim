# Win-Slim Suite — R3.2.38

Animações discretas: hover de botões com escala 1.006 em 140 ms, pressão com escala 0.985 em 80 ms e retorno em 120 ms; teclas Espaço/Enter usam a mesma resposta. As chaves deslizam 18 px e interpolam a cor verde/cinza em 170 ms. Checkboxes e indicadores de overlays recebem confirmação visual curta. Telas, detalhes/relatórios, abas e categorias usam entrada com opacidade e deslocamento de 7 px em 180–200 ms. Não há alteração do tamanho da janela nem atraso para executar o clique.

Respeita a preferência de animações da área de cliente do Windows e modo de alto contraste. Não usa timers para animação de interação, sombras pesadas, novas janelas ou dependências. As animações se substituem em cliques repetidos, finalizam na cor/posição correta e não alteram seleção, busca ou rolagem. Checkboxes bloqueados continuam indisponíveis.

Extraia em pasta nova e execute Validar-Animacoes-R3.2.38.bat. Abra Executar-WinSlim-R3.2.38.bat e confira mouse e teclado nos botões, chaves de Personalizado/Modo desenvolvedor, checkboxes de Configurações, overlays e mudança de categorias/telas. Alterne uma chave rapidamente e solte o mouse após sair de um botão pressionado. Confira que não fica deformado ou na cor errada. Teste a preferência do Windows de desativar animações.

R3.2.37 passou no gate Windows enviado pelo usuário (resultado 0). Verificações locais cobrem XML, referências de controles, estrutura C#, preservação da base e ZIP. Self-test acrescenta oito alternâncias de uma chave isolada e verifica cor e posição finais sem editar preferências do usuário. A compilação, carregamento WPF e avaliação da fluidez devem ser feitos no Windows. Execução continua em modo de consulta/demonstração.
