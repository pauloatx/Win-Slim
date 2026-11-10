# Teste curto — acabamento P8

O funcionamento observado do overlay da P7 foi confirmado pelo usuário. Validar somente o lote alterado abaixo; preservar os aceites anteriores.

1. Com Cities.exe monitorado, abra explicitamente **Overlay / atalhos**. Confira título “Configurar overlay”, subtítulo do jogo e seções Aparência, Informações e Atalhos. A janela deve caber no monitor, com rolagem e rodapé acessível.
2. Durante um benchmark, alterne Pequeno/Médio, escala, fundo e FPS Atual/Médio. Confira prévia ilustrativa e efeito imediato no overlay, mantendo posição quando houver espaço, valores reais e referência. Use Cancelar; reabra, altere e feche pelo X. Ambos devem restaurar o estado anterior sem interromper a coleta.
3. Escolha apenas algumas informações do computador, salve e reabra o mesmo jogo. Confira seleções restauradas e quatro métricas padrão preservadas. Leituras ausentes devem mostrar Indisponível. Use Restaurar padrão deste jogo e Cancelar para comprovar que o perfil salvo não foi apagado.
4. Capture atalhos, limpe um, repita uma combinação e tente uma ocupada por outro programa. Confira mensagens junto ao campo e ausência de comando acidental durante a captura da tecla. Salve; confira a confirmação e as três ações ao voltar ao jogo.
5. Confira legibilidade dos números/unidades, controles sem saltos de largura, clique nas métricas chegando ao jogo quando travado, e curvas laranja contínua/azul tracejada. Repita a abertura/rolagem em **DPI físico de 100%, 125% e 150%** e arraste a configuração entre monitores. Não deve haver controles inacessíveis nem foco roubado por atualizações do overlay.

Registrar jogo/modo/API, monitores/resolução/DPI, atalhos, resultado e desvios. Simulação WPF automatizada de DPI não substitui este aceite físico. Use `Coletar-Diagnostico.bat` para as evidências. **Edge permanece pendente e restrito à VM; não testar políticas Edge no host. Produção não aprovada.**
