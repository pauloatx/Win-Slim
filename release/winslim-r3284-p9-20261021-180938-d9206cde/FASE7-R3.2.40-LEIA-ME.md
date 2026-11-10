# Win-Slim Suite — R3.2.40

Extraia em pasta nova e abra Executar-WinSlim-R3.2.40.bat. Confirme R3.2.40 no rodapé.

Estilo esmaecer: telas entram de opacidade 0 a 1 em 320 ms; abas e categorias em 300 ms. Botões têm realce laranja que aparece/desaparece em 240–260 ms, com confirmação de clique por esmaecimento em 240 ms. Checkboxes e overlays usam confirmação por opacidade em 280 ms. Curva cúbica EaseInOut com aceleração/desaceleração suaves. Removidos zoom de hover/pressão e deslocamento vertical das telas. Chaves preservam deslize funcional e transição verde/cinza em 260 ms.

As animações são ativadas por padrão em Configurações > Geral > Animações da interface. Alto contraste continua sem movimento. Não altera seleção, tamanho das janelas ou modo de consulta/demonstração. Cliques não aguardam a animação. Animações repetidas substituem o efeito anterior; efeitos transitórios retornam à opacidade definida pelo template, incluindo controles desabilitados.

Execute Validar-Animacoes-R3.2.40.bat e confira navegação, botões com mouse/teclado, chaves, checkboxes e categorias. Verificações locais: XML, nomes e recursos, integridade da base e ZIP. Self-test verifica a curva de esmaecimento progressiva, duração e ausência de overshoot, além dos estados das chaves. Compilação e avaliação visual desta revisão pendentes no Windows.
