# Win-Slim Suite — R3.2.32

## Navegação em uma janela

Personalizado e Detalhe do tweak agora são páginas UserControl exibidas na janela principal, substituindo seu conteúdo. Não existe Show, Activate, ShowDialog ou criação de uma segunda Window para essas páginas. O cabeçalho de cada tela controla a mesma janela principal: minimizar, maximizar, arrastar e fechar o aplicativo.

O mesmo tratamento foi aplicado aos relatórios de conclusão, detalhes da pré-visualização e detalhes de backups: são páginas internas com Voltar, sem novas janelas. Os seletores padrão de arquivo e avisos de erro continuam aparecendo quando necessários.

Voltar dos detalhes recupera a mesma página Personalizado, mantendo categoria, busca, seleção e posição da lista. A página é reutilizada em vez de recriada. Voltar do Personalizado recupera a tela de origem. Aplicar continua seguindo para a prévia na mesma janela. A seleção editada, exportação/importação, chaves, dicas, metadados reais, barras arredondadas laranja e modo demonstrativo são preservados. O tamanho e o estado maximizado da janela principal não são alterados pela navegação.

## Conferir no Windows

1. Extraia em pasta nova e execute Validar-Detalhe-Tweak-R3.2.32.bat.
2. Abra Executar-WinSlim-R3.2.32.bat, vá a Personalizado e abra vários tweaks, retornando com Voltar.
3. Confira que apenas uma janela do aplicativo permanece aberta.
4. Faça uma busca, escolha uma categoria, role a lista e abra/feche os detalhes. O contexto deve permanecer.
5. Confira a prévia, os relatórios e os detalhes dos backups: devem substituir a tela atual e voltar na mesma janela.
6. Maximize ou redimensione a janela e repita a navegação.

A R3.2.31 passou no gate Windows enviado pelo usuário (resultado 0). O self-test da nova revisão verifica troca entre Personalizado, detalhes e relatório, recuperação da mesma página e seleção/busca/categoria, e ausência de aumento em Application.Windows.Count. As validações anteriores são preservadas e foram adaptadas para a janela principal. Verificações locais: XML, tipos das páginas, referências, estrutura C#, ausência de criação/abertura de Windows auxiliares no controlador, preservação dos arquivos anteriores, dependências e ZIP. Compilação e validação WPF/visual desta revisão precisam ser feitas no Windows.
