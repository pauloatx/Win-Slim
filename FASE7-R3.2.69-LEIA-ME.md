# Win-Slim R3.2.69 — identificação de backups e compatibilidade

A lista de backups mostra a finalidade em destaque e o perfil em uma segunda linha. A seleção, os detalhes e a confirmação explicam o resultado da restauração:

- Antes da aplicação: recupera os valores salvos antes daquela aplicação, dentro da cobertura da cópia.
- Antes da restauração: recupera o estado anterior à restauração; pode reativar ajustes que já foram desfeitos.
- Cópia de configurações: finalidade não identificada pelo nome legado; consulte os detalhes.

A confirmação inclui o ID e a data da cópia. Prefixos acumulados são simplificados apenas na apresentação; o nome original fica nos metadados e na dica da linha. Os arquivos de backup, seus hashes, IDs e o algoritmo de restauração não são alterados. Não restaura o Windows inteiro nem todos os backups juntos.

PRIV-017 permanece condicionado à compatibilidade já estabelecida. Quando excluído na revisão de aplicação real, o motivo informa edição, versão disponível, build e tipo de instalação detectados localmente. Edição não autorizada, build abaixo de 15063, instalação não cliente e falha de leitura são diferenciados. A validação é repetida antes da aplicação; não aceita dados de sistema fornecidos pelo cliente.

Nenhum novo tweak foi liberado nesta revisão. Os nove contratos da R3.2.68 foram preservados, com PRIV-017 disponível somente quando compatível.

## Testar no Windows
1. Extraia este ZIP em uma pasta nova.
2. Execute Validar-Aplicacao-Registro-R3.2.69.bat na VM.
3. Abra Executar-WinSlim-R3.2.69.bat.
4. Para visualizar as cópias anteriores, copie a pasta BackupsUI da instalação anterior para a nova pasta, mantendo os subdiretórios e arquivos intactos. Use a mesma máquina e conta que criaram as cópias.
5. Em Backup / Restauração, selecione uma cópia Antes da aplicação e outra Antes da restauração. Confira finalidade e explicação. Não é necessário restaurar novamente para validar esta mudança visual.
6. Selecione PRIV-017 em Personalizado e abra a revisão de aplicação real. Em sistema incompatível, confira o motivo detalhado. Não confirme aplicação apenas para testar o diagnóstico.
7. Envie o log da validação e imagens das duas telas, indicando tema e idioma se observar corte de texto.

## Validação local
112 verificações de aplicação e 50 de restauração passaram, além da suíte de captura, persistência e integridade dos backups. Compilação C#5 contra referências .NET Framework 4.8, sintaxe PowerShell e XML/XAML aprovadas. Incluídos testes de diagnóstico por edição, build, instalação e falha de leitura. O autoteste WPF inclui classificação de cópias antigas, prefixos acumulados e finalidade desconhecida.

Testes locais realizados em Linux/PowerShell 7.4.6, sem aplicar tweaks reais. Execução WPF, aparência e Windows PowerShell 5.1 ainda dependem do teste no Windows. Mantido o aviso CS4014 preexistente no carregamento de logs.

Todos os arquivos das versões anteriores foram preservados byte a byte.
