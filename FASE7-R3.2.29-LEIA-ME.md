# Win-Slim Suite — R3.2.29

Barras de rolagem arredondadas com destaque laranja em todo o aplicativo. O tema é carregado nos recursos globais da aplicação antes da janela principal e também no self-test: vale para a janela Personalizado, listas de categorias e tweaks, Presets, Logs, pré-visualização, Backup/Restore e janelas de detalhes/relatórios criadas em tempo de execução. Abrange barras verticais e horizontais, inclusive as internas de TextBox e ListBox.

Estilo: largura/altura de 12 px, trilho escuro #191919 arredondado, marcador laranja #FF7A00, hover #FF9A2E, arraste #C85A00. O marcador tem cantos arredondados e tamanho mínimo de 24 px na direção da rolagem. O layout simplificado usa o próprio trilho para avançar/retroceder páginas, sem botões de seta nas extremidades. A roda do mouse e o arraste continuam com os comandos padrão do WPF. As janelas e funcionalidades anteriores são preservadas.

## Conferir no Windows

1. Extraia em pasta nova e execute Validar-Personalizado-R3.2.29.bat.
2. Abra Visualizar-Personalizado-R3.2.29.bat e confira as barras das categorias e dos tweaks. Teste roda do mouse, arraste e clique no trilho.
3. Confira Presets > Logs, a lista da pré-visualização e as abas de Backup/Restore.
4. Abra Ver detalhes / Ver relatório detalhado para conferir a mesma aparência nas janelas auxiliares e nas barras horizontais dos textos longos.

A R3.2.28 passou no gate Windows enviado pelo usuário (resultado 0). Esta revisão precisa de nova compilação/validação visual no Windows. Verificações locais: XML dos recursos/XAML, referências, estrutura C#, dependências obrigatórias, arquivos anteriores intactos, especificação SHA256 e integridade do ZIP. O self-test existente carrega o novo dicionário global ao iniciar a aplicação. A execução de tweaks permanece no modo de demonstração definido nas revisões anteriores.
