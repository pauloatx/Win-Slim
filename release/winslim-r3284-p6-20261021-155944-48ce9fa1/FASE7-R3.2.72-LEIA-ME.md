# Win-Slim R3.2.72 — correção da compilação CS4014

Corrige o erro confirmado nos logs da R3.2.71, MainWindowController.cs(163,17). A preparação antecipada de Personalizado usava Dispatcher.BeginInvoke sem acompanhar a operação retornada em um manipulador async.

A operação agora é guardada como DispatcherOperation e aguardada após a inicialização do bridge. Continua ocorrendo em paralelo, com tratamento de cancelamento/falha e sem bloquear a thread da interface. Mantido /warnaserror:4014; nenhum aviso foi suprimido.

## Regressão
REG-BUILD-001 compila dois pequenos casos usando o csc.exe/.NET Framework do Windows: o padrão anterior deve falhar especificamente com CS4014; a operação aguardada deve compilar. A suíte nativa recompila o aplicativo inteiro e executa seu self-test. Métricas progressivas e seleção por categoria continuam cobertas.

## Testar
1. Extraia em uma pasta nova.
2. Execute Validar-Regressoes.bat. O comando faz a regressão do compilador, o teste de métricas e a validação nativa. Aguarde Resultado: 0.
3. Abra Executar-WinSlim-R3.2.72.bat.
4. Envie a pasta logs/regressao-... e logs/ui-native-r3.2.72.log. Não é preciso reaplicar otimizações.

## Validação local
XML/XAML, JSON, hashes e preservação das revisões anteriores conferidos. A falha anterior foi comprovada pelos logs enviados pelo usuário. Este ambiente não dispõe de csc/.NET Framework/WPF/PowerShell; os testes de compilação e execução da nova revisão permanecem pendentes no Windows. Nenhum ganho de desempenho é declarado como medido nesta revisão.
