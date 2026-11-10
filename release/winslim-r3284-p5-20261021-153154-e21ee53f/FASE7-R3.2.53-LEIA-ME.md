# Win-Slim Suite — R3.2.53

Atualiza as duas verificações obsoletas do validador para o build por conteúdo SHA-256. O teste passa a conferir os hashes das entradas, executável e configuração e a coleção explícita usada pelo PowerShell 5.1. Também valida os dados reais do cache publicado.

Os testes funcionais existentes continuam verificando reaproveitamento do executável, preservação byte a byte do log e log separado IfNeeded. O build e o funcionamento do aplicativo permanecem iguais aos da R3.2.52 aprovada visualmente; apenas nomes de revisão e testes foram atualizados.

Extraia em nova pasta e execute Validar-Performance-UI-R3.2.53.bat. Envie a pasta logs. Para abrir: Executar-WinSlim-R3.2.53.bat.

Preservação de revisões anteriores, estrutura XML, pacote e hashes foram verificados localmente. A execução integral do novo validador ainda precisa de conferência no Windows.
