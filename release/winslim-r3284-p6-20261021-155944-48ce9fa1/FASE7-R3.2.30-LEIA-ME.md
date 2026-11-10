# Win-Slim Suite — R3.2.30

## Detalhe de um tweak

Em Personalizado, clique no nome, descrição, ícone, risco ou espaço da linha para abrir uma janela própria. Clicar na chave continua apenas ativando/desativando a seleção. É possível focar a linha com Tab e abrir os detalhes com Enter ou Espaço. A dica ao manter o mouse parado continua disponível.

A janela segue a composição da imagem de referência: fundo escuro, contorno laranja arredondado, cabeçalho da marca, título do ajuste, selo âmbar, estado em verde/cinza, descrição, sete linhas de informação (risco, reinício, rollback, compatibilidade, hardware, dependências e conflitos), aviso âmbar e botões Desfazer / Aplicar. A dimensão inicial continua 1180 × 760, mínimo 1040 × 680, conforme a padronização anterior. O conteúdo rola quando necessário e usa as barras arredondadas laranja globais.

Os dados vêm do catálogo real de 230 ajustes; não são os valores fictícios da imagem. O selo mostra Experimental somente se o catálogo assim identificar o ajuste; nos demais casos mostra a categoria. Ativo significa selecionado nesta fase, não comprovação de alteração já executada no Windows. Risco e reinício são do catálogo; compatibilidade e hardware vêm da verificação do sistema atual; dependências e conflitos mostram os nomes dos IDs relacionados. Rollback aparece como previsto no catálogo, sem afirmar que um backup já existe. Avisos usam as notas reais do ajuste quando presentes, com complemento de compatibilidade e rollback.

Desfazer retira apenas esse ID da seleção e atualiza a chave e o estado. Não executa Undo do Windows nesta demonstração. Aplicar seleciona esse ID e abre sua pré-visualização individual pelo Planner: dependências, conflitos e bloqueios continuam visíveis, e os níveis do ajuste são preservados. Os demais IDs do preset personalizado permanecem selecionados; essa prévia individual não os executa. A aplicação real continua indisponível, como nas revisões anteriores.

## Conferir no Windows

1. Extraia em pasta nova e execute Validar-Detalhe-Tweak-R3.2.30.bat.
2. Abra Visualizar-Personalizado-R3.2.30.bat e clique em uma linha.
3. Confira título, descrição, estado, metadados, aviso e as cores da referência.
4. Use Desfazer em um ajuste selecionado e confira a chave desligada na janela Personalizado.
5. Clique Aplicar para conferir a prévia individual, mantendo o modo demonstrativo.
6. Clique na chave de outro ajuste: ela deve alternar sem abrir os detalhes.
7. Visualizar-Detalhe-Tweak-R3.2.30.bat abre diretamente HPET (PERF-004); Capturar-Detalhe-Tweak-R3.2.30.bat salva sua imagem em reports.

A R3.2.29 passou no gate Windows enviado pelo usuário (resultado 0). O self-test desta revisão carrega os detalhes de dois ajustes reais pelo bridge, confere os sete campos e a dimensão, testa a retirada da seleção e recusa IDs desconhecidos; os testes anteriores continuam presentes. Verificações locais: XML, referências de controles/recursos, estrutura C#, contrato de consulta, dependências de build, arquivos anteriores intactos e integridade do ZIP. Compilação, self-test WPF e comparação visual R3.2.30 precisam ser feitos no Windows.
