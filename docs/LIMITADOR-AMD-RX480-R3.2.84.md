# Limitador AMD — revisão anterior à implementação para a RX 480

22/10/2026. Hardware confirmado pelo usuário: **Radeon RX 480, 8 GB**. Não há laboratório NVIDIA; sua leitura física fica pendente **por falta de hardware**, sem prazo de aprovação e sem instalar driver NVIDIA neste computador. Adaptador NVIDIA preservado.

**Conclusão da revisão:** há APIs públicas AMD para investigar capacidades e ler configurações. Ainda não existe evidência suficiente para anunciar um limitador Win-Slim por jogo na RX 480. Próxima etapa técnica: revisar/validar ABI de um leitor AMD restrito, antes de chamar o driver. Nesta rodada não foi implementado adaptador AMD, compilado código nativo, carregada DLL ou alterada configuração gráfica.

## Compatibilidade específica, sem generalização

| Evidência oficial | O que permite concluir | Limite |
| --- | --- | --- |
| [Página da RX 480](https://www.amd.com/en/support/downloads/drivers.html/graphics/radeon-600-500-400/radeon-rx-400-series/radeon-rx-480.html) lista Radeon Chill e FRTC | Existem recursos associados a esse produto; a placa pertence à série RX 400 | Não prova exposição pela API, suporte em cada driver/jogo ou configuração disponível hoje |
| [Página atual de FRTC](https://www.amd.com/en/products/software/adrenalin/frtc.html) declara RX 6000/7000, tela cheia exclusiva e ajuste fora do jogo | A cobertura publicada atualmente não inclui a RX 480 | Não forçar suporte nem concluir que o recurso legado desapareceu. Investigar capacidade real no driver instalado antes de decidir |
| [Compatibilidade ADLX](https://gpuopen.com/manuals/adlx/programming-with-adlx/adlx-programming-guide/specifications/compatibility/) ressalva GPUs/drivers legados | A biblioteca pode oferecer funcionalidade reduzida; nem todo legado é atendido | Nome do produto, versão do arquivo ou DLL presente não autorizam presumir interfaces suportadas |

A página atual FRTC cita 30–200 FPS; documentação AMD mais antiga do overlay cita 30–300. Essas faixas pertencem aos respectivos documentos, **não são constantes de capacidade da RX 480**. Um futuro leitor deve obter faixa/passo e status do driver. Os 8 GB são identificação confirmada pelo usuário, não condição suficiente para habilitar o recurso. Não foi inferida a versão comercial Adrenalin a partir da versão numérica do driver.

## APIs e escopo

| Caminho | Consultas públicas relevantes | Escopo e dependências | Decisão |
| --- | --- | --- | --- |
| ADLX / FRTC | `GetFrameRateTargetControl`, `IsSupported`, `IsEnabled`, `GetFPS`, `GetFPSRange` | Interface obtida por `IADLXGPU`; sem parâmetro de executável. Requer ADLX instalado e interface funcional | Candidata à **consulta por GPU**. Não satisfaz, sozinha, perfil por jogo. [Interface](https://gpuopen.com/manuals/adlx/adlx-sdk-references/adlx-interfaces/3d-graphics/iadlx3dframeratetargetcontrol/), [assinatura](https://gpuopen.com/manuals/adlx/adlx-sdk-references/adlx-interfaces/3d-graphics/iadlx3dsettingsservices/getframeratetargetcontrol/) |
| ADLX / Chill | `GetChill`, `IsSupported`, `IsEnabled`, `GetMinFPS`, `GetMaxFPS`, `GetFPSRange` | Também recebe GPU; Chill varia FPS conforme atividade. Exclusão com Anti-Lag/Boost e, nas interfaces atuais, Anti-Lag Next | Consulta candidata; não apresentar como FRTC nem limite fixo já validado. [Interface e dependências](https://gpuopen.com/manuals/adlx/adlx-sdk-references/adlx-interfaces/3d-graphics/iadlx3dchill/) |
| ADL legado / FPS | `ADL2_FPS_Caps`, `ADL2_FPS_Settings_Get` | Contexto ADL + índice do adaptador; documentação define configurações **globais**, separadas AC/DC | Possível leitura alternativa após revisão ABI. Não transformar escrita global em “por jogo”. [Contrato público](https://gpuopen-librariesandsdks.github.io/adl/group__POWERMANAGEMANTAPI.html) |
| ADL legado / Chill | `ADL2_Chill_Caps_Get`, `ADL2_Chill_Settings_Get` | Consultas de capacidade/estado global do adaptador; não identificam executável | Alternativa de diagnóstico, sem inferir limites por aplicação |
| ADL / perfis | `ADL2_ApplicationProfiles_ProfileOfAnApplicationX2_Search`, `PropertyType_Get`; há APIs de customização/associação | Busca inclui nome, caminho, versão e área do driver. Há propriedades e buffers variáveis. Consultar perfil do driver não prova override do usuário nem precedência efetiva | **Contrato de escrita por jogo ainda não fechado**: faltam identificação oficial das propriedades FPS/Chill, origem/herança, ausência versus override e restauração exata. [Perfis públicos](https://gpuopen-librariesandsdks.github.io/adl/group__APPPROFILESAPI.html) |

A documentação do [AMD Software sobre Chill](https://www.amd.com/en/resources/support-articles/faqs/DH3-033.html) permite configuração manual por perfil, com herança global e override individual. Isso prova uma função da interface AMD, não a existência de uma chamada pública equivalente no SDK. Essa distinção impede implementar chaves de Registro, nomes de propriedades ou arquivos de perfil obtidos por suposição. Também não se usará troca automática do estado global ao mudar o jogo em foco como substituto de isolamento por executável.

Chill conflita com Anti-Lag/Boost, podendo desativá-los ao ser habilitado. Qualquer futura escrita precisará incluir os estados afetados na revisão e no backup/Undo; nesta etapa eles não foram consultados nem alterados. Fixar Min=Max como alternativa a FRTC permanece hipótese a testar, inclusive aceitação da igualdade e comportamento no jogo. Não foi prometido limite rígido, efeito imediato, cobertura de todas as APIs ou funcionamento em janela/borderless para FRTC.

## Dependências, ABI e licenças antes de programar

Preferência para estudo: **ADLX**, pois a AMD o recomenda para novos desenvolvimentos; ADL fica como alternativa legada delimitada. [Orientação oficial](https://gpuopen.com/archived/adl/). A revisão preservou 13 cabeçalhos/documentos em `logs`, sem incorporar SDK ao runtime:

- ADLX `32b5a740d42295c5dfe9026b9f52683da0f3af91`: cabeçalhos de inicialização, tipos, sistema e 3D; helper C e compatibilidade. [Repositório fixado](https://github.com/GPUOpen-LibrariesAndSDKs/ADLX/tree/32b5a740d42295c5dfe9026b9f52683da0f3af91).
- ADL `84c881cb2136f04287eb3af12de00a9e2867aa9e`: tipos/estruturas e documentação gerada de adapter/perfis. [Repositório fixado](https://github.com/GPUOpen-LibrariesAndSDKs/display-library/tree/84c881cb2136f04287eb3af12de00a9e2867aa9e).
- [Manifesto com SHA-256 e URL](../logs/amd-limiter-review-20261022/official-source-manifest.json). São cópias para revisão estática; não houve execução dos exemplos. Os exemplos expõem setters e não devem ser usados como sondagem automática.

Para C#/PowerShell 5.1, ADLX oferece interfaces C com vtables e gestão de referências; não é uma importação COM automática. Entradas de inicialização usam Cdecl e métodos de interface usam o macro StdCall. `adlx_bool` usa um byte no contrato C; não reutilizar o marshalling padrão de BOOL de quatro bytes. Revisar `ADLX_IntRange`, versão negociada, ponteiros, ordem de métodos, `Acquire/Release`, `Terminate`, tratamento de erro e liberação em cada falha. Não copiar IDs/estruturas do leitor NVIDIA.

O [caminho oficial de binding C#](https://gpuopen.com/manuals/adlx/programming-with-adlx/adlx-programming-guide/quick-start/building-csharp-bindings-for-adlx/) usa SWIG e build C++; isso acrescentaria ferramentas de desenvolvimento/bridge nativa. O ambiente desta rodada não tem compilador C++ identificado. Um binding C restrito alternativo exigiria sua própria revisão e comparação ABI antes de uso; não foi escolhido como atalho já validado. Python/MCPs do SDK não são dependências adequadas para introduzir no aplicativo atual nem foram instalados.

No ADL, revisar callback de memória, contexto, Unicode, buffers/propriedades variáveis e tamanho de estruturas. `ADLFPSSettingsOutput` contém nove `int` (36 bytes no layout declarado); isso é análise estática, não validação de marshalling nem chamada nativa. Para perfil, `record[1]`/`uData[1]` representam dados variáveis: não tratá-los como array fixo de um elemento.

O SDK ADLX inclui [contrato próprio de licença](https://github.com/GPUOpen-LibrariesAndSDKs/ADLX/blob/32b5a740d42295c5dfe9026b9f52683da0f3af91/ADLX%20SDK%20License%20Agreement.pdf); não classificá-lo automaticamente como MIT. Sua revisão integral e as condições de redistribuição continuam pendentes antes de incorporar código/artefatos. Os cabeçalhos ADL consultados contêm MIT e seus avisos foram preservados. Nenhuma licença de driver foi presumida a partir da licença de cabeçalho; nenhuma DLL AMD foi copiada para distribuição.

## Ambiente observado sem chamar o driver

Driver previamente inventariado: `31.0.21925.1001`, PCI `VEN_1002 / DEV_67DF`. Nesta rodada foram lidos metadados e tabela PE dos arquivos já instalados:

| Arquivo | Versão do arquivo | SHA-256 | Assinatura observada |
| --- | --- | --- | --- |
| `C:\Windows\System32\amdadlx64.dll` | 1.1.0.56 | `312dfb7e297dafc2b0979c9acfd5390605323a0b3ee0e19f0d1b601b6e942957` | Valid; Microsoft Windows Hardware Compatibility Publisher |
| `C:\Windows\System32\atiadlxx.dll` | 7.23.19.1541 | `01d083006351d05fd6d02b7fe54220d9c4f7ea2fca2802d51465c550f8a145d0` | Valid; mesmo publisher WHQL |

A presença de publisher WHQL Microsoft mostra por que uma futura política AMD não pode reutilizar mecanicamente o filtro de CN NVIDIA. Ainda será necessário revisar identidade do arquivo, arquitetura, localização, cadeia de confiança e hash no instante da carga; assinatura válida não comprova capacidade funcional.

Inspeção **estática**, sem `LoadLibrary`: ADLX exporta seis entradas, incluindo consulta de versão, inicialização normal/legada e término; não exporta `ADLXInitialize2`. ADL exporta 1296 nomes, incluindo FPS/Chill Caps/Get e buscas de perfis Unicode. **Exports não comprovam que as chamadas terão sucesso na RX 480.** A ausência de Initialize2 exige revisão do caminho Initialize clássico antes do futuro binding; não permite renomear função, trocar DLL ou instalar driver. Inicialização legada documentada é opção de compatibilidade a avaliar explicitamente, sem retry silencioso nem promessa de suporte.

Evidências: [metadados](../logs/amd-limiter-review-20261022/installed-library-metadata.json), [exports estáticos](../logs/amd-limiter-review-20261022/installed-exports-static.json). Nenhuma consulta `IsSupported`, Caps/Get, configuração AMD Software ou efeito físico foi executado/aprovado.

## Sequência independente e condições de avanço

1. **Concluído:** revisão oficial RX 480, diferenças de escopo, pin de fontes e inventário estático. NVIDIA pendente por falta de hardware. Sem mudança no adaptador existente, Edge ou overlay.
2. **Próxima etapa independente:** fechar licença/ABI e contrato de leitor AMD por GPU com lista restrita de consultas, erros explícitos, valores nulos para ausência e liberação só dos recursos adquiridos. Validar fixtures de indisponibilidade/versão/booleano/tamanho/limpeza antes de qualquer chamada nativa; só então consulta física, sem setters, no driver instalado.
3. **Portão de escopo por jogo:** obter contrato documentado de identidade/propriedades/origem/herança e Undo exato. Se indisponível, manter limitador automático por jogo indisponível para AMD; documentar somente orientação manual suportada pelo AMD Software. Não substituir por escrita global ou ajuste especulativo de Registro.
4. **Futuro aceite de efeito:** ambiente de laboratório autorizado para alterações reais, backup dos estados dependentes, Apply/Verify/Undo, matriz de jogo/API/modo de tela e aferição física independente. Não executar benchmark auxiliar retido nem apresentar fixtures como prova física.

AV-20261021-001, PresentMonHarness/MonitorHarness, gate completo e produção continuam bloqueados. Aceite Edge e visual anterior preservados. Não houve nova candidata/ZIP, instalação de driver, exclusão AV ou teste repetido dos lotes aprovados.
