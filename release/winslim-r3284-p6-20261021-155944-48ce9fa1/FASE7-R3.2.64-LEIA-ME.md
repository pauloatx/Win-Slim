# Win-Slim Suite — R3.2.64

Esta revisão corrige uma expectativa antiga do self-test: o botão Criar backup passou a ocupar 149 DIPs na R3.2.62 (coluna de 165 menos margens), mas uma verificação posterior ainda exigia pelo menos 200. Agora os dois botões de ação precisam estar desabilitados sem um plano válido, visíveis e com espaço suficiente para o texto, padding e bordas. Todos os botões do rodapé também passam pela verificação de legibilidade em claro/escuro, PT-BR/inglês e nos dois tamanhos de janela. As verificações de sobreposição foram mantidas.

O log enviado da R3.2.63 confirmou 55 testes do fluxo, 12 testes de escrita/verificação/recuperação em chave HKCU temporária e 50 testes de restauração. A compilação também passou. O self-test WPF parou na expectativa de largura antiga; portanto a validação completa ainda deve ser repetida.

Esta correção não altera o motor nem o desenho da interface. A aplicação real continua limitada aos cinco ajustes abaixo.

## Escopo liberado

| ID | Preferência | Tipo |
|---|---|---|
| PERF-001 | Atraso de abertura dos menus: 100 ms | String |
| UI-007 | Abrir o Explorer em Este PC | DWORD |
| UI-008 | Mostrar extensões dos arquivos | DWORD |
| UI-009 | Desativar transparência | DWORD |
| UI-016 | Mostrar caminho completo no título do Explorer | DWORD |

São cinco preferências por usuário, classificadas como baixo risco no catálogo e compatíveis com Windows 10/11. O app aplica apenas as que estiverem na sua seleção. A revisão mostra a lista, os valores desejados, quantas precisam de mudança e quais ficaram de fora, incluindo itens ignorados pelo planejador. A leitura/verificação do Registro não garante atualização imediata da interface do Windows; pode ser necessário sair e entrar na conta. O app não reinicia o Explorer nem o computador automaticamente.

HAGS, MSI, afinidade, BCD, remoção de aplicativos e a aplicação geral de serviços não foram liberados neste fluxo. As ações individuais de serviços GPU já existentes continuam separadas.

## Como testar primeiro na VM

1. Extraia o ZIP em uma pasta nova.
2. Execute `Validar-Aplicacao-Registro-R3.2.64.bat`. Aguarde o resumo. Ele compila a UI, executa os testes anteriores, testa o novo motor com IO simulado e testa escritas reais apenas numa chave HKCU temporária exclusiva, removida ao terminar. Não aplica preferências do catálogo.
3. Se a validação terminar com resultado 0, abra `Executar-WinSlim-R3.2.64.bat` como administrador.
4. Em Personalizado, deixe somente **UI-008 — Extensões de arquivo** selecionado para o primeiro teste. Use a busca para localizar o ajuste e confira o total selecionado.
5. Clique em Aplicar selecionados para abrir a prévia. Clique em **Revisar aplicação real**. Confira a lista e, somente então, **Criar backup e aplicar**.
6. Confira o resultado. Se a extensão já estiver configurada, o resultado correto é “já configurado”, sem uma nova escrita.
7. Abra **Ver backups**. Selecione a cópia identificada como **Antes da aplicação**. Use **Restaurar tudo** para recuperar todos os valores daquela cópia, ou a aba por tweak para restaurar só um. Isso não restaura o Windows inteiro.
8. Envie a pasta `logs` e o `outcome.json` da aplicação. Depois desse ciclo individual, teste dois ou três ajustes na VM antes da máquina real.

Para manter backups antigos, copie a pasta `Backups` preservando sua estrutura. Eles só podem ser restaurados na máquina, usuário e arquitetura de Registro originais.

## Proteções implementadas

- Planejamento e compatibilidade reavaliados na confirmação; destinos/tipos/valores presos aos cinco contratos revisados. O cliente transmite tokens, não comandos ou caminhos de escrita.
- Confirmação de uso único, válida por cinco minutos, ligada ao plano, à identidade e ao estado observado.
- Backup completo do escopo, verificado e persistido antes da primeira escrita. Backup parcial ou falha de disco bloqueiam a aplicação.
- Exclusão mútua com restauração e ações GPU. Navegação/fechamento ficam bloqueados enquanto a transação é executada; a UI permanece responsiva.
- Progresso emitido pelo backend conforme backup e verificações reais; nenhum temporizador simula o resultado.
- Estados já configurados não são regravados. Verificação após cada operação e ao final do lote.
- Falhas tentam recuperar os destinos tocados em ordem inversa, incluindo uma escrita parcialmente executada. Recuperação incompleta é informada explicitamente.
- O bridge não encerra o processo de uma operação mutável por timeout. Uma interrupção externa ou perda de energia não permite prometer rollback automático: o registro persistido permite identificar a tentativa, localizar o backup e exigir recuperação antes de outra aplicação.
- Não há botão de cancelamento durante a escrita nesta primeira etapa; aguarde a verificação/recuperação. O relatório é salvo junto ao backup.

## Arquivos de diagnóstico

- `logs\gate-native-r3.2.64-visivel.log`: validação completa do Windows.
- `logs\build-native-r3.2.64.log`: compilação.
- `logs\ui-native-r3.2.64.log`: interface e resultado da aplicação.
- `Backups\UI\<id>\snapshot.json` e `manifest.json`: backup verificável.
- `Backups\UI\<id>\apply-journal\intent.json`: escopo e estado anterior.
- `Backups\UI\<id>\apply-journal\outcome.json`: resultado real e exclusões.

## Validação desta entrega

Sintaxe PowerShell e compilação C#5 contra referências .NET Framework 4.8 conferidas localmente. Motor, XAML, temas e traduções comparados com R3.2.63 e preservados, exceto identificações da revisão. O ambiente local não executa WPF nem Windows PowerShell 5.1. Repita `Validar-Aplicacao-Registro-R3.2.64.bat` na VM e envie a pasta logs antes do teste manual pela interface.
