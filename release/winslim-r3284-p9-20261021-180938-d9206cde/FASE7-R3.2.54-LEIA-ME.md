# Win-Slim Suite — R3.2.54

Primeira etapa da integração: estado real na pré-visualização.

O Planner existente continua verificando compatibilidade, dependências e conflitos. Agora a pré-visualização também consulta o registro e os serviços do computador, apenas para os ajustes presentes na ordem validada pelo Planner. Mostra contagens de ajustes já configurados, que precisam de mudança, não verificados e de tipos ainda não suportados pela observação.

Os detalhes do plano incluem valores atuais e desejados, falhas por operação, data UTC da consulta e identificação do plano. Falha de acesso não é tratada como valor ausente. Serviço ausente e operações adicionais sem verificação específica aparecem como não verificados. Planos bloqueados antes da consulta indicam estado indisponível.

A observação é somente leitura, não equivale a backup e não autoriza aplicação. Os botões de aplicação continuam demonstrativos. Backup real, execução e restauração são os próximos incrementos. Nenhuma alteração foi feita no Core, Providers ou catálogo.

## Como conferir no Windows

1. Extraia o ZIP em uma nova pasta.
2. Execute `Validar-Performance-UI-R3.2.54.bat` para compilar e executar o gate completo, incluindo os novos testes isolados da observação.
3. Abra `Executar-WinSlim-R3.2.54.bat`, escolha um preset e abra a pré-visualização. Confira o estado atual e os detalhes; também funciona com seleção personalizada.
4. Envie a pasta `logs` se houver erro.

O leitor usa a visão de registro de 64 bits em Windows de 64 bits. HKCU corresponde ao usuário que executa o aplicativo. Os dados representam o momento da consulta; devem ser relidos antes de uma futura aplicação. Outros tipos de ajustes não são executados para obter estado.

Verificado neste ambiente: preservação byte a byte das revisões anteriores, XML/JSON, empacotamento e integridade do ZIP. A compilação C#, execução dos testes PowerShell e conferência visual dependem do Windows e ainda estão pendentes nesta revisão.
