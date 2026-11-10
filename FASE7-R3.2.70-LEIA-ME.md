# Win-Slim R3.2.70 — Modo de Jogo com aplicação e restauração

PILOT-003 (Modo de Jogo) passa a aceitar aplicação real. Em Personalizado → Performance, busque Modo de Jogo. A seleção é manual, sem mudar os presets existentes.

O contrato grava apenas AutoGameModeEnabled, DWORD 1, em HKCU\Software\Microsoft\GameBar. Windows cliente a partir do build 15063 é exigido pela checagem local repetida antes da aplicação. Home também é aceito. Server, build antiga ou detecção indisponível excluem o ajuste. Os dez contratos incluem o PRIV-017, que conserva sua própria restrição de edição.

A aplicação exige revisão, backup completo verificado e autorização da tela. Confere existência, tipo e valor antes e depois da gravação. Se já configurado, não escreve novamente. A restauração recupera o estado capturado, incluindo DWORD 0 ou ausência original. Feche e reabra o jogo depois de aplicar. Não há garantia de ganho de FPS; a verificação confirma a configuração no Registro.

A descrição exibida foi esclarecida para remover a promessa antiga de efeito imediato. O catálogo original e as versões anteriores foram preservados. A interface mantém as identificações dos backups aprovadas na R3.2.69.

## Teste na VM
1. Extraia em uma pasta nova e execute Validar-Aplicacao-Registro-R3.2.70.bat.
2. Abra Executar-WinSlim-R3.2.70.bat. Em Personalizado, selecione PILOT-003 e revise os IDs que serão aplicados.
3. Use Aplicar selecionados → Revisar aplicação real → Criar backup e aplicar.
4. Se aparecer Já configurado, o Modo de Jogo já estava ativo; isso é esperado. Para testar uma mudança efetiva, pode desligá-lo antes nas Configurações do Windows da VM, em Jogos → Modo de Jogo, e então repetir o fluxo.
5. Abra Ver backups e selecione a cópia Antes da aplicação desta execução. Use Restaurar tudo para devolver os valores anteriores desta cópia.
6. Envie a pasta logs e os backups correspondentes em Backups\UI, incluindo os journals. Não é necessário repetir todos os ajustes anteriores individualmente.

## Validação local
125 verificações de aplicação e 50 de restauração aprovadas, além da suíte de backup. Testes cobrem contrato adulterado, Home/Pro, build mínima, falha de leitura, escrita parcial, reaplicação sem escrita, restauração de ausência e DWORD 0 original. Compilação C#5 contra .NET Framework 4.8 e parser PowerShell aprovados. XML/XAML e JSON conferidos.

Ambiente local Linux/PowerShell 7.4.6, com acesso ao Registro simulado. O teste WPF, Windows PowerShell 5.1 e a aplicação real desta revisão ainda precisam da execução no Windows. Aviso CS4014 anterior permanece.

## Referências
- Microsoft Learn: referência de configurações do Windows 11, seção Gaming, AutoGameModeEnabled: https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11
- Microsoft: Modo de Jogo introduzido na Atualização para Criadores: https://news.microsoft.com/pt-br/o-que-ha-de-novo-na-atualizacao-do-windows-10-para-criadores/

## Atualização de Personalizado — seleção por categoria

O botão Desativar todos da categoria aparece logo depois de Ativar todos da categoria. Desmarca todos os ajustes da categoria atual, incluindo os ocultos pela busca, e mantém as demais categorias. Chaves e contadores são atualizados imediatamente. O botão fica indisponível quando a categoria não tem itens selecionados. Esta ação muda apenas a seleção; para desfazer alterações já aplicadas, utilize Backup / Restauração.

Extraia este pacote em uma pasta nova e abra Executar-WinSlim-R3.2.70.bat. O launcher recompila quando necessário. A versão continua R3.2.70, com esta correção de interface; o Modo de Jogo ainda requer o teste no Windows. O self-test WPF inclui o novo botão, busca sem resultados e preservação de outras categorias. Nesta atualização, foram conferidos localmente XML, JSON e integridade dos arquivos; a execução WPF exige Windows.
