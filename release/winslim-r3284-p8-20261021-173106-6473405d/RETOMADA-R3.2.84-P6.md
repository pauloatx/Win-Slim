# Retomada — R3.2.84 P6: complemento do overlay

Registro: 21/10/2026 — America/Sao_Paulo.

- Candidata isolada: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p6-20261021-155944-48ce9fa1`.
- Executável: `bin\WinSlim.UI.Native.R3.2.84.exe`; SHA-256: `AC06D60261CBC6A0590E31512836420FE5C38E90AA96EFF054E9DE0E52E88D68`.
- Pequeno: quatro métricas ao vivo. Médio: mesmas quatro e FrameTime atual laranja contínuo/referência compatível azul tracejada. Seletor Pequeno | Médio indica o ativo e mantém tarefa, dados, processo e referência.
- Travado: métricas deixam os cliques passarem, controles continuam clicáveis. Mover habilita arraste livre entre monitores sem ativação; Travar fixa. Monitor/posição relativa/tamanho/trava são salvos por jogo e se ajustam à mudança da topologia. A captura continua iniciada pelo usuário e dura 10–120 segundos.
- `Validar-Regressoes.bat`: **17/17 suítes aprovadas**, incluindo compilação e self-test WPF. Relatório da única execução que aprova esta entrega: `logs\regressao-20261021-160424-575-b3ee5d70\resultado.json`.
- Seis testes Python do empacotador aprovados; cadastro com 17 IDs únicos e 137 hashes. Python portátil não integra a candidata.
- Resultado técnico: `logs\candidate-p6.json`. A primeira tentativa foi preservada: falhou somente na limpeza da fixture temporária do self-test. A correção tem teste de falha transitória/persistente e não permite apagar diretório alheio nem ocultar falha persistente.
- FrameTime comparativo e cancelar/capturar novamente: **aceitos pelo usuário**, conforme as duas capturas da conversa. As candidatas/evidências P4 e P5 anteriores foram preservadas.
- **Edge real pendente**, somente na VM. **Novo overlay em jogo real pendente**, incluindo clique recebido pelo jogo, cursor capturado, exclusivo/anti-cheat e DPI de monitores físicos. Múltiplos monitores automatizados usam fixtures; não foram alterados monitores do usuário.
- CI Windows hospedada: **pendente**. Produção: **não aprovada**. Nenhum ajuste do catálogo foi aplicado. A VM não foi iniciada nem restaurada.

Roteiro do lote novo: [ACEITE-MANUAL-R3.2.84-P6.md](docs/ACEITE-MANUAL-R3.2.84-P6.md). Não repetir os lotes manuais anteriores aprovados sem regressão relacionada.