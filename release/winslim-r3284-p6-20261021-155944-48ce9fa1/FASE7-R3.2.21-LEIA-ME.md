# Win-Slim R3.2.21 — Dimensões uniformes

Tamanho inicial padronizado em 1180 × 760 unidades WPF (equivalente a pixels na escala de 100%). É o tamanho das telas mais densas já conferidas: Presets, Avançado e Pré-visualização. O Dashboard passa a usar o mesmo tamanho. As janelas de relatório de conclusão e detalhes da pré-visualização também abrem em 1180 × 760.

Removido o redimensionamento automático durante a navegação. Redimensionar manualmente ou maximizar continua disponível; trocar de tela preserva o tamanho escolhido. Os seletores nativos de arquivos e avisos do Windows mantêm as dimensões do sistema.

Feche o aplicativo, extraia em nova pasta e execute Validar-Janela-R3.2.21.bat. Envie o log. Abra Executar-WinSlim-R3.2.21.bat e alterne Início, Presets, suas quatro abas, Pré-visualização, Aplicação e Conclusão. Confira que as bordas da janela permanecem na mesma posição. Redimensione manualmente e repita a navegação. Abra os dois relatórios para conferir as dimensões padronizadas.

R3.2.20 passou no gate Windows (resultado 0); Aplicação, Conclusão e abertura do relatório foram conferidas em prints. Esta versão preserva backend, catálogo e revisões anteriores. Continua em modo de consulta e demonstração; não aplica alterações nem reinicia o Windows.

Verificações estáticas locais concluídas. Compilação e teste de navegação WPF devem ser executados no Windows.
