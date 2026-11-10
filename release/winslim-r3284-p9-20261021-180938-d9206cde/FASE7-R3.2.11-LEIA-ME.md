# Win-Slim R3.2.11 — Presets

Dashboard R3.2.10 aprovado visualmente pelo usuário em 06/10/2026. Gate técnico R3.2.10 aprovado no Windows. Captura por comando corrigido também funcionou.

Esta revisão refina somente Presets: três cards com ícones vetoriais e cores próprias, Gamer recomendado, benefícios agrupados, overlays por categoria, resumo e seleção ativa explícita. Equilibrado é o nome apresentado para o preset interno Balanceado. Catálogo 230 e bases 105/129/168 preservados. Nenhuma alteração no Windows é aplicada nesta fase.

Corrigidos também os argumentos de captura: --root "." após mudar para a pasta do pacote. A nova captura suporta Presets. Respostas antigas de resolução não substituem o resumo da seleção atual; a pré-visualização fica desabilitada enquanto calcula.

## Teste no Windows

1. Feche o Win-Slim e extraia em uma nova pasta.
2. Execute Validar-Presets-R3.2.11.bat. Envie logs/gate-native-r3.2.11.log se houver falha.
3. Abra Executar-WinSlim-R3.2.11.bat e navegue a Presets.
4. Sem overlays, confirme Equilibrado 105, Gamer 129 e Extremo 168.
5. Selecione Gamer + HAGS: espere 1 overlay e 130 ajustes. Limpar deve voltar a 129.
6. Selecione GPU IRQ sem permitir alto risco: confirme aviso de consentimento e pré-visualização bloqueada.
7. Troque rapidamente entre perfis e confirme que título, destaque e resumo terminam no mesmo perfil.
8. Execute Capturar-Presets-R3.2.11.bat. Envie capturas/Presets-R3.2.11.png para comparação visual. A captura usa Equilibrado sem overlays.

Verificações locais: XML, nomes e tags, preservação byte a byte, hashes e ZIP. Compilação WPF, interação e aprovação visual desta revisão ainda pendentes no Windows.
