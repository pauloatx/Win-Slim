# Retomada — R3.2.84 P7: monitoramento contínuo

Registro: 21/10/2026 — America/Sao_Paulo.

- Candidata isolada: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p7-20261021-164829-76e2357d`.
- Executável: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p7-20261021-164829-76e2357d\bin\WinSlim.UI.Native.R3.2.84.exe`. SHA-256: `664C9510070979DAE404B9178D927CE0D425585D1974E5C39ADA742CC453AE02`.
- ZIP: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p7-20261021-164829-76e2357d.zip`. Hash final do ZIP registrado separadamente em `release/candidate-p7-artifacts.json` do workspace, evitando hash circular dentro do pacote.
- Monitorar jogo inicia coleta contínua via stdout sem arquivo permanente de quadros. Gravar benchmark compartilha a sessão; concluir/cancelar preserva monitor, resultado completo anterior e referência.
- Overlay: quatro métricas, primeiro FPS médio/atual; Médio acrescenta FrameTime laranja e referência azul tracejada. Pequeno | Médio e Mover/Travar permanecem interativos, com corpo travado deixando cliques passarem e sem ativação. Posição/tamanho/escala/opacidade/FPS/sensores por jogo, ajuste de monitores/DPI, atalhos configuráveis com conflitos explícitos.
- Sensores opcionais: uso CPU/GPU/RAM reutilizado; VRAM do maior adaptador; temperaturas apenas de provedor WMI já disponível. Ausente/inválido/desatualizado resulta em Indisponível; nenhum driver instalado.
- `Validar-Regressoes.bat`: **18/18 suítes aprovadas no Windows**, incluindo build, self-test WPF e regressões de streaming, cancelamento/reinício preservando resultado, buffers, stale, indisponibilidade, preferências, escala e atalhos. Relatório: `logs\regressao-20261021-165241-737-05144a4f\resultado.json`. Seis testes Python do empacotador aprovados; 145 hashes de fontes/cadastro.
- Primeiro gate P7 preservado: `regressao-20261021-164847-786-f93349dc`, 17/18, contrato de ausência de Thread.Sleep. A espera do adaptador foi convertida para await Task.Delay, sem alterar o teste. Somente o novo relatório completo acima autoriza o empacotamento.
- Diagnóstico negativo do problema anterior: `logs/p7-buffering-reproducer.log`. Transporte por arquivo sem flush reproduz falha; regressão nova comprova atualização antes do fim via stdout. A primeira tentativa de execução desse diagnóstico foi preservada separadamente. As regressões não iniciam ETW real nem aplicam ajustes de produção.
- P6/P5/P4 e evidências anteriores preservadas. **FrameTime comparativo e cancelar/capturar novamente da P4: aceitos pelo usuário**, conforme as duas capturas da conversa.
- **Edge real: pendente, somente na VM. Novo fluxo em jogo real, cliques recebidos pelo jogo, cursor capturado, DPI/múltiplos monitores físicos e sensores: pendentes. CI Windows hospedada: pendente. Produção: não aprovada.** VM não iniciada/restaurada; nenhum ajuste aplicado.
- Limitador por jogo, sincronização e exclusivo ampliado ficam na etapa posterior com avaliação de arquitetura/licenças/testes, descrita no relatório. Overlay externo atual pode exigir janela sem bordas; nenhum RTSS redistribuído ou contorno de anti-cheat.

Relatório: [IMPLEMENTACAO-R3.2.84-P7.md](docs/IMPLEMENTACAO-R3.2.84-P7.md). Teste real curto: [ACEITE-MANUAL-R3.2.84-P7.md](docs/ACEITE-MANUAL-R3.2.84-P7.md). Não repetir lotes manuais antigos aprovados sem regressão relacionada.