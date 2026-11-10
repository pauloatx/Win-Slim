# Win-Slim Suite — R3.2.58

## Backup concluído

A pré-visualização exibe um cartão verde com **Backup concluído e verificado**, orientação para Backup / Restauração e botão **Ver backups**. O botão abre a lista e seleciona a cópia recém-criada. O aviso aparece somente depois de salvar e conferir o arquivo. A contagem de itens salvos e fora da cobertura permanece visível.

## Restaurar tudo e restaurar um tweak

- **Restaurar tudo** recupera todos os ajustes de registro e serviços cobertos pelo backup selecionado, em qualquer uma das duas abas. Não combina todas as cópias históricas.
- **Restaurar selecionado** recupera somente o tweak escolhido na aba Restaurar por tweak.
- Demonstrações, metadados antigos sem snapshot verificado e ajustes fora da cobertura não habilitam restauração. A exclusão continua indisponível.

Antes de alterar o Windows, o aplicativo confere SHA-256, computador, usuário, arquitetura do registro, IDs e destinos do catálogo atual. A confirmação informa quantos ajustes estão cobertos, quantas operações precisam de mudança e quantos itens não serão restaurados. Mudanças do estado depois da confirmação exigem nova revisão. Execute o aplicativo como administrador para restaurar.

O estado atual é salvo e verificado em uma nova cópia **Antes da restauração / ...** antes da primeira alteração. Cada destino e o resultado completo são verificados. Em caso de falha, o app tenta desfazer as mudanças dessa tentativa e verificar a recuperação; recuperação incompleta é informada explicitamente. Os backups originais são preservados. Uma trava entre instâncias protege operações simultâneas; fechar pela interface fica bloqueado enquanto o processo estiver em andamento.

O registro de progresso fica na pasta `restore-journal` da cópia de recuperação. Se o processo for interrompido externamente, não há retomada automática: a cópia anterior permanece disponível para revisão e restauração. Esta versão não cria ponto de restauração nem restaura arquivos pessoais, apps removidos, scripts, BCD, powercfg ou uma imagem inteira do Windows. Os tipos excluídos são informados nos detalhes.

Os campos `CanApply` e `CanRestore` dos snapshots antigos permanecem falsos: o arquivo sozinho não concede autorização. A R3.2.58 decide a elegibilidade e autoriza cada tentativa mediante verificação e confirmação. R3.2.56/R3.2.57 não são modificadas.

## Continuar com backups da R3.2.57

Extraia a R3.2.58 em uma pasta nova. Para visualizar cópias reais das revisões anteriores, copie a pasta **Backups** da sua R3.2.57 para a pasta da R3.2.58, preservando os arquivos originais. Copie somente seus backups da mesma máquina e usuário; a validação recusará outras identidades.

## Verificação no Windows

1. Execute `Validar-Backup-Restauracao-R3.2.58.bat` nas duas máquinas. Ele valida compilação, interface, integridade das revisões anteriores e testes isolados de restauração, sem alterar registro/serviços reais. Log: `logs\gate-native-r3.2.58.log`.
2. Execute `Validar-Restauracao-Registro-R3.2.58.bat` primeiro na VM. Ele testa o writer real apenas em uma chave HKCU exclusiva e temporária, depois a remove. Não toca configurações do catálogo nem serviços existentes. Log: `logs\restore-registry-r3.2.58.log`.
3. Abra `Executar-WinSlim-R3.2.58.bat`. Crie um backup na pré-visualização e confira o cartão de conclusão e **Ver backups**. Na VM, confira a confirmação e o resultado de **Restaurar tudo** e **Restaurar selecionado**. Se os estados já correspondem à cópia, o app não reescreve esses valores.

Os testes locais em Linux incluem dados tipados, validação de origem, escopo, confirmação, integridade, recuperação de falhas, persistência da cópia anterior, regressões de GPU/backup/prévia e compilação C#5 com referências .NET Framework. Não substituem execução WPF/PowerShell 5.1 no Windows. A restauração de serviços reais ainda precisa de validação no Windows.

## GPU e aplicação de presets

A detecção AMD/NVIDIA/virtual e as restrições de HAGS, MSI e afinidade são preservadas. Serviços GPU opcionais compatíveis continuam com Backup / Apply / Verify / Undo individuais. A aplicação global de presets continua demonstrativa.
