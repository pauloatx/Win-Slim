# Win-Slim Suite — R3.2.10 — Publicação do executável

O log recebido confirma CompilerExitCode: 0. A R3.2.9 falhou ao substituir um executável existente, em File.Replace, com erro de formato de caminho.
Esta revisão passa um caminho real para o backup temporário, evitando a conversão de null para caminho vazio na chamada .NET pelo PowerShell 5.1. Interface e backend permanecem iguais, exceto os identificadores da nova revisão.

## Teste no Windows

1. Feche todas as janelas do Win-Slim.
2. Extraia em uma nova pasta.
3. Execute Validar-Dashboard-R3.2.10.bat antes de abrir o aplicativo.
4. O gate compila duas vezes: a segunda exercita a substituição de um executável existente.
5. Se passar, execute Capturar-Dashboard-R3.2.10.bat.
6. Envie logs/gate-native-r3.2.10.log e capturas/Dashboard-R3.2.10.png. Se falhar, envie também logs/build-native-r3.2.10.log.

As revisões anteriores permanecem byte a byte preservadas. As verificações locais são estáticas; a regressão de File.Replace precisa passar no Windows PowerShell 5.1.
