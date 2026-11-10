# Win-Slim Suite — R3.2.59

## Correções dos testes enviados

Os pacotes test(7) e test(8) registraram a mesma falha da R3.2.58: a restauração recusava operações únicas com “Operações do backup diferem do catálogo”. A leitura agora mantém listas como arrays no Windows PowerShell 5.1, inclusive quando existe somente uma operação. Os destinos, tipos, identidade e quantidade de operações continuam validados; nenhum bloqueio de segurança foi removido. A mesma normalização foi aplicada à captura.

O aviso verde estava dentro de uma linha de altura fixa e cortava o botão Ver backups. O painel agora cresce conforme o conteúdo, com o botão ao lado da mensagem. A lista de categorias usa o espaço restante com rolagem e o rodapé permanece separado. O gate WPF passa a conferir os limites nos temas claro/escuro, PT-BR/EN, dois tamanhos e com/sem aviso.

Nos logs enviados, os 19 testes de registro da R3.2.58 passaram, inclusive a recuperação de uma falha após escrita. Isso não confirma a restauração completa de serviços reais. A R3.2.59 amplia o teste Windows para conferir operações únicas e a diferença entre restauração individual e completa, apenas na mesma chave temporária HKCU.


## Backup concluído

A pré-visualização exibe um cartão verde com **Backup concluído e verificado**, orientação para Backup / Restauração e botão **Ver backups**. O botão abre a lista e seleciona a cópia recém-criada. O aviso aparece somente depois de salvar e conferir o arquivo. A contagem de itens salvos e fora da cobertura permanece visível.

## Restaurar tudo e restaurar um tweak

- **Restaurar tudo** recupera todos os ajustes de registro e serviços cobertos pelo backup selecionado, em qualquer uma das duas abas. Não combina todas as cópias históricas.
- **Restaurar selecionado** recupera somente o tweak escolhido na aba Restaurar por tweak.
- Demonstrações, metadados antigos sem snapshot verificado e ajustes fora da cobertura não habilitam restauração. A exclusão continua indisponível.

Antes de alterar o Windows, o aplicativo confere SHA-256, computador, usuário, arquitetura do registro, IDs e destinos do catálogo atual. A confirmação informa quantos ajustes estão cobertos, quantas operações precisam de mudança e quantos itens não serão restaurados. Mudanças do estado depois da confirmação exigem nova revisão. Execute o aplicativo como administrador para restaurar.

O estado atual é salvo e verificado em uma nova cópia **Antes da restauração / ...** antes da primeira alteração. Cada destino e o resultado completo são verificados. Em caso de falha, o app tenta desfazer as mudanças dessa tentativa e verificar a recuperação; recuperação incompleta é informada explicitamente. Os backups originais são preservados. Uma trava entre instâncias protege operações simultâneas; fechar pela interface fica bloqueado enquanto o processo estiver em andamento.

O registro de progresso fica na pasta `restore-journal` da cópia de recuperação. Se o processo for interrompido externamente, não há retomada automática: a cópia anterior permanece disponível para revisão e restauração. Esta versão não cria ponto de restauração nem restaura arquivos pessoais, apps removidos, scripts, BCD, powercfg ou uma imagem inteira do Windows. Os tipos excluídos são informados nos detalhes.

Os campos `CanApply` e `CanRestore` dos snapshots antigos permanecem falsos: o arquivo sozinho não concede autorização. A R3.2.59 decide a elegibilidade e autoriza cada tentativa mediante verificação e confirmação. Todas as revisões anteriores, inclusive R3.2.58, são preservadas sem alterações.

## Continuar com backups anteriores

Extraia a R3.2.59 em uma pasta nova. Para visualizar cópias reais das revisões anteriores, copie a pasta **Backups** da sua R3.2.57 ou R3.2.58 para a pasta da R3.2.59, preservando os arquivos originais. Copie somente seus backups da mesma máquina e usuário; a validação recusará outras identidades.

## Verificação no Windows

1. Execute `Validar-Backup-Restauracao-R3.2.59.bat` nas duas máquinas. Ele valida compilação, interface, integridade das revisões anteriores e testes isolados de restauração, sem alterar registro/serviços reais. Log: `logs\gate-native-r3.2.59.log`.
2. Execute `Validar-Restauracao-Registro-R3.2.59.bat` primeiro na VM. Ele testa o writer real apenas em uma chave HKCU exclusiva e temporária, depois a remove. Não toca configurações do catálogo nem serviços existentes. Log: `logs\restore-registry-r3.2.59.log`.
3. Abra `Executar-WinSlim-R3.2.59.bat`. Crie um backup na pré-visualização e confira o cartão de conclusão e **Ver backups**. Na VM, confira a confirmação e o resultado de **Restaurar tudo** e **Restaurar selecionado**. Se os estados já correspondem à cópia, o app não reescreve esses valores.

Os testes locais em Linux incluem dados tipados, validação de origem, escopo, confirmação, integridade, recuperação de falhas, persistência da cópia anterior, regressões de GPU/backup/prévia e compilação C#5 com referências .NET Framework. Não substituem execução WPF/PowerShell 5.1 no Windows. A restauração de serviços reais ainda precisa de validação no Windows.

## GPU e aplicação de presets

A detecção AMD/NVIDIA/virtual e as restrições de HAGS, MSI e afinidade são preservadas. Serviços GPU opcionais compatíveis continuam com Backup / Apply / Verify / Undo individuais. A aplicação global de presets continua demonstrativa.
