# Ponto de retomada — Win-Slim R3.2.84 FrameTime Corrigido 4

> Atualização de aceite em 21/10/2026: o usuário confirmou, com duas capturas nesta conversa, a comparação de FrameTime e o fluxo cancelar/capturar novamente. Esses dois aceites estão concluídos. O aceite real do Edge permanece pendente. A continuação é a candidata P5, com escopo e roteiro em `docs/ACEITE-MANUAL-R3.2.84-P5.md`; o registro histórico abaixo foi preservado.

Registro de encerramento: **21/10/2026 — America/Sao_Paulo**.
Sessão encerrada por solicitação do usuário. Nenhum novo teste foi iniciado nesta etapa de registro.

## Estado aprovado

- Validação automatizada concluída: **16/16 suítes Windows/WPF aprovadas**, self-test do binário do host e restauração nativa adicional aprovados.
- Seis testes Python do empacotador aprovados; cadastro com 16 IDs únicos e 125 hashes validado.
- Coletor de diagnóstico corrigido: usa a revisão do resumo da execução. Os sete logs R3.2.84 no ZIP foram conferidos por SHA-256.
- Regressão do defeito registrada em `REG-PIPELINE-001`, bug `diagnostic-current-revision-build-logs`; falha demonstrada antes da correção e aprovação depois.
- Último estado verificado da VM `teste win-slim-win11`: **desligada**, snapshot `WINSLIM_BASELINE` restaurado, `currentStateModified=false`.
- Evidências anteriores preservadas. Aceite manual pendente; **produção não aprovada**. CI Windows hospedada não executada nesta sessão.

## Candidata pronta

Pasta:
`C:\WinSlim-Integracao\Builds\winslim-r3284-p4-20261021-040645-05adeefc`

Executável para abrir no computador principal:
`C:\WinSlim-Integracao\Builds\winslim-r3284-p4-20261021-040645-05adeefc\bin\WinSlim.UI.Native.R3.2.84.exe`

SHA-256 do executável: `C980CA4B8BBB888FCA3A6D2FA63EC43131F328B57EED56108475C8EC65E12AD5`.
O binário C#/WPF e o coletor PresentMon permaneceram inalterados.

## Pendências de aceite manual

1. **FrameTime no computador principal:** duas capturas comparáveis; conferir comparação, atual laranja contínuo, referência azul tracejada, escala comum, hover e ausência de cortes.
2. **PresentMon real no computador principal:** concluir captura, cancelar outra e capturar novamente; jogo permanece aberto, medição parcial não é aceita e a sessão própria termina.
3. **Edge somente na VM:** Apply/Verify/Undo de **EDGE-019/020/024/025**, com conta administrativa, revisão e backup pelo fluxo do aplicativo; restaurar exatamente o estado original, inclusive valores ausentes.

Roteiro com resultados esperados e permissões: [docs/ACEITE-MANUAL-R3.2.84-P4.md](docs/ACEITE-MANUAL-R3.2.84-P4.md).
Para o Edge, executar **dentro da VM** o auxiliar `tools\integration\Abrir-Aceite-Edge-VM.ps1` da candidata compartilhada; ele verifica TESTE/VirtualBox e solicita UAC visível. Não aplicar políticas Edge no computador principal.

## Evidências e relatório

- Relatório atualizado no projeto: [docs/RELATORIO-VALIDACAO-VM-R3.2.84-P4-20261021.md](docs/RELATORIO-VALIDACAO-VM-R3.2.84-P4-20261021.md).
- Resultado do controlador: `C:\WinSlim-Integracao\Logs\20261021-010654\resultado.json` — ExitCode 0.
- Pasta completa da candidata validada: `C:\WinSlim-Integracao\Logs\winslim-r3284-p4-20261021-040645-05adeefc`.
- Suítes detalhadas: `logs\regressao-20261021-040808-660-b2f754a6\resultado.json` dentro dessa pasta.
- Resumo integrado e conferência dos sete logs: `logs\integration\summary.json` dentro dessa pasta.
- ZIP corrigido: `C:\WinSlim-Integracao\Logs\winslim-r3284-p4-20261021-040645-05adeefc\WinSlim-Diagnostico-R3.2.84.zip`.
- SHA-256 do ZIP corrigido: `233BABEE85918E6A3AF99B890A194771BF79C5825C08F4EC91362FC0F44BFD19`.
- Evidências da regressão e estado final no projeto: `logs\diagnostic-fix-20261021`.
- Execução anterior preservada: `C:\WinSlim-Integracao\Logs\20261021-004905` e `C:\WinSlim-Integracao\Logs\winslim-r3284-p4-20261021-034856-26b513b8`.

## Próxima ação

Retomar pelos três aceites manuais acima e registrar seus resultados/evidências. Não repetir automaticamente os testes já aprovados nem os lotes manuais anteriores sem alteração ou regressão relacionada. Preservar backups e logs antes de restaurar a VM após o aceite do Edge. Nenhuma senha está registrada neste documento ou no projeto.
