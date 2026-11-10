# Aceite manual — Win-Slim R3.2.84 FrameTime Corrigido 4

> Atualização em 21/10/2026: itens 1 e 2 aceitos pelo usuário nas duas capturas da conversa, incluindo cancelar e capturar novamente. Item 3 (Edge na VM) continua pendente. Este roteiro permanece como histórico; o novo lote está em `ACEITE-MANUAL-R3.2.84-P5.md`.

Candidata: `winslim-r3284-p4-20261021-040645-05adeefc`.
Pasta no computador principal: `C:\WinSlim-Integracao\Builds\winslim-r3284-p4-20261021-040645-05adeefc`.
Executável: `bin\WinSlim.UI.Native.R3.2.84.exe`. Pode ser aberto diretamente: resolve a raiz pela pasta pai de `bin`.
SHA-256: `C980CA4B8BBB888FCA3A6D2FA63EC43131F328B57EED56108475C8EC65E12AD5`.

O aceite tem três itens pendentes. Não é necessário repetir manualmente lotes anteriores já aprovados sem alteração relacionada.

## 1. FrameTime — computador principal

1. Abra o executável da candidata. Em Desempenho em jogo, selecione o processo do jogo aberto e meça 30 segundos.
2. Clique **Guardar referência**. Repita a captura no mesmo jogo, cena, duração e configurações gráficas; não guarde a segunda captura como referência antes de comparar.
3. Confira os temas claro/escuro e redimensione a janela. Passe o mouse no início, no meio e no fim do gráfico e retire o cursor.

**Esperado:** atual laranja contínuo e referência azul tracejada, legenda legível, escala comum e gráfico visível sem cortes. Hover mostra valores em ms de ambas as séries e a diferença, inclusive nos extremos; retirar o cursor remove marcadores e valores. A posição horizontal é relativa às amostras, não um alinhamento por instante. Não há garantia de ganho de desempenho entre capturas.

Salve o resultado pelo botão **Salvar resultado** e registre imagens do gráfico e do hover. Uma captura sem referência ainda não comprova comparação entre duas séries.

## 2. PresentMon real — computador principal

1. Na mesma candidata, faça uma captura completa de 30 segundos e salve o resultado. Se houver erro de permissão ETW, registre a mensagem; quando necessário, feche o app e abra o executável explicitamente como administrador antes de repetir.
2. Inicie uma nova captura de 60 segundos. Clique **Cancelar** após alguns segundos; em seguida faça outra captura curta completa.

**Esperado:** a primeira captura contém dados do processo escolhido e arquivos em `Benchmarks\<execução>`. Cancelar mantém o jogo aberto, devolve a interface ao estado ocioso e não aceita a medição parcial como resultado; a última medição completa pode continuar visível. A próxima captura funciona. Para conferir sessões, use somente a consulta `logman query -ets`: compare antes/depois e verifique que não restou a sessão `WinSlim-<GUID>` daquela captura. Não encerre sessões de terceiros.

Preserve o resultado exportado, a pasta `Benchmarks` e a mensagem de cancelamento. Esta etapa coleta dados; não aplique ajustes do catálogo no computador principal.

## 3. Edge Apply/Verify/Undo — somente VM

Com a VM `teste win-slim-win11` desligada e a baseline restaurada após a validação técnica, inicie-a e entre no Windows. Dentro da VM, execute no PowerShell:

```powershell
& '\\vboxsvr\WinSlim_Builds\winslim-r3284-p4-20261021-040645-05adeefc\tools\integration\Abrir-Aceite-Edge-VM.ps1'
```

O script recusa execução fora de `TESTE`/VirtualBox, solicita UAC visível se necessário e copia a candidata para `C:\WinSlim\Aceite\winslim-r3284-p4-20261021-040645-05adeefc`, preservando cópias existentes. Ele abre o app elevado; os ajustes dependem da ação explícita na interface. Caso a cópia já exista, reabra o mesmo script dentro da cópia local. É necessária uma conta administrativa da VM; use a mesma conta na aplicação e na restauração.

1. Em **Personalizado**, importe `Teste-Lote-Edge-R3.2.84.json` da cópia local. Confirme somente EDGE-019/020/024/025 selecionados. Registre o estado original das quatro políticas, inclusive valores ausentes, e a versão do Edge. Se o app bloquear por incompatibilidade ou permissões, registre o bloqueio; não force a aplicação.
2. Confira a prévia e a tela **Revisar aplicação real**; clique **Criar backup e aplicar**. Confirme Verify e exporte o relatório. Feche e reabra o Edge manualmente e confira `edge://policy`.
3. Em **Backups**, escolha o backup dessa aplicação e use **Restaurar tudo**; confirme a verificação da restauração. Reabra o Edge e compare com o estado original; valores originalmente ausentes devem voltar a ausentes.

| ID | Valor em HKLM\SOFTWARE\Policies\Microsoft\Edge | Apply/Verify esperado |
|---|---|---|
| EDGE-019 | UserFeedbackAllowed | DWORD 0 |
| EDGE-020 | MicrosoftEdgeInsiderPromotionEnabled | DWORD 0 |
| EDGE-024 | AlternateErrorPagesEnabled | DWORD 0 |
| EDGE-025 | SearchSuggestEnabled | DWORD 0 |

**Esperado:** backup válido antes da primeira escrita; quatro políticas verificadas, sem alterações em outros ajustes. Feedback manual, promoção Insider e sugestões web seguem as políticas aplicáveis; histórico e favoritos locais permanecem disponíveis. Undo restaura exatamente o estado original, não simplesmente quatro zeros. Políticas carregadas sem erro não substituem a observação do efeito de cada recurso disponível na versão instalada.

Antes de descartar o estado da VM, copie o backup em `Backups\UI`, os logs e as imagens para uma **nova** pasta em `\\vboxsvr\WinSlim_Logs`, identificada como aceite manual. Só depois desligue normalmente e restaure `WINSLIM_BASELINE`. Não sobrescreva a pasta de evidências da validação técnica nem a da execução anterior.

## Registro do aceite

Para cada item, anote aprovado/reprovado, data, ambiente/versão, ação realizada e arquivo de evidência. Os testes técnicos não aprovam automaticamente estes três itens nem autorizam marcar a candidata como produção aprovada.
