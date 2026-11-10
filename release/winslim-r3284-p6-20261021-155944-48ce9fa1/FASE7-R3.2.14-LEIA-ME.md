# Win-Slim R3.2.14 — Correção do Avançado

Corrige os dois painéis do Avançado que ocupavam a mesma coluna na R3.2.13. Opções à esquerda e detalhes à direita. O self-test WPF verifica as colunas, largura útil e ausência de sobreposição.

Feche o aplicativo anterior e extraia em uma nova pasta. Execute Validar-Presets-R3.2.14.bat e envie logs/gate-native-r3.2.14.log. Abra Executar-WinSlim-R3.2.14.bat, vá a Presets > Avançado e teste o modo desenvolvedor. Capturar-Presets-Avancado-R3.2.14.bat salva capturas/Presets-Avancado-R3.2.14.png.

Geral, Logs e Sobre continuam disponíveis. Backend e Dashboard preservados. Nenhuma alteração do Windows é aplicada. Verificação estática local aprovada; compilação, teste WPF e aprovação visual dependem do Windows.
