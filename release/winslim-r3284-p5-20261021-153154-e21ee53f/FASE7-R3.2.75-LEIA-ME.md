# Win-Slim R3.2.75 — Encerrar tarefa na barra de tarefas

Base: R3.2.74. Usuário confirmou validação nos dois ambientes em 16/10/2026. A nova revisão ainda requer validação Windows.

## Novidade
UI-006, na categoria UI / QoL de Personalizado, pode ser aplicado pelo fluxo real. Habilita a opção Encerrar tarefa ao clicar com o botão direito no ícone de um aplicativo aberto na barra de tarefas. Não encerra processos durante a aplicação. Usar posteriormente Encerrar tarefa força o fechamento e pode perder trabalho não salvo; teste a presença da opção sem encerrar documentos importantes.

Contrato: HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings, TaskbarEndTask, DWORD 1. Baixo risco para a alteração da preferência; restauração preserva o valor e a existência originais. Não é uma otimização de FPS.

Critério conservador desta versão: Windows cliente, build 22631 ou superior (Windows 11 23H2+). Builds anteriores são excluídas com motivo mesmo quando o recurso possa existir por atualização. Falha de detecção também exclui. O backend verifica o sistema local novamente antes da escrita, independentemente dos dados enviados pela interface. O catálogo e os presets existentes não foram alterados; a autorização real permanece restrita aos contratos revisados.

Backup completo e verificado antes de escrever; verificação no Registro; reaplicação idempotente; recuperação em caso de falha parcial; restauração da ausência original ou DWORD anterior. A revisão mostra a observação sobre fechamento forçado somente quando UI-006 está incluído. Sem reinício automático do Explorer.

## Como validar esta versão
1. Extraia em pasta nova. Execute Validar-Regressoes.bat e aguarde Resultado: 0. Isso valida esta revisão, sem exigir repetir manualmente os testes já aprovados do Edge.
2. Abra Executar-WinSlim-R3.2.75.bat na mesma conta usada no teste.
3. Em Personalizado, selecione UI-006. Na revisão de aplicação real, confirme a lista: para testar somente a novidade, deixe apenas UI-006 selecionado antes de prosseguir.
4. Clique Criar backup e aplicar. Se já estava habilitado, o resultado sem alterações é esperado.
5. Abra um aplicativo de teste e confira Encerrar tarefa no menu de seu ícone na barra. Não é necessário acioná-lo. Se a interface do Windows não atualizar, salve o trabalho e saia/entre na conta manualmente.
6. Restaure o backup Antes da aplicação criado nessa execução. A opção deve retornar ao estado anterior; se já existia, deve continuar habilitada.
7. Em caso de erro, envie a pasta logs/regressao-... desta revisão e logs/ui-native-r3.2.75.log.

## Testes
REG-ENDTASK-001 usa catálogo, autorização, backup em disco e motores reais com acesso ao Registro simulado. Cobre contratos adulterados, hive, limites de build, Server, detecção ausente/falha, Planner Windows 10/11, compatibilidade alterada após revisão, falha de leitura/backup, token consumido, ausência/DWORD 0, idempotência, Undo e recuperação de escrita parcial. Integra a rotina de regressão existente e o gate NativeUI.

Verificações locais: XML/XAML, JSON, hashes, caminhos dos testes e preservação dos arquivos da base. PowerShell 5.1, compilador .NET Framework e WPF não estão disponíveis neste ambiente; a execução Windows está pendente. Não atribuir aprovação da R3.2.74 à R3.2.75.

## Decisão de escopo e fontes
Políticas adicionais do Edge, como SleepingTabsEnabled, não foram liberadas porque a documentação informa limitações para perfis conectados com conta Microsoft. O lote EDGE-001/002 permanece intacto.
- https://learn.microsoft.com/en-us/windows/advanced-settings/
- https://github.com/microsoft/WindowsDeveloperConfig/blob/main/src/windows-dev-config/README.md
- https://blogs.windows.com/windows-insider/2023/08/18/announcing-windows-11-insider-preview-build-22621-2199-and-22631-2199-beta-channel/
- https://learn.microsoft.com/pt-br/deployedge/microsoft-edge-browser-policies/sleepingtabsenabled
