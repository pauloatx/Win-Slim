# Win-Slim Suite — R3.2.28

## Personalizado a partir de um preset

Ao escolher Equilibrado, Gamer ou Extremo, a resolução real do preset (incluindo overlays aceitos) inicializa as chaves de Personalizado. Verde indica selecionado. É possível retirar ajustes, adicionar outros e ativar todos de uma categoria. Trocar de categoria, buscar ou fechar/reabrir a janela preserva as edições. Escolher outro preset/combinação de overlays inicia uma nova seleção. Uma resolução repetida da mesma combinação não apaga as edições.

Restaurar padrão recupera a seleção inicial do preset escolhido; em arquivos importados, recupera a seleção do arquivo. O botão Voltar tem fundo marrom suave, borda e texto em laranja claro. As dicas dos tweaks e o tamanho da janela são preservados.

Aplicar selecionados está disponível quando a seleção contém ajustes e abre a pré-visualização da lista personalizada. O Planner real verifica o sistema atual, expande dependências e mostra conflitos, ajustes ignorados, risco e reinício. Dependências necessárias podem reaparecer no plano: confira Ver detalhes. Voltar ao Personalizado permite corrigir a seleção. Não existe execução antes dessa revisão.

A aplicação continua como demonstração visual nesta fase. O botão de criar backup/aplicar realmente permanece desativado. Ver aplicação (demonstração) somente funciona quando o Planner considera o plano válido e com trabalho; a simulação personalizada usa os IDs e contagens desse plano, mas não executa transação, não cria backup e não modifica o Windows. A conclusão e o relatório identificam a demonstração.

## Salvar e reutilizar

Salvar preset, na área inferior esquerda, exporta um JSON WinSlim.CustomPreset/v1. Importar preset abre esse arquivo no mesmo aplicativo instalado em outro PC. O documento guarda nome, preset base, IDs selecionados e os níveis de ajustes com várias opções. Não inclui comandos, scripts, caminhos do computador ou dados do hardware. Os níveis originais do preset são mantidos; um ajuste multilevel adicionado manualmente usa seu primeiro nível.

A importação valida todos os campos antes de substituir a seleção: formato, nome, IDs existentes e únicos e níveis válidos. Campos extra, código, IDs desconhecidos/repetidos, níveis fora da faixa e arquivos maiores que 1 MB são recusados. Uma falha mantém a seleção anterior. A compatibilidade é verificada novamente no computador de destino ao abrir a pré-visualização. Use a mesma versão de catálogo; arquivos com IDs ausentes devem ser reexportados de uma versão compatível.

## Conferir no Windows

1. Extraia em uma pasta nova e execute Validar-Personalizado-R3.2.28.bat.
2. Abra a UI e selecione Gamer em Presets. Entre em Personalizado: os 129 ajustes devem estar selecionados (sem overlays).
3. Desative um desses ajustes e ative outro. Troque de categoria e reabra a janela: a edição deve permanecer.
4. Use Restaurar padrão e confira a seleção original. Escolha Equilibrado e Extremo para conferir 105 e 168 IDs.
5. Edite a seleção, salve o JSON e importe-o. Confira IDs e níveis. Leve o arquivo ao outro PC e revise a prévia nesse sistema.
6. Clique Aplicar selecionados, confira o plano e use Voltar ao Personalizado. A execução desta versão permanece demonstrativa.

O self-test inclui os três presets resolvidos pelo backend, edição/preservação, restauração, exportação/importação com níveis, rejeição de entradas inválidas, prévia customizada e os testes anteriores de categorias, dicas, chaves verdes e tamanho. As verificações locais cobrem XML, referências, integridade do pacote e preservação dos arquivos anteriores. A compilação e o gate WPF desta nova revisão precisam ser executados no Windows. A R3.2.27 passou no gate enviado pelo usuário.
