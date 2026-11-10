# Win-Slim R3.2.73 — resultados de regressão e thread da aba Logs

Nos logs enviados da R3.2.72, o caso de compilação, o coletor de métricas e o gate nativo passaram. O resumo do executor marcou falha porque os ExitCode foram lidos como null. O teste do próprio executor detectou essa inconsistência. O self-test também registrou acesso indevido à thread da interface na aba Logs.

## Correções
O executor agora inicia e acompanha System.Diagnostics.Process diretamente, mantém o handle original, lê stdout e stderr de forma assíncrona e obtém ExitCode antes de descartar o processo. Não converte null em zero. O mesmo helper é utilizado pelo teste de caminhos. REG-PROCESS-001 verifica saídas 0, 1 e 7 e streams maiores que o buffer dos pipes.

A leitura de logs continua fora da thread da interface; a publicação do texto e das mensagens de falha usa explicitamente o Dispatcher WPF. O self-test remove o SynchronizationContext e verifica sucesso e falha de leitura, com tempo limite. Não foram alterados os contratos de aplicação, backup e restauração.

## Testar
Extraia em uma pasta nova e execute Validar-Regressoes.bat. Aguarde o resultado final e envie logs/regressao-.... Depois abra Executar-WinSlim-R3.2.73.bat e confira Configurações → Logs e Personalizado. Não precisa reaplicar otimizações.

## Validação local
JSON/XAML, hashes e preservação das revisões anteriores verificados. Compilador .NET Framework, WPF e PowerShell não estão disponíveis neste ambiente; os novos testes são entregues para execução no Windows e permanecem pendentes. Os testes anteriores da R3.2.72 não são atribuídos à nova revisão.
