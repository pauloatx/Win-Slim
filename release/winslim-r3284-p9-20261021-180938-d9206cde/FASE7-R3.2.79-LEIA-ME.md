# Win-Slim Suite R3.2.79 — lote QoL

Base: R3.2.78 corrigida, validada nas evidências enviadas: dez suítes aprovadas, aplicação e restauração verificadas, quatro snapshots com hash íntegro. A aprovação anterior não substitui os testes desta build.

## Alterações

Três ajustes existentes passam a ter aplicação real por contrato exato, com cinco valores de Registro:

| ID | Comportamento | Valores | Disponibilidade |
|---|---|---:|---|
| QOL-003 | Mostrar arquivos ocultos e protegidos do sistema no Explorer | Hidden=1, ShowSuperHidden=1 | Windows 10/11 cliente, build 10240+ |
| QOL-008 | Desativar dicas online do aplicativo Configurações | AllowOnlineTips=0 | Windows cliente 1709+, edições Pro/Enterprise/Education/IoT Enterprise suportadas, administrador |
| QOL-012 | Ocultar recentes e frequentes no Acesso Rápido | ShowRecent=0, ShowFrequent=0 | Windows 10/11 cliente, build 10240+ |

QOL-003 não concede acesso adicional nem modifica arquivos. Ele torna arquivos protegidos visíveis. QOL-012 mantém os arquivos e pastas fixadas; não desativa o Acesso Rápido inteiro e não apaga seu histórico. QOL-008 afeta todos os usuários e somente a ajuda/dicas online das Configurações, não todas as sugestões do Windows/Store. Não há promessa de ganho de FPS.

O caminho antigo de AllowOnlineTips no catálogo histórico estava incorreto. O runtime desta versão corrige somente esse contrato em memória, antes de criar o planejador, para HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer. Também exige administrador e compatibilidade local. O caminho incorreto é rejeitado na aplicação. Arquivos dos catálogos e builds anteriores ficam preservados.

Continua obrigatório: revisão explícita, token vinculado à seleção e ao estado atual, backup completo e verificado antes de escrever, leitura após escrita, nenhuma reescrita de valores já configurados, recuperação em falha e restauração do estado real anterior (incluindo valores originalmente ausentes). Não há aplicação automática ao abrir ou importar preset.

O relatório nativo agrupado, a exportação HTML e o layout aprovado da R3.2.78 continuam presentes. Os demais ajustes não revisados permanecem fora da aplicação real.

## Testar o lote junto

1. Extraia em uma pasta nova, mantendo a versão anterior e seus backups.
2. Execute Validar-Regressoes.bat. Esta build exige onze suítes e Resultado: 0. O teste automatizado usa IO simulado para este lote; não altera essas preferências no computador.
3. Abra Executar-WinSlim-R3.2.79.bat. Em Personalizado, use Importar preset e selecione Teste-Lote-QoL-R3.2.79.json.
4. Revise a seleção: são três ajustes. Na revisão real, até cinco valores serão aceitos. Sem edição suportada ou elevação, QOL-008 fica fora; os outros dois somam quatro valores. Não force sua inclusão.
5. Use Criar backup e aplicar; confira o resultado agrupado. Reabra o Explorer e confira arquivos ocultos/protegidos e recentes/frequentes. Para QOL-008, a verificação automática confirma o Registro; a disponibilidade de conteúdo nas Configurações depende do Windows. Não basta uma leitura correta para declarar todo efeito visual aprovado.
6. Em Backup / Restauração, selecione o backup Antes da aplicação deste teste e use Restaurar tudo. Ele restaura os valores cobertos dessa cópia, não todas as cópias existentes. Confira o retorno das preferências. O estado anterior real é restaurado, sem assumir os padrões do catálogo.
7. Envie a pasta logs/regressao-... e o backup/relatório do ciclo para revisão. Não precisa repetir os lotes manuais antigos.

## Regressão e limites

REG-QOLBATCH-001 testa os três contratos e os cinco destinos, adulteração de cada campo, operações extras/parciais, caminho antigo incorreto, normalização idempotente, versões/edições, ausência de detecção, Server e elevação. Testa Apply/Verify/Undo por ajuste e em lote, estados existentes e ausentes, idempotência, backup com todas as operações, leitura/backup falhos e recuperação após cada uma das cinco escritas. As dez suítes anteriores continuam exigidas.

Verificação local disponível: seis testes do empacotador, JSON/XML, preservação da base, contratos estáticos e hashes. PowerShell 5.1, .NET Framework e WPF não estão disponíveis neste ambiente; compilação e onze suítes Windows desta build estão PENDENTES. O usuário não precisa instalar Python.

## Referências da revisão

- Microsoft, Settings Policy CSP / AllowOnlineTips: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-settings#allowonlinetips
- Microsoft, WindowsDeveloperConfig (Hidden, ShowRecent, ShowFrequent): https://github.com/microsoft/WindowsDeveloperConfig/blob/main/windows-dev-config/README.md
- Microsoft, configurações do Windows (mostrar arquivos protegidos): https://github.com/MicrosoftDocs/windows-dev-docs/blob/docs/hub/apps/develop/settings/settings-common.md

Essas referências não substituem a validação de comportamento na versão do Windows testada. Sem reinício automático do Explorer, encerramento da sessão ou reinício do computador.
