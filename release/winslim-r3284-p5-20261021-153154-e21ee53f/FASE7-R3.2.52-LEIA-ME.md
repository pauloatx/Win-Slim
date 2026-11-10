# Win-Slim Suite — R3.2.52

O símbolo × do botão Fechar acompanha o tema no estado de hover, usando a mesma lógica de contraste dos overlays. Corrigido nos três templates e nos relatórios que reutilizam o estilo compartilhado. Modo escuro mantém o texto branco; modo claro usa texto escuro no fundo claro.

Os logs da R3.2.51 mostraram recompilação desnecessária no teste IfNeeded. O build agora compara SHA-256 das entradas, do executável e da configuração, em vez de depender de datas. Mudanças de conteúdo, ausência/corrupção do cache ou marcador de falha obrigam recompilar. O cache é publicado atomicamente apenas após compilação e publicação bem-sucedidas. O log do compilador permanece preservado ao reutilizar o build.

## Conferir

Extraia em nova pasta, execute Validar-Performance-UI-R3.2.52.bat e depois Executar-WinSlim-R3.2.52.bat. Confira hover do botão Fechar nos dois temas e envie logs/captura.

Verificações locais: XML, estrutura C#, contraste, preservação byte a byte da R3.2.51 e integridade do ZIP. O build e a execução WPF ainda precisam de conferência no Windows PowerShell 5.1.

Seleção, catálogo, ações do aplicativo e motor continuam preservados. Nenhuma otimização real do Windows é aplicada nesta revisão.
