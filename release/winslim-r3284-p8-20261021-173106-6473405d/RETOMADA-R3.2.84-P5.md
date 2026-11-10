# Retomada — R3.2.84 P5: seleção automática e overlay

Registro: 21/10/2026 — America/Sao_Paulo.

- Candidata isolada: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p5-20261021-153154-e21ee53f`.
- Executável: `bin\WinSlim.UI.Native.R3.2.84.exe`.
- SHA-256 do executável: `E638D1341F202B73ED8827AB796D2230ECEBD4036DF12A44EF04F2E29E0F857A`.
- Gate `Validar-Regressoes.bat`: **17/17 suítes aprovadas**, incluindo compilação e self-test WPF. Relatório: `logs\regressao-20261021-153506-617-23ec86aa\resultado.json`.
- Seis testes Python do empacotador aprovados; cadastro único e 134 hashes exigidos pelo empacotador antes do ZIP. Python portátil ficou fora da candidata.
- Resultado técnico e permissões: `logs\candidate-p5.json`. A primeira execução no sandbox falhou somente na chave HKCU descartável do teste nativo; foi preservada. O teste isolado e o gate completo passaram fora do sandbox, sem alteração de expectativas e sem aplicar ajustes do catálogo.
- FrameTime comparativo e cancelar/capturar novamente: **aceitos pelo usuário**, conforme as duas capturas da conversa. Evidências P4 anteriores preservadas.
- **Edge real pendente**, somente na VM; não aplicar políticas no computador principal.
- **Seleção automática e overlay em jogo real pendentes**: quatro métricas ao vivo, Pequeno/Médio, gráfico de FrameTime, arraste e posição por jogo. O overlay acompanha a medição iniciada pelo usuário (10–120 segundos). Exclusivo, anti-cheat, cursor capturado e DPI de vários monitores precisam de teste real.
- CI Windows hospedada: **pendente**. Produção: **não aprovada**. A VM não foi iniciada nem restaurada nesta etapa.

Roteiro curto: [ACEITE-MANUAL-R3.2.84-P5.md](docs/ACEITE-MANUAL-R3.2.84-P5.md). Não repetir lotes manuais anteriores aprovados sem regressão relacionada. Próxima ação: validar apenas o novo lote no jogo real e manter o Edge pendente até o aceite específico na VM.