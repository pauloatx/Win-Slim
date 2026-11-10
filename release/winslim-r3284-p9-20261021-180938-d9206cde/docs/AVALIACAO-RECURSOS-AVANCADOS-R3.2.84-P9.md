# Próxima etapa autorizada — avaliação de arquitetura

21/10/2026. Executada **após** aprovação do gate final P9, `regressao-20261021-181259-341-9470659d`, 19/19 suítes e self-test WPF. Desenvolve o planejamento do item 10 do pedido de monitoramento contínuo e da seção “Etapa posterior” do relatório P7. Esta é uma avaliação documental; nenhum recurso avançado foi instalado, aplicado ou declarado compatível com jogo real.

## Decisão de arquitetura

Preservar o monitor PresentMon e o overlay WPF como componentes de observação. Alterações de ritmo/apresentação devem usar um provedor separado, com capacidade detectada por jogo/GPU, revisão, backup, Apply, Verify e Undo do aplicativo. A candidata P9 continua sem esse provedor. Não misturar preferências visuais do overlay com escritas no perfil do driver.

DXGI disponibiliza espera e controle de fila no ciclo de renderização da própria swap chain. `SetMaximumFrameLatency` controla quadros enfileirados; não configura um limite universal de FPS. **Inferência de arquitetura:** aplicar essas chamadas ao processo do Win-Slim não controla o loop de Cities.exe. Uma integração DXGI exigiria cooperação explícita do jogo. Fontes: [espera DXGI](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_3/nf-dxgi1_3-idxgiswapchain2-getframelatencywaitableobject), [fila de apresentação](https://learn.microsoft.com/en-us/windows/win32/api/dxgi/nf-dxgi-idxgidevice1-setmaximumframelatency).

## Primeiro recurso: limitador por jogo

Há um caminho público concreto para avaliar em NVIDIA: o SDK expõe a configuração `FRL_FPS_ID` como limitador de quadros. Isso identifica uma possibilidade de integração, sem provar disponibilidade, unidade/intervalo efetivos ou comportamento em cada driver/jogo. Fonte: [NvApiDriverSettings.h oficial](https://github.com/NVIDIA/nvapi/blob/main/NvApiDriverSettings.h).

DRS permite encontrar o perfil pelo caminho completo do executável, ler/alterar uma configuração, enumerar valores disponíveis e salvar configurações no sistema. **Proposta:** primeiro protótipo de provedor deve usar essas operações em fixtures de driver, com limites consultados e sem alterar perfil global. Distinguir valor explícito, herdado, ausência, associação do executável e perfil compartilhado; Undo precisa preservar cada estado e alterações externas concorrentes. Fonte: [interfaces DRS oficiais](https://github.com/NVIDIA/nvapi/blob/main/nvapi.h).

Dependências: hardware/driver NVIDIA compatível e adaptador nativo com ABI validada para o host C#/WPF existente. O repositório público informa que a implementação NVAPI vem do driver instalado. Os componentes públicos consultados usam MIT; eventual inclusão exige avisos correspondentes, versão/commit e hashes fixados, revisão de todos os arquivos efetivamente distribuídos. Isso não concede automaticamente direito de redistribuir o pacote de driver. Fontes: [README do SDK](https://github.com/NVIDIA/nvapi/blob/main/README.md), [licença das bibliotecas](https://github.com/NVIDIA/nvapi/blob/main/License.txt), [licença no cabeçalho](https://github.com/NVIDIA/nvapi/blob/main/nvapi.h).

Pendências concretas antes de implementar: escolher o conjunto inicial de GPUs/drivers, fixar versão do SDK e forma do adaptador, confirmar o valor suportado em consulta somente leitura, testar isolamento de perfis compartilhados e definir recuperação contra mudança concorrente. Não foram consultados nem escritos perfis físicos neste trabalho. AMD/Intel exigem avaliação própria; compatibilidade não presumida. Alternativa é integração documentada com o limitador interno de um jogo, quando existir contrato verificável.

## Sincronização e tela cheia exclusiva

VRR/VSync depende de suporte e flags da swap chain, além do modo de apresentação. **Inferência:** um temporizador do overlay externo não oferece controle equivalente à posição de varredura. Falta escolher um mecanismo cooperativo/documentado e uma forma de medir tearing e latência externamente. Não apresentar este objetivo como disponível. Fonte: [VRR e apresentação DXGI](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/variable-refresh-rate-displays).

DirectFlip/Independent Flip pode enviar quadros sem composição convencional do desktop. **Inferência:** somente topmost/posição de um HWND WPF não comprova suporte universal ao exclusivo. Manter janela sem bordas como alternativa já documentada; avaliar integração autorizada de sobreposição no jogo/fabricante antes de anunciar compatibilidade adicional. Fonte: [modelo flip e composição](https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/for-best-performance--use-dxgi-flip-model).

## Critérios antes de liberar um provedor

| Família | Prova automatizada necessária | Prova física necessária |
| --- | --- | --- |
| Limitador | Ausência/erro de driver, ABI/versão, perfil ambíguo/compartilhado, valor herdado/ausente, backup/Apply/Verify/Undo, falha por etapa e conflito externo | Limites selecionados, frame pacing/consumo, reinício do jogo, DX11/DX12/Vulkan conforme suporte declarado, vários drivers/GPU, restauração |
| Sincronização | Capacidade/VRR ausente, mudança de modo/resolução/taxa e desligamento seguro | Tearing e latência por instrumentação externa, taxas fixas/VRR e múltiplos monitores |
| Exclusivo | Alternância de modo, foco, fechamento do jogo, isolamento da coleta e recuperação de recursos | Exclusivo verdadeiro por jogo/API, Alt-Tab, HDR/DPI/monitores e ausência de regressão de desempenho |

Resultado: avaliação concluída, caminho NVIDIA identificado para protótipo futuro; implementação e aceite físico permanecem pendentes das dependências acima. Nenhum componente RTSS foi copiado/redistribuído e nenhuma técnica para contornar anti-cheat foi proposta. A avaliação não amplia o aceite manual já registrado.
