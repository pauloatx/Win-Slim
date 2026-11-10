# Win-Slim Suite — FASE 7 R3.2.7 — Dashboard

Esta revisão implementa a primeira etapa do handoff: Início / Dashboard.
O backend e todos os arquivos recebidos da R3.2.6 permanecem byte a byte preservados.
Presets permanece na composição anterior, aguardando a aprovação visual do Dashboard.

## Como executar no Windows 10 / 11

1. Extraia o ZIP inteiro em uma pasta local, por exemplo `D:\Desktop\winslim_fase7_r3_2_7`.
2. Abra `Executar-WinSlim-R3.2.7.bat`. Ele compila com o .NET Framework do Windows e abre em Início.
3. Execute `Validar-Dashboard-R3.2.7.bat` no Windows PowerShell 5.1. O resultado fica em `logs/gate-native-r3.2.7.log`.
4. Execute `Capturar-Dashboard-R3.2.7.bat`. A janela aparece, aguarda a inicialização do bridge, captura o Dashboard e fecha. A imagem fica em `capturas/Dashboard-R3.2.7.png`.
5. Compare com `referencias/01_Dashboard_Referencia.png`, considerando somente a janela interna da referência, sem a moldura de apresentação. Envie a captura e o log do gate para a revisão visual.

A execução comum não solicita elevação automaticamente. O card informa os privilégios reais da sessão; para verificar a aparência em modo administrador, execute o launcher como administrador.

## O que mudou

- Início abre por padrão, com a mensagem de boas-vindas da referência.
- Três cards: Windows/build; CPU/núcleos/threads/RAM; GPU/driver/armazenamento.
- Três estados abaixo: compatibilidade da família Windows 10/11, privilégios reais e disponibilidade de backup ainda não informada.
- Quatro indicadores circulares com arcos proporcionais e etiquetas abaixo; dados ausentes aparecem como travessão.
- Botão ANALISAR SISTEMA abaixo dos indicadores e painel de status à direita.
- CPU, GPU e armazenamento mostram o texto completo ao passar o mouse.
- Métricas a cada três segundos, somente no Dashboard, pausadas fora dele ou com a janela minimizada.
- Valores inválidos são descartados; valores numéricos são limitados a 0–100; falha de leitura limpa valores antigos.
- A quantidade do catálogo deixou de ser apresentada como quantidade aplicada.
- Captura WPF em PNG respeita o DPI real da janela.

## Dados e limites desta etapa

O bridge permanece persistente e somente de leitura. A arquitetura aprovada não foi alterada.
A compatibilidade exibida indica apenas a família do sistema; elegibilidade por tweak continua no runtime.
Os campos de backup, tweaks aplicados, pendências e datas ficam como “não informado”, pois o contrato atual não fornece histórico de transações. Não há dedução de contagens a partir do catálogo, nem anúncio de backup sem confirmação.
“Ver detalhes” e “ANALISAR SISTEMA” abrem a página Análise do Sistema que já existia na R3.2.6; essa página continua sendo um protótipo desta fase.

## Validação

Verificações locais: XML XAML, resolução estática de controles/recursos, contagens do catálogo/presets, preservação byte a byte dos arquivos recebidos e hashes de baseline. Consulte `docs/VALIDACAO-LOCAL-R3.2.7.json`.

Este pacote foi preparado em Linux. Não foi possível compilar ou abrir WPF nem executar Windows PowerShell 5.1 aqui.
O gate R3.2.6 não é declarado aprovado. O gate R3.2.7 inclui sua preservação, validação do backend, build, bridge real, self-test WPF, inicialização do controller e regressão de `-IfNeeded`.
Aprovação final continua dependendo de gate verde, abertura real e comparação visual aprovada. Não há screenshot real produzido neste ambiente.

## Arquivos de entrada

- `Executar-WinSlim-R3.2.7.bat`: abrir o aplicativo.
- `Validar-Dashboard-R3.2.7.bat`: executar o gate e salvar o log.
- `Capturar-Dashboard-R3.2.7.bat`: capturar a janela real.
- `src/UI/Native/R3_2_7`: fontes da revisão nova.
- `specs/FASE7-R3.2.7-baseline.json`: hashes dos novos arquivos.

Próxima etapa: corrigir os desvios da captura do Dashboard e obter aprovação visual; só então reconstruir Presets usando a imagem fornecida.
