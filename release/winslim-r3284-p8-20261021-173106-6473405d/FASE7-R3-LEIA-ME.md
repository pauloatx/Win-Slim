# Win-Slim Suite — FASE 7 R3

## Objetivo
Conectar a tela **Presets** ao `PresetRuntime` aprovado, mantendo a UI sem qualquer mutação do Windows.

## O que testar
1. Execute `tests\Test-Fase7-R3-UI.ps1`.
2. Abra `Executar-WinSlim-R3.bat`.
3. Entre em **Presets** e selecione Equilibrado, Gamer e Extremo.
4. Confirme que o card selecionado recebe destaque e o resumo mostra 105 / 129 / 168 como base.
5. Marque overlays de Hardware e Workloads e observe a contagem/fingerprint mudar.
6. Marque `GPU IRQ affinity [ALTO]` sem autorizar risco Alto: a seleção deve indicar bloqueio.
7. Autorize risco Alto: o bloqueio deve desaparecer quando o hardware for elegível.
8. Overlays incompatíveis com o hardware detectado devem ficar desabilitados.

## Segurança da revisão
A R3 apenas chama `Resolve-WinSlimPresetRuntimeSelection`, que é a resolução pura já aprovada. Planner, Preview, Transaction e Providers ainda não são executados pela UI.

## Próximo subgate
**FASE 7 R4 — Catálogo Personalizado.**
