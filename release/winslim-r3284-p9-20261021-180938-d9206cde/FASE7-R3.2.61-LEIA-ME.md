# Win-Slim Suite — R3.2.61

O log da R3.2.60 identificou a falha exata: no caso com aviso visivel, o conteudo do painel terminava em 170 DIPs, enquanto o teste ainda usava o limite anterior, de 92 DIPs. A medida do host estava atualizada, mas seus descendentes preservavam caches de layout do caso anterior.

O self-test agora invalida a medicao e disposicao de toda a arvore visual da area de paginas, de baixo para cima, antes de medir cada cenario. A janela do teste esta oculta e os cenarios sao executados sincronamente, sem o ciclo normal do dispatcher que atualiza a interface em uso. As verificacoes de corte e sobreposicao continuam ativas, com diagnostico numerico. Nao foi aumentada a tolerancia nem removido o caso com aviso visivel.

Esta alteracao se limita ao self-test. O motor de backup/restauracao e o desenho do aplicativo continuam preservados. Revisoes anteriores sao conservadas byte a byte. Os 50 testes isolados de restauracao da R60 passaram no log enviado; isso nao aprova o self-test WPF da nova revisao, que ainda deve ser executado no Windows.

1. Extraia em uma pasta nova.
2. Execute `Validar-Backup-Restauracao-R3.2.61.bat` nas duas maquinas.
3. Aguarde o resumo final e envie a pasta `logs`. O arquivo principal e `logs\gate-native-r3.2.61-visivel.log`; o diagnostico da UI fica em `logs\ui-native-r3.2.61.log`.

O progresso e mostrado durante a execucao e salvo em UTF-8. Os backups anteriores podem ser copiados para a nova pasta, preservando os arquivos e usando a mesma maquina/usuario.

A aplicacao global dos presets continua demonstrativa. HAGS, MSI e afinidade continuam bloqueados. A restauracao real cobre registro e servicos capturados no backup escolhido, com confirmacao, copia anterior e verificacao. Nao e restauracao completa do Windows.
