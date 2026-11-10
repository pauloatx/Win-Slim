# Win-Slim Suite — R3.2.25 / Personalizado

Ao clicar em Personalizado, abre uma janela independente de 1180 × 760 com o desenho da referência: categorias e contagens à esquerda; busca, nomes dos tweaks, explicações curtas, riscos e chaves Ativado/Desativado à direita; indicação de reinício e ações no rodapé.

As 230 entradas vêm do CatalogRuntime aprovado, através da nova ação de consulta Catalog no bridge. As descrições curtas são os campos plainName do catálogo, com a descrição completa na dica ao passar o mouse. Não há tweaks fictícios. Categorias equivalentes de Segurança e UI/QoL são agrupadas; categorias CPU/GPU, Apps e Gaming usam nomes curtos. Performance também reúne Responsividade. O número de categorias e as contagens refletem o catálogo real, podendo diferir da imagem conceitual.

Ativado indica seleção, não detecção de estado aplicado no Windows. Todos começam desativados. A seleção permanece ao trocar categoria, buscar ou fechar e reabrir a janela durante a mesma sessão. Restaurar padrão limpa todas as seleções, sem executar Undo. A busca ignora maiúsculas e acentos e procura nome, descrição e ID dentro da categoria atual. Aplicar selecionados permanece indisponível nesta fase de seleção, até integração da pré-visualização/backup/transação. Todos os riscos são visíveis; selecionar um ajuste de risco alto não o executa.

## No Windows

1. Extraia em uma pasta nova; feche versões em execução.
2. Execute Validar-Personalizado-R3.2.25.bat.
3. Execute Visualizar-Personalizado-R3.2.25.bat ou abra Executar-WinSlim-R3.2.25.bat e clique Personalizado.
4. Confira categorias, busca, rolagem, chaves, troca de categoria e Restaurar padrão.
5. Feche e reabra Personalizado: a seleção da sessão deve permanecer.
6. Capturar-Personalizado-R3.2.25.bat gera o PNG para revisão visual.

A janela principal permanece com seu tamanho e sua tela. O botão Voltar e o X fecham somente a janela de seleção. As métricas do Dashboard pausam enquanto Personalizado está aberto.

A R3.2.24 corrigida e todos os arquivos anteriores são preservados byte a byte. Config, manifesto e ambos os XAML foram conferidos no ZIP. O teste Windows adicional verifica as 230 entradas, todas as categorias, busca por ID e sem resultados, seleção após troca de categoria e reset.

Verificação local: XML, dependências, arquivos anteriores, checksums e ZIP. Compilação C#5 e carregamento WPF ainda precisam ser confirmados no Windows; não foram executados no ambiente Linux.
