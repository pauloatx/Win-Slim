# Win-Slim Suite — R3.2.24

Backup/Restauração segue a referência: tema escuro, painel contornado em laranja, abas Backups e Restaurar por tweak, tabela com ícones e status, ações Detalhes/Restaurar/Excluir. Janela permanece 1180 × 760 em todas as telas.

## Testar no Windows

1. Execute `Validar-Backups-R3.2.24.bat` (build .NET Framework + regressão + self-test WPF).
2. Execute `Visualizar-Backups-R3.2.24.bat` para avaliar os quatro exemplos da referência.
3. Selecione outro backup, abra Detalhes e troque a aba Restaurar por tweak. A lista de ajustes acompanha o backup selecionado.
4. Use `Capturar-Backups-R3.2.24.bat` e `Capturar-Backups-Por-Tweak-R3.2.24.bat` para gerar PNGs.
5. Em Backup/Restauração, clique Ver backups reais ou Atualizar para sair da demonstração.

## Comportamento

A demonstração usa dados ilustrativos claramente identificados. Não cria backups nem executa alterações. Restaurar e Excluir permanecem indisponíveis nesta fase de consulta.

O inventário real lê somente metadados JSON em `Transactions/<id>/transaction.json` e `operations.json`, filtrando transações Apply com referências de backup. A coluna Alterações conta essas referências; não certifica alterações aplicadas. Payloads CLIXML não são carregados. O perfil fica Não informado porque o contrato atual da transação não persiste essa informação. A integridade fica Não verificado: a presença de uma referência não comprova validade da cópia. Backups em raízes personalizadas não entram neste inventário inicial. Registros inválidos são contabilizados sem impedir a leitura dos demais; falhas de acesso à raiz são exibidas.

R3.2.23 e catálogo/backend anteriores são preservados byte a byte. Restauração por tweak e exclusão reais dependem da integração futura com a transação canônica.

Verificações locais: XML e integridade dos arquivos/pacote. Compilação C#, carregamento WPF e inspeção visual precisam ser executados no Windows; não foram executados neste ambiente Linux.

## Correção do pacote R3.2.24

O pacote corrigido inclui `WinSlim.UI.Native.exe.config` e `WinSlim.NativeUI.manifest`, omitidos na primeira entrega. O log do Windows mostrou falha de pré-requisito antes da compilação C#. A correção mantém o layout e as funcionalidades e deve ser validada novamente no Windows. Extraia em uma pasta nova e execute `Validar-Backups-R3.2.24.bat`.
