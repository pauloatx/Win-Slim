# Win-Slim Suite — R3.2.34

Avançado e Logs foram movidos de Presets para Configurações. Presets agora apresenta diretamente os perfis e overlays, sem as antigas abas. Configurações contém Geral, Avançado e Logs; os painéis funcionais substituem o antigo protótipo duplicado.

Modo desenvolvedor, opções de exibição, detalhes da seleção atual, exportação de configurações, atualização e exportação de logs mantêm suas ações. Mudar de tela ou aba preserva a seleção de preset e as opções. Sobre continua no menu lateral, sem aba redundante em Configurações.

## Conferir no Windows

1. Extraia em pasta nova e execute Validar-Configuracoes-R3.2.34.bat.
2. Abra Executar-WinSlim-R3.2.34.bat. Em Presets, confira os perfis e overlays sem as abas.
3. Abra Configurações e teste Geral, Avançado e Logs. Ative o modo desenvolvedor, confira os metadados da seleção e teste exportação das preferências e logs.
4. Volte a Presets: a seleção deve continuar igual. Retorne a Configurações: a última aba e suas opções devem permanecer.
5. Visualizar-Configuracoes-R3.2.34.bat abre diretamente Avançado. Capturar-Configuracoes-Avancado-R3.2.34.bat e Capturar-Configuracoes-Logs-R3.2.34.bat geram PNGs.

R3.2.33 passou no gate Windows enviado pelo usuário (resultado 0). Foram verificados localmente XML, nomes, localização das abas na árvore de controles, estrutura C#, preservação dos arquivos anteriores e ZIP. O self-test verifica navegação das três abas e ausência das abas migradas em Presets. Compilação e renderização WPF da nova revisão precisam ser validadas no Windows. Execução continua em modo de consulta/demonstração.
