# Win-Slim R3.2.71 — carregamento progressivo e correção CS4014

Base: R3.2.70 com botão Desativar todos da categoria, validada pelo usuário. Mantém os contratos de aplicação/backup/restauração e a interface aprovada.

## Alterações
- Ao selecionar Logs, a leitura assíncrona agora é aguardada com await e tratamento de exceção na entrada da interface. A compilação trata CS4014 como erro, evitando entregar um executável novo com esse aviso.
- CPU, RAM, Disco e GPU são publicados individualmente assim que cada consulta termina. CPU/RAM não precisam esperar a consulta da GPU para aparecer. O resultado final e as fórmulas foram mantidos; dados indisponíveis continuam nulos, nunca números simulados.
- O inventário do sistema é mostrado antes do processamento de overlays, reutilizando a mesma consulta em memória.
- O XAML de Personalizado é preparado em segundo plano no dispatcher durante a inicialização do bridge. A preparação dos itens usa prioridade Background, sem esperar o estado ContextIdle. A seleção continua aguardando a resolução do preset e a compatibilidade do hardware.
- Mantido um único bridge e as quatro consultas originais, sem novos processos ou consultas duplicadas. A coleta continua pausada fora do Dashboard/minimizada.
- O log registra o tempo até o primeiro indicador e o tempo da coleta completa.

Esta revisão reduz esperas de exibição. Não garante um tempo absoluto: a primeira consulta CIM ainda depende do Windows, drivers e VM.

## Teste no Windows
1. Extraia em uma pasta nova, preservando a R3.2.70 e os backups anteriores.
2. Execute Validar-Aplicacao-Registro-R3.2.71.bat e aguarde Resultado: 0.
3. Abra Executar-WinSlim-R3.2.71.bat. Observe o aparecimento progressivo dos indicadores e abra Personalizado, incluindo uma abertura logo após iniciar o programa.
4. Confira seleção do preset, ativar/desativar categoria, busca, voltar e troca de abas Geral/Logs/Avançado.
5. Envie logs/gate-native-r3.2.71-visivel.log, logs/build-native-r3.2.71.log e logs/ui-native-r3.2.71.log. Não é necessário reaplicar o Modo de Jogo para testar estas mudanças de carregamento.

## Validação desta entrega
XML/XAML e JSON verificados; integridade dos arquivos anteriores e dos contratos de aplicação comparada com a base. Testes PowerShell de publicação progressiva adicionados ao coletor existente. Este ambiente não dispõe de Windows/WPF nem PowerShell; compilação e execução desses testes aguardam o validador no Windows. Os resultados anteriores da R3.2.70 não são apresentados como testes executados na R3.2.71.
