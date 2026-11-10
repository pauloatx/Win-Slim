# Win-Slim R3.2.76 — Pesquisa como ícone

Base: R3.2.75 validada nos testes automatizados e no ciclo de aplicação/restauração na VM; usuário confirmou também a máquina real em 16/10/2026. Essa aprovação não se transfere automaticamente para a nova revisão.

## Novidade
UI-004 — Barra de Pesquisa: Ícone apenas, categoria UI / QoL, passa a ter aplicação real. Usa HKCU\Software\Microsoft\Windows\CurrentVersion\Search, SearchboxTaskbarMode, DWORD 1. A busca continua acessível pelo ícone, menu Iniciar e Win+S. É uma preferência visual, sem promessa de ganho de FPS.

Disponível para Windows cliente 10/11, build 10240 ou superior. A versão local é verificada na revisão e novamente antes de aplicar. Detecção ausente, falha ou Windows Server excluem o ajuste com motivo.

UI-004 conflita com UI-021, que oculta a pesquisa e a Visão de Tarefas. O catálogo mantém esse conflito; a aplicação exige exatamente essa declaração e rejeita ambos no mesmo plano, inclusive se o plano estiver marcado incorretamente como executável. UI-021 continua fora da aplicação real desta etapa. Os contratos antigos continuam rejeitando conflitos não revisados.

Backup completo e verificado antes da escrita; Apply/Verify; reaplicação sem escrita quando já configurado; recuperação em falha parcial; restauração preserva tipo, valor e existência anteriores. Cobertura automatizada para ausência e DWORD 0 (oculto), 2 (caixa) e 3 (ícone e rótulo). Valor 1 já aplicado é coberto pela reaplicação idempotente. Nenhum reinício automático do Explorer.

## Teste desta revisão
1. Extraia em pasta nova e execute Validar-Regressoes.bat. Aguarde Resultado: 0.
2. Abra Executar-WinSlim-R3.2.76.bat. Em Personalizado, selecione somente UI-004 para este teste.
3. Clique Aplicar selecionados, revise e use Criar backup e aplicar. Confirme que a revisão lista somente o ajuste desejado.
4. Confira a pesquisa como ícone e abra-a com Win+S. Se já estava como ícone, nenhuma alteração é esperada. A verificação automática confirma o Registro; para conferir o efeito visual, pode ser necessário salvar o trabalho e sair/entrar na conta manualmente.
5. Em Backup / Restauração, restaure a cópia Antes da aplicação criada nesse teste. Confira o retorno ao modo anterior; se já era ícone, deve continuar assim.
6. Envie a pasta logs/regressao-... e os backups da execução. Faça o ciclo da novidade na VM e na máquina real; não é necessário repetir manualmente os ciclos anteriores do Edge e UI-006.

Se houver política da organização controlando a barra de tarefas, ela pode prevalecer sobre a preferência do usuário. O Win-Slim não altera essas políticas para impor o modo escolhido.

## Regressão
REG-SEARCH-001 integra o gate NativeUI e a rotina de regressão. Usa catálogo, autorização, backup em disco e motores reais com IO de Registro simulado. Cobre destino e hive adulterados, declaração de conflitos, grupo de exclusão, plano conflitante, preservação dos contratos anteriores, limites Windows 10/11, Server, detecção indisponível, rechecagem local, falha de leitura e backup, token, estados originais, idempotência, Undo e recuperação parcial.

O ambiente local não possui PowerShell 5.1, .NET Framework/WPF. A compilação e a execução Windows desta revisão estão PENDENTES. Conferidos aqui: XML/XAML, JSON, hashes, referências dos testes, preservação da base e integridade do ZIP.

## Fontes consultadas
- Microsoft Support, personalização da barra de tarefas: https://support.microsoft.com/pt-br/windows/experience/personalization/customize-the-taskbar-in-windows
- Recurso Taskbar oficial da Microsoft, mapeamento SearchboxTaskbarMode: https://github.com/microsoft/winget-dsc/blob/main/resources/Microsoft.Windows.Developer/Microsoft.Windows.Developer.psm1
