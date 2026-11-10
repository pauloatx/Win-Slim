# Win-Slim R3.2.12 — Correções de Presets

O gate R3.2.11 passou na compilação, publicação, bridge e self-test WPF, mas terminou reprovado por uma contagem de overlays vinculada aos antigos nomes de estilos. A captura real também mostrou o selo RECOMENDADO e a quinta linha do Equilibrado cortados.

Esta revisão conta os controles ToggleButton reais pelos nomes Overlay*, verifica tags únicas, permite ao selo usar a largura do cabeçalho e fixa linhas de benefício em 18 pixels. O self-test WPF mede o selo e as três listas para detectar esses cortes. Conteúdo do Dashboard aprovado e backend são preservados.

1. Feche o Win-Slim e extraia em nova pasta.
2. Execute Validar-Presets-R3.2.12.bat e envie logs/gate-native-r3.2.12.log.
3. Se passar, execute Capturar-Presets-R3.2.12.bat e envie capturas/Presets-R3.2.12.png.
4. Confira selo completo e cinco linhas por card. Teste Equilibrado 105, Gamer 129, Extremo 168 sem overlays; Gamer + HAGS 130; GPU IRQ sem consentimento bloqueia pré-visualização.

Verificações locais são estáticas. Gate e visual R3.2.12 ainda precisam de validação no Windows.
