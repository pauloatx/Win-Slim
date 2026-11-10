# Win-Slim Suite — R3.2.26

Personalizado ganhou o botão Ativar todos da categoria, ao lado do título. Ele seleciona todos os ajustes da categoria aberta, incluindo os ocultos por uma busca, preservando as seleções de outras categorias. Quando todos estão selecionados, o botão fica desativado; retirar um ajuste da seleção o habilita novamente.

Chaves ativadas ficam verdes (#00C853), com botão branco à direita. Desativadas continuam cinzas. Restaurar padrão limpa toda a seleção da sessão. As chaves continuam indicando seleção, sem executar mudanças no Windows.

O log da R3.2.25 confirmou compilação, mas revelou uma expectativa incorreta no self-test: buscar PERF-001 encontra esse ajuste e RESP-002, que o cita na descrição. A R3.2.26 mantém a busca em todos os campos e corrige o teste para validar todos os resultados legítimos.

## Validar no Windows

1. Extraia em pasta nova e execute Validar-Personalizado-R3.2.26.bat.
2. Abra Visualizar-Personalizado-R3.2.26.bat.
3. Selecione uma categoria e clique Ativar todos da categoria. Confira chaves verdes, contador e seleções de outras categorias preservadas.
4. Busque um termo que oculte parte da categoria e ative todos; os ocultos também devem ser selecionados.
5. Desative uma chave e confira que o botão volta a ficar disponível.
6. Use Restaurar padrão para limpar as seleções.

A janela continua 1180 × 760 e os 230 ajustes anteriores são preservados. Aplicar selecionados segue desativado até a integração real.

Verificações locais: XML, controles, preservação de todos os arquivos anteriores e integridade do ZIP. Compilação C#5 e teste WPF da nova versão precisam ser executados no Windows. A verificação WPF inclui seleção em lote, filtro, reset e a cor efetiva das chaves.
