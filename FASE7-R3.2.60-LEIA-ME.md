# Win-Slim Suite — R3.2.60

A R3.2.59 terminou a validacao enviada, com duas reprovacoes derivadas da mesma excecao no self-test de layout. Os 50 testes isolados de restauracao passaram. O log do aplicativo registrou backup de 65 ajustes e uma restauracao concluida e verificada, com copia anterior preservada. Isso confirma aquela operacao; nao comprova todos os servicos ou cenarios possiveis.

A R3.2.60 ajusta a medicao do self-test: ele dispoe diretamente a area real das paginas, com as dimensoes descontadas da barra lateral, titulo e rodape. Assim, a verificacao nao depende de atualizar a janela oculta antes de Window.Show. As checagens de sobreposicao, altura minima da tabela, visibilidade do aviso e limites do rodape permanecem ativas. Cada erro agora inclui tema, idioma, viewport e as medidas do elemento que falhou. A validacao WPF ainda precisa ser repetida no Windows.

O iniciador de backup/restauracao mostra progresso desde o inicio e grava o log em UTF-8. O diagnostico adicional da UI tambem e lido em UTF-8. O motor e o desenho da interface permanecem iguais aos da R59, exceto pelas identificacoes de versao. Todas as revisoes anteriores sao preservadas byte a byte.

1. Extraia em uma pasta nova.
2. Execute `Validar-Backup-Restauracao-R3.2.60.bat` nas duas maquinas e aguarde o resumo final. Log: `logs\gate-native-r3.2.60-visivel.log`. Ele nao aplica os tweaks do catalogo.
3. Abra `Executar-WinSlim-R3.2.60.bat` para conferir a interface.
4. Os backups anteriores podem ser copiados para a nova pasta, preservando os arquivos e usando a mesma maquina/usuario.

Se houver falha, envie `logs\gate-native-r3.2.60-visivel.log` e `logs\ui-native-r3.2.60.log`.

O teste controlado de registro continua disponivel em `Validar-Restauracao-Registro-R3.2.60.bat`, usa somente uma chave temporaria HKCU e a remove ao terminar. Os 27 testes dessa operacao passaram nos logs anteriores do Windows.

A aplicacao global dos presets continua demonstrativa. HAGS, MSI e afinidade continuam bloqueados. A restauracao real cobre registro e servicos capturados no backup escolhido, com confirmacao, copia anterior e verificacao. Nao e restauracao completa do Windows.
