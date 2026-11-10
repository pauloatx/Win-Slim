# Win-Slim R3.2.13 — Abas dentro de Presets

R3.2.12 passou no gate técnico e a captura mostra os dois cortes corrigidos. A solicitação atual adiciona Geral, Avançado, Logs e Sobre dentro de Presets, seguindo a referência de Configurações/Avançado.

Geral mantém os três perfis e 16 overlays. Avançado oferece modo desenvolvedor e opções reais de exibição dos metadados da seleção, exportação JSON, relatório automático opcional e log detalhado. Classificação experimental e incompatibilidade individual estão desabilitadas porque ainda não foram integradas; elegibilidade dos overlays continua no bridge existente. Dry Run e confirmação de risco são obrigatórios nesta fase. Nenhum comando exibido é executado.

Opções persistem em config/presets-ui-r3.2.13.json. O relatório automático, quando habilitado, vai para reports/preset-selection-latest.json. Logs lê as últimas 200 linhas de logs/ui-native-r3.2.13.log e permite exportar o arquivo. Sobre apresenta versão, catálogo e limites da fase.

## Testes no Windows
1. Feche o Win-Slim, extraia em nova pasta e execute Validar-Presets-R3.2.13.bat. Envie logs/gate-native-r3.2.13.log.
2. Abra Executar-WinSlim-R3.2.13.bat e vá a Presets. Alterne Geral/Avançado/Logs/Sobre; voltar a Geral mantém a seleção.
3. Em Avançado, ative Modo desenvolvedor e teste cada opção de campo. Exporte configurações e confira o JSON. Desative modo desenvolvedor e confirme que detalhes são ocultados.
4. Se habilitar relatório automático, volte a Geral e mude o preset; confira reports/preset-selection-latest.json.
5. Em Logs, atualize e exporte. Confira a seleção registrada. A opção Log detalhado adiciona fingerprint e quantidade.
6. Feche e reabra; confira as opções de exibição persistidas. Consentimento de alto risco não persiste.
7. Capturar-Presets-R3.2.13.bat captura Geral. Capturar-Presets-Avancado-R3.2.13.bat, Capturar-Presets-Logs-R3.2.13.bat e Capturar-Presets-Sobre-R3.2.13.bat capturam as outras abas.

Dashboard preservado. Catálogo/backend congelados. Verificações locais estáticas; build, interação e visual desta revisão pendentes no Windows.
