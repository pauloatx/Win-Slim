# Win-Slim Suite — R3.2.44

R3.2.43 passou no gate Windows enviado: resultado 0.

Personalizado é preparado uma vez em uma pausa do Dispatcher (ContextIdle), após a inicialização e resolução do preset. Carrega o catálogo e o layout e monta apenas a categoria atual. Não navega, não abre janela nem altera seleção. Mantém apenas controles exibidos da categoria atual; sem cache de todas as categorias.

Warmup e clique compartilham a mesma Task de catálogo, evitando consultas duplicadas. Falha permite nova tentativa. Ao reabrir a tela pronta, usa os mesmos controles e contexto (categoria, busca e seleção); não espera outra consulta. Ao fechar durante a preparação, continuações são descartadas. Duração de preparação registrada uma vez no log.

Se o usuário clicar antes do término da inicialização, ainda é necessário esperar o preset e o catálogo: essa espera evita permitir edição de seleção incompleta. Há um pequeno custo único de memória por manter a tela e a categoria atual preparadas antes da primeira visita. Não cria controles das 230 opções; reutiliza a mesma página depois.

Extraia em pasta nova e execute Validar-Performance-UI-R3.2.44.bat, depois Executar-WinSlim-R3.2.44.bat. Confira a primeira abertura após o catálogo carregar e várias idas/voltas. Self-test verifica três reaberturas da página preparada sem espera adicional, sem novos controles ou janelas, com seleção/categoria/busca preservadas. Verificações locais de XML, integridade e ZIP feitas. Compilação, primeira abertura e fluidez desta revisão pendentes no Windows. Visual/esmaecimento e métricas anteriores preservados.
