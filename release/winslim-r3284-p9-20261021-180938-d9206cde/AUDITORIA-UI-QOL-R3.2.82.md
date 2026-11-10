# Atualização R3.2.82

QOL-003, QOL-008 e QOL-012 agora têm contratos revisados e regressão própria. A liberação requer o gate Windows desta build. QOL-008 usa caminho corrigido no runtime e exige edição compatível/elevacão. Os demais itens abaixo mantêm o estado da auditoria anterior.

# Auditoria UI / QoL — R3.2.82

Categoria inteira revisada: 39 ajustes. Este lote libera seis IDs novos, preserva os contratos existentes e mantém os demais fora da aplicação real deste fluxo.

| ID | Ajuste | Situação | Motivo / condição |
|---|---|---|---|
| UI-001 | Modo Escuro - Ativar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
| UI-002 | Widgets - Desativar | Pendente | TaskbarDa não tem efeito uniforme em versões atuais; requer detecção da superfície e contrato específico. |
| UI-003 | Botão de Chat (Teams pessoal) - Ocultar | Pendente | Botão de Chat pertence a versões antigas do Windows 11; requer limite superior e detecção do componente. |
| UI-004 | Barra de Pesquisa - Ícone apenas | Contrato já liberado | Contrato específico já disponível. |
| UI-005 | Copilot - Desativar por completo via ViVeTool | Pendente | ViVeTool e recursos internos não seguem o contrato de preferências de Registro deste lote. |
| UI-006 | Botão 'Encerrar tarefa' na barra de tarefas - Ativar | Contrato já liberado | Contrato específico já disponível. |
| UI-007 | Explorer abrir em 'Este PC' | Contrato já liberado | Contrato específico já disponível. |
| UI-008 | Extensões de arquivo - Sempre mostrar | Contrato já liberado | Contrato específico já disponível. |
| UI-009 | Transparência - Desativar | Contrato já liberado | Contrato específico já disponível. |
| UI-010 | Segundos no relógio - Mostrar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
| QOL-001 | Pasta Objetos 3D - Ocultar do Explorer | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-002 | Pastas de biblioteca no Navegador - Limpar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-003 | Arquivos ocultos e de sistema - Mostrar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-004 | Windows Spotlight (tela de bloqueio) - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-005 | Tela de bloqueio - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-006 | Menu de contexto clássico (Windows 11) - Restaurar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-007 | Manutenção automática agendada - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-008 | Dicas e sugestões online do Windows - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-009 | 'Get tips' (Soft Landing) - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-010 | Central de Ações (notificações do sistema) - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-011 | Num Lock ativo na tela de login | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-012 | Acesso Rápido (Quick Access) - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| UI-011 | Botao Copilot na barra de tarefas - Ocultar | Pendente | Copilot tornou-se aplicativo separado em versões atuais; ShowCopilotButton não confirma ausência do aplicativo. |
| UI-012 | Secao Recomendados do menu Iniciar - Ocultar | Pendente | Ocultar toda a seção Recomendados por esse valor não tem comportamento documentado uniforme. |
| UI-013 | Visualizador de Fotos do Windows (classico) - Habilitar | Pendente | Associações de arquivos e script exigem backup e verificação próprios. |
| UI-014 | Detalhes de operacoes de arquivo - Sempre mostrar | Contrato já liberado | Contrato específico já disponível. |
| UI-015 | Aero Shake (minimizar ao sacudir janela) - Desativar | Contrato já liberado | Contrato específico já disponível. |
| UI-016 | Caminho completo na barra de titulo do Explorer | Contrato já liberado | Contrato específico já disponível. |
| UI-017 | Aceleracao do mouse - Desativar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
| UI-018 | News and Interests (Windows 10) - Ocultar | Pendente | Recurso específico do Windows 10; componente pode não existir em LTSC. Precisa detecção e teste de superfície. |
| UI-019 | Meet Now (Windows 10) - Ocultar | Pendente | Meet Now depende do componente e da versão do Windows 10. Precisa detecção de disponibilidade. |
| UI-020 | Texto 'Atalho' em novos atalhos - Remover | Pendente | Script e valor binário exigem contrato e verificação próprios. |
| QOL-013 | Mensagens detalhadas de inicializacao/desligamento | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| QOL-014 | 'Obter ainda mais do Windows' (Welcome Experience) - Desativar | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| UI-021 | Busca e Task View - Ocultar da Taskbar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
| UI-022 | Game Bar - Desativar Painel de Overlay Inicial | Pendente | ShowStartupPanel depende da versão do Game Bar; precisa confirmação de suporte no componente instalado. |
| QOL-015 | Explorer - Link "Pesquisar novamente na Internet" removido | Pendente | Requer contrato individual revisado e teste de efeito/Undo; permanece apenas selecionável. |
| UI-023 | Search Highlights - Desativar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
| UI-024 | Sites personalizados na seção Recomendados - Ocultar | Novo neste lote | Contrato de Registro revisado; compatibilidade definida no leia-me. |
