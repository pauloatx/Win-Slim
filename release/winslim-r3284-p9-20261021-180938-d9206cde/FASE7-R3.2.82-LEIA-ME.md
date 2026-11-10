# Win-Slim R3.2.82 — preferências opcionais do Edge

## Base validada

Na R3.2.81, as treze suítes terminaram Passed, Resultado 0. O lote EDGE-008/011/012/016 aplicou quatro valores, todos verificados, sem erros; as quatro políticas foram aceitas com status OK no Edge. Os quatro valores originalmente ausentes foram restaurados, com status Completed e Count 4. Os dois snapshots recebidos passaram na conferência de hashes. Isso conclui o ciclo previsto no cenário recebido; não aprova antecipadamente esta nova versão.

## Lote novo

| ID | Política | DWORD | Edge Stable mínimo |
|---|---|---:|---:|
| EDGE-019 | UserFeedbackAllowed | 0 | 77 |
| EDGE-020 | MicrosoftEdgeInsiderPromotionEnabled | 0 | 98 |
| EDGE-024 | AlternateErrorPagesEnabled | 0 | 80 |
| EDGE-025 | SearchSuggestEnabled | 0 | 77 |

Todas usam HKLM\SOFTWARE\Policies\Microsoft\Edge, exigem administrador e Windows 10/11 cliente. O aplicativo verifica localmente a instalação Stable e a versão, e repete a validação antes de escrever. Ausência de detecção, versão incompatível e falta de elevação excluem os ajustes.

- EDGE-019 desativa a função manual de enviar feedback pelo Edge. Não representa desligamento geral de telemetria. Exige fechar e reabrir o navegador manualmente.
- EDGE-020 oculta a promoção do canal Insider na página Sobre. Não desativa atualizações do navegador.
- EDGE-024 usa a página de erro padrão, sem sugestões do serviço web para erros de conexão/DNS.
- EDGE-025 desativa sugestões web de pesquisa na barra de endereços. Sugestões locais de histórico e favoritos permanecem; esses dados não são apagados.

São preferências opcionais, sem promessa de ganho de FPS. Conforme a documentação, EDGE-020/024/025 têm limitações em perfis conectados com conta Microsoft; confira o status e o comportamento no perfil usado. A gravação verificada no Registro e a aceitação pelo navegador são verificações diferentes.

O fluxo mantém revisão explícita, backup tipado completo antes de escrever, leitura após escrita, idempotência, recuperação de falha e restauração da existência/tipo/valor anteriores. O aplicativo não fecha o Edge automaticamente. Visual, catálogo de 230 IDs e presets-base são preservados.

## Validar esta versão

1. Extraia em pasta nova. Feche o Win-Slim e execute Validar-Regressoes.bat, mantendo o aplicativo fechado até terminar. São 14 suítes; aguarde Resultado: 0. Se falhar, envie a pasta logs/regressao-... antes da aplicação real.
2. Abra Executar-WinSlim-R3.2.82.bat como administrador. Em Personalizado, importe Teste-Lote-Edge-R3.2.82.json. Confirme somente EDGE-019/020/024/025.
3. Revise os destinos e as exclusões. Use Criar backup e aplicar e identifique a cópia Antes da aplicação deste lote.
4. Salve seu trabalho, feche/reabra o Edge manualmente. Na mesma máquina, abra edge://policy e clique Recarregar políticas. Confira os quatro nomes, valores false e status OK. Para aceitar todos, o Edge precisa ser 98 ou posterior. Se houver erro, expanda Mostrar mais e envie a mensagem.
5. Confira as preferências no perfil usado, considerando as limitações acima. Não precisa apagar histórico ou recriar perfil.
6. Em Backup / Restauração, selecione a cópia Antes da aplicação deste lote e use Restaurar tudo. Antes da restauração guarda o estado aplicado, portanto é outra cópia.
7. Feche/reabra o navegador e recarregue políticas. O estado esperado é o estado real salvo: valores preexistentes retornam ao valor anterior; originalmente ausentes são removidos. Envie a pasta de regressões, capturas e backups desta versão. Não repita os lotes anteriores já concluídos.

## Regressões e validação local

REG-EDGEPRIV-001 cobre contratos exatos dos quatro IDs, adulteração de destino/tipo/valor/hive/admin/reinício, versões abaixo/no mínimo, Windows cliente/Server, falha de detecção e perda de elevação. Exercita Apply/Verify/Undo individual e em lote com IO simulado, backup em disco, estados presentes/ausentes, idempotência, falha de leitura/backup, falha parcial após cada escrita e snapshot incompleto. As treze suítes anteriores continuam exigidas.

Executados localmente: seis testes Python do empacotador; conferência de JSON/XAML, cadastro único, contratos estáticos, hashes e preservação dos arquivos anteriores. Linux não dispõe de PowerShell 5.1, .NET Framework ou WPF: compilação e 14 suítes Windows da R3.2.82 estão PENDENTES. Python é ferramenta de desenvolvimento, não requisito do aplicativo.

## Fontes oficiais revisadas

- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/userfeedbackallowed
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/microsoftedgeinsiderpromotionenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/alternateerrorpagesenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/searchsuggestenabled
