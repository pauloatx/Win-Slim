# Implementação e verificações — R3.2.84 P5

Escopo: seleção automática do último aplicativo em tela cheia, descoberta inicial inequívoca, captura acionada pelo usuário e overlay opcional durante a captura. Dois tamanhos no próprio overlay; quatro métricas, gráfico no Médio, título arrastável com Mover/Travar e perfil por executável. A seleção fica congelada durante operações, valida PID/nome/início do processo e mantém a opção manual. Dados ao vivo são limitados a 240 intervalos por fluxo; linhas incompletas aguardam newline, fluxos não se misturam, ausência de dados limpa a prévia. A estatística final continua sendo calculada pelo parser aprovado sobre a captura completa.

Os arquivos de comparação, baseline e CSV anteriores não são migrados nem excluídos. Os módulos de Apply/Verify/Undo, backups e políticas Edge não foram alterados. O hash e as licenças do PresentMon 2.6.0 permanecem os mesmos. Não foram executados ajustes de otimização de produção.

## Cobertura comportamental

- `REG-PRESENTMON-001`: casos anteriores preservados; acrescidos coleta ao vivo com processo simulado, cancelamento com prévia/nova captura, falha do consumidor de prévia, leitura incremental, números conhecidos, janela limitada, PID/nome/swap chain separados, pausa/retomada, arquivo ausente/truncado e CSV inválido.
- `REG-OVERLAY-001`: geometria de tela cheia e monitor com origem negativa, processo reutilizado, perfil por caminho sem PID, roundtrip, arquivo bloqueado, estado anterior preservado, dados corrompidos, quatro valores, seletores reais WPF acionados por eventos, gráfico, arraste pelos mesmos métodos dos handlers, trava e nova janela com perfil salvo. Usa HWND nativo oculto e não captura ETW nem move o mouse do usuário.
- `REG-UI-001`: self-test WPF inclui seleção automática/manual, indisponibilidade, congelamento durante operação e preservação de resultado/referência; controles novos cabem nos dois viewports, dois temas e idiomas. Todos os testes anteriores permanecem exigidos.

Defeito encontrado durante a implementação: inicializar um HWND oculto antes da árvore visual retornava `PresentationSource.FromVisual == null`. Falha demonstrada no harness antes da correção, com log em `logs/overlay-p5-before-fix.log`; a origem agora é obtida pelo HWND em `SourceInitialized`. Essa regressão não depende de procurar strings no código.

A funcionalidade de overlay era nova, portanto não existia um teste anterior do recurso no P4; a demonstração antes/depois acima é do defeito detectado na implementação. A ausência de hardware/jogo real nos testes automatizados impede aprovar visibilidade exclusiva, anti-cheat, interação com cursor capturado e DPI de vários monitores.

## Evidências da candidata

A entrega isolada preserva em `logs` o resultado do gate completo (`regressao-*/resultado.json`, com um resultado único por ID), o log de compilação e self-test WPF, os testes Python do empacotador, a validação de cadastro/hashes e um `candidate-p5.json` que identifica a pasta e o SHA-256 do binário. O resultado dessa execução, e não a existência deste documento, determina a aprovação técnica. Prévia visual dos tamanhos: `logs/overlay-p5-preview/overlay-pequeno.png` e `overlay-medio.png`.

Aceites reais anteriores: FrameTime comparativo e cancelar/capturar novamente confirmados pelo usuário em 21/10/2026 nas duas capturas da conversa. Edge, novo lote de overlay/seleção e CI hospedada continuam pendentes. Produção não aprovada. Roteiro curto: `ACEITE-MANUAL-R3.2.84-P5.md`.
