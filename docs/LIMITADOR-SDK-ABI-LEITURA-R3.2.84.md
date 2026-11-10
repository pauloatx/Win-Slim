# Limitador — SDK/ABI e adaptador somente leitura

22/10/2026. Retomada expressamente autorizada após concluir os 31 contratos Edge. **Etapa independente implementada e verificada com fixtures; sucesso físico NVIDIA pendente.** Não disponibiliza controle de FPS no aplicativo. AV-20261021-001, família retida, gate completo e produção permanecem bloqueados.

## Origem e compatibilidade

SDK oficial [NVIDIA/nvapi](https://github.com/NVIDIA/nvapi/tree/70d337db9186e968eab622f7e786de7e437faf3d), commit `70d337db9186e968eab622f7e786de7e437faf3d` (data de autoria informada pelo repositório: 18/09/2026). O [manifesto](../specs/NVAPI-SDK-R3.2.84.json) fixa URL e SHA-256 de oito arquivos textuais, conferidos antes de compilar. Cabeçalhos MIT, README e licença originais preservados; [aviso local](../third_party/NvApiSdk/NOTICE-WINSLIM.md). Nenhum `.lib`, driver ou instalador incorporado.

O leitor usa C#/.NET Framework x64 e PowerShell 5.1, separado do build WPF. A implementação NVAPI é fornecida pelo driver NVIDIA instalado, não por esses cabeçalhos. O host observado possui **Radeon RX 480**, driver 31.0.21925.1001, e não contém `System32\nvapi64.dll`. Nenhum driver foi instalado. Windows ARM64, processo x86 e DLL de outra arquitetura não foram habilitados.

## Contrato ABI revisado

| Estrutura | Tamanho em bytes | Revisão | Pontos conferidos |
| --- | ---: | ---: | --- |
| NVDRS_SETTING | 12320 | 1 | Pack 4; ID em 4100, valor predefinido em 4120, atual em 8220 |
| NVDRS_SETTING_VALUES | 414112 | 1 | Pack 4; cabeçalho 12, união padrão e até 100 uniões de 4100 bytes |
| NVDRS_APPLICATION_V4 | 20492 | 4 | Nome em 8, flags em 16392, linha de comando em 16396 |
| NVDRS_PROFILE_V1 | 4116 | 1 | Nome em 4; contagens de aplicações/configurações em 4108/4112 |

Strings `NvU16[2048]` ocupam 4096 bytes; a união binária ocupa 4100, incluindo tamanho. O macro de versão é **sizeof OR (revisão << 16)**, sem truncar o tamanho a 16 bits; isso também vale para a estrutura grande de valores. Delegates usam Cdecl e o export `nvapi_QueryInterface`. Os tamanhos/offsets do marshalling .NET foram comparados a um modelo independente em Python ctypes baseado nos cabeçalhos fixados, com caracteres explícitos de 16 bits. Não havia compilador C++ no ambiente; não foi realizado ensaio cruzado C++ nem chamada ABI física a driver NVIDIA. A comparação de modelos não substitui esses ensaios.

`FRL_FPS_ID=0x10835002`; os cabeçalhos declaram 0/desligado e limite numérico 1023. **Não foi inferida uma lista de FPS suportados** a partir desses extremos ou de `NUM_VALUES`. O leitor preserva a enumeração bruta e marca `EnumeratedValuesAreCompleteRange=false`. Semântica/unidade/faixa efetivamente aceita por GPU/driver e efeito no jogo continuam pendentes.

## Comportamento e limites do leitor

- `tools/prototypes/NvapiReadOnly.ps1` valida o pin do SDK e a política de execução da família independente `NvapiReadOnly`. Compila somente uma DLL própria; grava fontes, compilador e SHA-256 do artefato **antes de carregá-lo**, em diretório novo sob `logs`. Não cria executável, transporte de captura, ETW ou processo auxiliar semelhante aos retidos.
- O wrapper consulta apenas a DLL fixa em System32: exige processo/PE AMD64, Authenticode válido e publisher NVIDIA Corporation. O binding confere hash antes/depois de carregar e usa `LOAD_LIBRARY_SEARCH_SYSTEM32`, sem busca no diretório atual. A verificação de assinatura pertence ao wrapper; o método C# `ReadValidatedSystemLibrary` recebe o hash já revisado e não é uma fronteira de autorização independente.
- A superfície permite somente 12 interfaces de consulta/ciclo de vida: inicializar/finalizar, versão do driver, sessão DRS em memória, carregar configurações, localizar aplicação por **caminho completo**, ler informações do perfil/base/global, setting e valores enumeráveis. Todas são resolvidas antes de inicializar a sessão; função ausente impede prosseguir. Nenhuma Set/Save/Delete/CreateProfile/CreateApplication foi exposta ou resolvida.
- Ausente (`SETTING_NOT_FOUND=-160`) é distinto de zero explícito. Origem atual explícita/predefinida, global/base/default herdado, valor predefinido válido e valor efetivo permanecem separados. Falha não é convertida em valor zero. Perfis globais, compartilhados, associação genérica ou qualificada são identificados sem afirmar exclusividade do jogo.
- Libera somente a sessão e a referência de biblioteca adquiridas pelo leitor. Erros de leitura, ABI, capacidade parcial ou limpeza ficam explícitos; não autorizam escrita. Todos os resultados têm `CanApplyToDriver=false`, inclusive leitura completa. Não modifica perfis nem materializa overrides.
- O planejador anterior `FrameLimitPlan.ps1` e sua regressão permanecem intactos. Ele aceita somente fixtures; não recebe automaticamente o DTO do novo leitor. Nenhuma integração no runtime/UI nem alteração das definições estatísticas ou do overlay.

## Verificações realizadas e alcance

`REG-NVAPIRO-001`: **114 verificações comportamentais/ABI passaram**. Cobrem layouts/versões/IDs oficiais, origens, ausência/zero, caminho completo, perfis globais/compartilhados, disponibilidade parcial, erro em cada etapa e limpeza dos recursos adquiridos. Metadados de confiança/arquitetura foram exercitados com fixtures; não representam assinatura de um driver real. Artefatos de teste e proveniência foram preservados.

Houve duas falhas iniciais preservadas: erro de sintaxe no registro de proveniência (antes da compilação) e ambiguidade de overload `Marshal.SizeOf` no PowerShell (depois da compilação). Corrigidas respectivamente a expressão e a seleção explícita do overload `Type` por reflexão; a execução final passou. Não houve enfraquecimento das expectativas nem execução da família retida.

Uma segunda compilação **sem fixture** foi carregada, e o caminho de indisponibilidade real do host retornou `Unavailable / DriverLibraryMissing`, `Value=null`, sem carregar driver e sem chamar NVAPI. Essa é validação negativa real, **não sucesso físico de ABI/DRS NVIDIA**. [Resultado](../logs/limiter-sdk-20261021/native-unavailable-result.json), [log final](../logs/limiter-sdk-20261021/readonly-test-03.log). Python é apenas ferramenta de desenvolvimento.

## Próximos critérios

1. Em máquina de laboratório NVIDIA x64 com driver instalado e assinatura válida, executar somente consulta pelo caminho real de um jogo; registrar GPU/driver, hash/publisher da DLL, versão ABI, resultado DRS, origem e limpeza. Não usar VM sem passthrough como prova física. Até lá, sucesso nativo permanece pendente.
2. Ampliar a matriz somente leitura para associação específica/genérica/compartilhada, valor explícito/herdado/ausente/predefinido e indisponibilidade. Conferir com a configuração observável do driver sem alterá-la para fabricar cenários no host principal.
3. Escrita, backup persistente, concorrência, recuperação de falha real, aplicação física de FPS e integração Review/Apply/Verify/Undo são etapas futuras, dependentes dessa leitura e das revisões correspondentes; não foram iniciadas nesta autorização de leitura.
4. Incidente AV e gate precisam de resolução própria. Esta etapa independente não libera empacotamento, produção, auxiliares retidos ou o aceite Edge pela UI.
