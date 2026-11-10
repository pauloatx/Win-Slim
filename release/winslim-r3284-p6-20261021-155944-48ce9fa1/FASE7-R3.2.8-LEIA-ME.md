# Win-Slim Suite — R3.2.8 — Correção do build e diagnóstico

## Teste no Windows

1. Feche todas as janelas do Win-Slim.
2. Extraia este pacote em uma nova pasta. Não sobrescreva a R3.2.7.
3. Execute primeiro `Validar-Dashboard-R3.2.8.bat`. Não abra o aplicativo enquanto o gate estiver rodando.
4. Se terminar com `GATE TECNICO R3.2.8 APROVADO` e código 0, execute `Executar-WinSlim-R3.2.8.bat`.
5. Feche o aplicativo e execute `Capturar-Dashboard-R3.2.8.bat`.
6. Envie `logs/gate-native-r3.2.8.log` e `capturas/Dashboard-R3.2.8.png`.

Se o gate falhar, envie também `logs/build-native-r3.2.8.log`. A saída e os erros do processo de build ficam em `logs/gate-build-r3.2.8-forced.stdout.log` e `logs/gate-build-r3.2.8-forced.stderr.log`.

## Diagnóstico da R3.2.7

O gate recebido reprovou com duas falhas relacionadas ao build forçado: compilador retornou 1 e o log não registrou sucesso naquele momento.
Os checks do backend, bridge e self-test WPF usando o executável já existente passaram.
O TEST 08 executou `-IfNeeded` e sobrescreveu o log do compilador com “up-to-date / ExitCode: 0”.
Por isso, o erro original do compilador não está disponível nos anexos recebidos.
Executável em uso é uma hipótese; não é uma causa confirmada.
A R3.2.7 permanece tecnicamente reprovada naquele gate, e a aprovação visual continua pendente.

## Correções

- `-IfNeeded` usa `build-native-r3.2.8-ifneeded.log` e não sobrescreve o log da compilação.
- Nova tentativa de compilação arquiva o log anterior em `logs/build-history`.
- O gate interrompe em caso de falha do build; não roda self-test de executável anterior nessa situação.
- stdout e stderr do build são preservados em arquivos separados, evitando perda da saída no PowerShell 5.1.
- Build detecta o executável desta pasta em execução e pede que a janela seja fechada, sem encerrar processos.
- O compilador gera um executável em pasta temporária própria. O resultado só é publicado depois de compilação bem-sucedida.
- Erro na publicação também reprova o build e é registrado; uma marca de falha impede que `-IfNeeded` ignore o erro e reutilize o binário anterior como se estivesse atualizado.
- O gate verifica que `-IfNeeded` mantém o log do compilador byte a byte intacto.

## Preservação e validação

Todos os arquivos da R3.2.7 e baselines anteriores foram preservados. A R3.2.8 usa fontes próprias; a interface mantém a composição do Dashboard anterior, com troca dos identificadores de revisão. Presets continua aguardando a comparação e aprovação do Dashboard.
O backend permanece com 230 IDs e presets 105/129/168.
As verificações locais são estáticas, executadas em Linux. Compilação, gate e abertura da R3.2.8 ainda precisam ser verificados no Windows PowerShell 5.1.
Nenhum tweak é aplicado por este teste.
