# Registo de bugs — Win-Slim Suite

> Visão humana do histórico de defeitos, com identificadores estáveis `WS-BUG-NNNN`.
> A fonte de verdade automática é `tests/regression/cases.json` (validada pelo gate e por
> `tools/package_release.py`). Este ficheiro é mantido à mão enquanto o gerador/validador
> automático do Apêndice D (item 2) não existir; cada entrada corresponde a um caso registado
> em `cases.json` e não pode divergir dele.
>
> Regra de estado (AGENTS §5.2): `aberto` → `em_correcao` → `corrigido` (teste verde + gate
> verde) → `verificado` (verificação em Windows real/aceite). Defeitos por corrigir ficam
> `nao_corrigir` ou `nao_reproduzido` com justificação.

## Resumo cronológico

| ID | Título | Família | Sev. | Risco | Estado | Encontrado | Corrigido |
| --- | --- | --- | --- | --- | --- | --- | --- |
| WS-BUG-0001 | CI hospedada nunca executada: árvore sem repositório Git, remoto ou credencial | CI/Infraestrutura | S3 | N2 | corrigido | 2026-11-10 | 2026-11-10 |
| WS-BUG-0002 | Regras de exclusão removiam do checkout os artefactos entregues exigidos pelo baseline | CI/Infraestrutura | S2 | N3 | corrigido | 2026-11-10 | 2026-11-10 |
| WS-BUG-0003 | Reordenação do workflow invalidou o hash revisado do manifesto de segurança | CI/Infraestrutura | S3 | N3 | corrigido | 2026-11-10 | 2026-11-10 |
| WS-BUG-0004 | Baseline desatualizado para a revisão de `AGENTS.md` de 10/11/2026 | CI/Infraestrutura | S2 | N3 | corrigido | 2026-11-10 | 2026-11-10 |
| WS-BUG-0005 | Workflow inválido: here-string PowerShell com indentação 0 encerrava o bloco YAML | CI/Infraestrutura | S2 | N2 | corrigido | 2026-11-11 | 2026-11-11 |
| WS-BUG-0006 | `REG-UI-001` reprovava por área de trabalho do runner menor que a janela contratada | CI/Interface | S2 | N2 | corrigido | 2026-11-11 | 2026-11-11 |
| WS-BUG-0007 | Gate local é one-shot: o build forçado substitui `bin/` e a execução seguinte reprova | Gate/Nativo | S2 | N3 | corrigido | 2026-11-10 | 2026-11-11 |
| WS-BUG-0008 | Escopo declarava 28 suítes obrigatórias enquanto o cadastro real tinha 30 | Governança | S4 | N1 | corrigido | 2026-11-11 | 2026-11-11 |
| WS-BUG-0009 | Cadeia de revisão não acompanhou o registo de casos: `registrySHA256` e `requiredIds` divergentes | Segurança/Cadeia | S2 | N3 | corrigido | 2026-11-11 | 2026-11-11 |
| WS-BUG-0010 | Medição da área de trabalho via `System.Windows.Forms.Screen` lia métricas em cache e dava a preparação por falhada | CI/Instrumentação | S2 | N2 | corrigido | 2026-11-11 | 2026-11-11 |

## Detalhe

### WS-BUG-0001 — CI hospedada nunca executada

- **Família / severidade / risco:** CI/Infraestrutura · S3 · N2 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** validação · **Datas:** 2026-11-10 / 2026-11-10
- **Sintoma:** o workflow existia e estava revisto, mas nenhuma execução hospedada existia; a pasta não tinha `.git`, remoto, branch nem credencial não-interativa.
- **Cenário de reprodução:** `git rev-parse` na pasta de trabalho (sem repositório) e consulta das execuções do repositório (`total_count` sem execuções).
- **Comportamento esperado:** o repositório tem remote e branch, e uma execução hospedada arranca a partir de um `push`.
- **Causa raiz:** ausência de checkout Git e de credencial; nunca houve acesso de escrita ao repositório. **Categoria:** `permissao`.
- **Correção:** repositório inicializado, remoto `pauloatx/Win-Slim` configurado e branch `master` publicada com o corpus de entrega.
- **Testes:** `REG-HOSTEDCI-001` e as execuções hospedadas registadas no relatório de CI.
- **Evidência de falha prévia:** `logs/ci-hosted-implementation-20261029/repository-access.json` → `credentialAvailable: false`, `hostedRunStarted: false`.
- **Verificação Windows:** `aprovada`. **Limitações:** a autenticação usou token do proprietário; deve ser rotacionado e nunca gravado no repositório.

### WS-BUG-0002 — Corpus de entrega incompleto no checkout

- **Família / severidade / risco:** CI/Infraestrutura · S2 · N3 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-10 / 2026-11-10
- **Sintoma:** `REJECTED: Missing or outside release: bin/WinSlim.UI.Native.R3.2.84.exe`; mais tarde `[FAIL] R3.2.84 recebido: third_party/PresentMon/PresentMon-2.6.0-x64.exe` e `Integridade de entrada reprovada; compilacao bloqueada.`
- **Cenário de reprodução:** checkout limpo → o `TEST 06B` compara byte a byte os ficheiros do baseline; três não existiam por efeito das regras de exclusão.
- **Comportamento esperado:** o checkout contém os ficheiros do baseline byte a byte.
- **Causa raiz:** regras de exclusão por padrão (`bin/`, `*.exe`) removiam artefactos entregues e fixados por hash, não apenas outputs de build. **Categoria:** `empacotamento`.
- **Correção:** o `.gitignore` passou a excluir apenas conteúdo gerado; os artefactos entregues e o binário oficial de terceiros ficaram rastreados e verificados por SHA-256.
- **Testes:** `REG-BUILDIDENTITY-001` e `REG-HOSTEDDISPLAY-001`.
- **Evidência de falha prévia:** artefactos das execuções `42917048392` e `42918325245`.
- **Verificação Windows:** `aprovada`. **Limitações:** as cópias históricas em `release/winslim-r3284-p*/` continuam excluídas por serem evidência citada apenas por `RETOMADA-R3.2.84-P*.md` e `release/candidate-p*-artifacts.json`.

### WS-BUG-0003 — Hash revisado do manifesto invalidado

- **Família / severidade / risco:** CI/Infraestrutura · S3 · N3 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-10 / 2026-11-10
- **Sintoma:** `[FALHA] Reviewed dependency changed: .github/workflows/windows-candidate.yml` — a política de contenção bloqueou o gate.
- **Cenário de reprodução:** alterar os bytes do workflow sem atualizar `release/review.json` → a política compara o hash e falha fechada.
- **Comportamento esperado:** a alteração e o manifesto revisto são publicados em conjunto.
- **Causa raiz:** reordenação temporária dos passos do workflow (validação depois do build) sem reposicionar a cadeia de revisão. **Categoria:** `ordem_de_operacoes`.
- **Correção:** a reordenação foi revertida — o desenho oficial valida os hashes **antes** da compilação, porque o baseline regista o executável aceite — e o workflow voltou ao byte revisado `47f6235262499ca3...`.
- **Testes:** `REG-SECURITY-001` e a cadeia `baseline`/`review.json`/`security-incidents.json` verificada por `package_release.py`.
- **Evidência de falha prévia:** artefacto da execução `42917525392`. **Verificação Windows:** `aprovada`.

### WS-BUG-0004 — Baseline desatualizado para a revisão de `AGENTS.md`

- **Família / severidade / risco:** CI/Infraestrutura · S2 · N3 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** revisão · **Datas:** 2026-11-10 / 2026-11-10
- **Sintoma:** o `TEST 06B` reprovava em `AGENTS.md` porque o documento de processo foi revisto pelo responsável em 10/11, depois do último reprocessamento do baseline.
- **Cenário de reprodução:** comparar `specs/FASE7-R3.2.84-baseline.json` com o ficheiro revisto → divergência de hash.
- **Comportamento esperado:** o baseline reflecte o documento de processo vigente.
- **Causa raiz:** revisão legítima do documento de processo sem reprocessamento do baseline. **Categoria:** `ordem_de_operacoes`.
- **Correção:** baseline reprocessado para `dfb83a8893fb49deb...`, com verificação de deriva byte a byte de todas as entradas.
- **Testes:** `package_release.py` e `REG-BUILDIDENTITY-001`.
- **Evidência de falha prévia:** verificação local `Release hash mismatch: AGENTS.md`. **Verificação Windows:** `aprovada`.

### WS-BUG-0005 — Workflow inválido por indentação de here-string

- **Família / severidade / risco:** CI/Infraestrutura · S2 · N2 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-11 / 2026-11-11
- **Sintoma:** a execução `42977834181` falhou sem criar jobs: o corpo do here-string PowerShell ficou com indentação 0 e encerrou o bloco escalar YAML.
- **Cenário de reprodução:** `actionlint .github/workflows/windows-candidate.yml` → exit diferente de zero; na CI, workflow inválido e nenhum job.
- **Comportamento esperado:** o workflow é YAML válido e cada bloco PowerShell é sintaticamente válido no Windows PowerShell 5.1.
- **Causa raiz:** escrita do bloco sem a indentação exigida pelo escalonamento YAML. **Categoria:** `empacotamento`.
- **Correção:** indentação corrigida e **validação local obrigatória antes do envio**: `actionlint` (exit 0) e parser do Windows PowerShell 5.1 sobre cada bloco `run:`.
- **Testes:** `REG-HOSTEDCI-001` e a validação local do workflow.
- **Evidência de falha prévia:** execução `42977834181` (sem jobs). **Verificação Windows:** `aprovada`.
- **Limitações:** o ficheiro de configuração do actionlint (Apêndice D, item 3) continua por criar; a validação é executada localmente.

### WS-BUG-0006 — `REG-UI-001` reprovava por área de trabalho insuficiente

- **Família / severidade / risco:** CI/Interface · S2 · N2 · **Estado:** `corrigido` (diagnóstico concluído; validação nativa final em VM Windows 11 pendente)
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-11 / 2026-11-11
- **Sintoma:** `System.IO.InvalidDataException: Detalhe: dimensão ou nome incorreto.` em `MainWindowController.ValidateTweakDetail`, fazendo o `REG-UI-001` reprovar e a execução candidata falhar.
- **Cenário de reprodução:** runner `windows-2022` com ecrã 1024x768 e área de trabalho 1024x728; a asserção exige exatamente 1180x760 e o SO restringe a janela a 1044x760. A mesma árvore byte a byte passa num ambiente de 1920x1080.
- **Comportamento esperado:** o self-test nativo obtém uma janela de 1180x760; quando a sessão não a comporta, o ambiente é declarado inadequado em vez de o produto ser apontado como defeituoso.
- **Causa raiz:** limitação do ambiente interativo do runner (área de trabalho menor que a janela contratada), **não** defeito do produto. Diagnóstico provado com o mesmo instrumento nos dois ambientes: local `afterShow=1180x760` (`contractHeld=true`); runner `afterShow=1044x760` (`contractFits=false`). O nome do ajuste foi confirmado correcto pelo bridge (`bridge-PERF-001.json`), o que excluiu a segunda hipótese da mesma asserção. **Categoria:** `ui`.
- **Classificação:** falha ambiental e de sessão gráfica; **sem evidência de defeito no produto**. O problema é a capacidade gráfica/desktop do host, não a lógica do Win-Slim.
- **Correção adotada:** `tools/validation/HostedDisplayPreparation.ps1` prepara um modo de ecrã compatível (1920x1080 → área 1920x1040) **antes** do gate e **falha fechada** quando a área fica abaixo de 1200x800. A expectativa do self-test (1180x760 exatos) **não foi afrouxada**, nenhuma fonte de produção foi alterada e o binário aceite mantém a identidade `62eb3819580efa1d...`.
- **Testes:** `REG-HOSTEDDISPLAY-001` (19 verificações comportamentais: estado real, recusa de requisito impossível, não-mutação no modo de observação, coerência entre a área observada e o contrato da janela) e `REG-UI-001` (suite nativa completa, 67 s).
- **Evidência de falha prévia:** artefacto da execução `42978644088` (`hosted-diagnostics/window-probe.json` com `afterShow=1044x760`; `bridge-PERF-001.json` com o `name` correcto).
- **Situação atual:** `REG-UI-001` continua a requerer **validação real na VM Windows 11**. O diagnóstico do ambiente foi concluído e o instrumento de preparação foi corrigido, mas a aprovação final da janela nativa em desktop real continua pendente.
- **Verificação Windows:** `pendente` para VM Windows 11; os runs hospedados `42980308809` e `42982286279` validaram a capacidade do diagnóstico e da preparação, mas não substituem a sessão física/VM nativa.
- **Limitações:** a preparação exige sessão interativa com direito a alterar o modo de ecrã; runners sem esse direito falham de forma explícita e o gate não é considerado válido.

### WS-BUG-0007 — Gate local é one-shot

- **Família / severidade / risco:** Gate/Nativo · S2 · N3 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** validação · **Datas:** 2026-11-10 / 2026-11-11
- **Sintoma:** a primeira execução do gate termina com 30/30 e exit 0; a execução imediata seguinte reprova em `REG-UI-001` com `[FAIL] R3.2.84 recebido: bin/WinSlim.UI.Native.R3.2.84.exe`.
- **Cenário de reprodução:** executar o gate duas vezes consecutivas sem restauro do executável aceite.
- **Comportamento esperado:** o gate é repetível sem intervenção manual e restaura o estado aceite mesmo quando uma execução falha.
- **Causa raiz:** o `REG-UI-001` executa build forçado duas vezes; o build publica o novo binário por cima do executável aceite e o `TEST 06B` valida o baseline **antes** do build. **Categoria:** `idempotencia`.
- **Correção:** `tools/validation/NativeBuildRestoration.ps1` captura o EXE/config/cache aceites antes do gate e restaura-os byte a byte no `finally`, com prova SHA-256, staging transacional, rollback em falha parcial e recibo por candidata. `Validar-Candidato-R3.2.84.ps1` passa a falhar se a restauração falhar. Nenhum contrato Apply/Verify/Undo ou fonte C#/WPF foi alterado.
- **Testes:** `REG-RESTORE-001` (`tests/regression/Test-NativeBuildRestoration-R3.2.84.ps1`), 20 verificações comportamentais na fixture inerte; `REG-PIPELINE-001`; duas candidatas oficiais consecutivas com 32/32 suítes, build e self-test WPF.
- **Evidência de falha prévia:** `logs/reg-restore-001-red.log` — exit 1 porque `tools/validation/NativeBuildRestoration.ps1` não existia; `logs/achado-gate-reexecucao-r3.2.84-20261110.md` — segunda execução imediata reprovada antes da correção.
- **Verificação Windows:** `aprovada` — candidatas `logs/candidato-r3284-20261112-040720-434-75e72501` e `logs/candidato-r3284-20261112-041152-998-bd4d5e98`, ambas `TechnicalPassed=true`, 32/32 e restauração do EXE aceite `62eb3819580efa1d1e80151e9934646b796572fe2e9ac786bdb961241a04de62`. **Relacionados:** WS-BUG-0006.
- **Limitações:** a restauração é uma infraestrutura de gate; não altera produção, contracts Apply/Verify/Undo, publication ou `ProductionApproved=false`.

### WS-BUG-0008 — Contagem de suítes divergente no escopo

- **Família / severidade / risco:** Governança · S4 · N1 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** revisão · **Datas:** 2026-11-11 / 2026-11-11
- **Sintoma:** `release/escopo-R3.2.84.json` declarava `requiredWindowsSuites: 28` enquanto o cadastro real tinha 30 (e depois 31).
- **Cenário de reprodução:** comparar `release/escopo-R3.2.84.json` com `tests/regression/cases.json`.
- **Comportamento esperado:** o escopo declara o número real de suítes obrigatórias.
- **Causa raiz:** campo declarativo não atualizado quando o cadastro cresceu. **Categoria:** `outra`.
- **Correção:** atualizado para 31, mantendo o registo como fonte de verdade.
- **Testes:** `package_release.py` (31 casos únicos). **Verificação Windows:** `aprovada`.

### WS-BUG-0009 — Cadeia de revisão não acompanhou o registo de casos

- **Família / severidade / risco:** Segurança/Cadeia · S2 · N3 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-11 / 2026-11-11
- **Sintoma:** ao acrescentar `REG-HOSTEDDISPLAY-001`, o gate reprovou com `Reviewed regression registry changed` e depois `Reviewed case set incomplete`.
- **Cenário de reprodução:** alterar `tests/regression/cases.json` sem atualizar `registrySHA256` e `requiredIds` em `release/review.json`.
- **Comportamento esperado:** a política de contenção aceita o registo revisto e continua a reprovar qualquer divergência real.
- **Causa raiz:** o registo de casos e o manifesto revisto não são atualizados em conjunto. **Categoria:** `ordem_de_operacoes`.
- **Correção:** `registrySHA256` e `requiredIds` passaram a acompanhar o registo; a cadeia `baseline` → `review.json` → `security-incidents.json` foi reprocessada e verificada. O comportamento de **falhar fechada** foi preservado e demonstrado.
- **Testes:** `REG-SECURITY-001` e `package_release.py`.
- **Evidência de falha prévia:** execuções locais `Reviewed regression registry changed` e `Reviewed case set incomplete`.
- **Verificação Windows:** `aprovada`.

### WS-BUG-0010 — Métricas de ecrã em cache na medição da área de trabalho

- **Família / severidade / risco:** CI/Instrumentação · S2 · N2 · **Estado:** `corrigido`
- **Versão encontrada/corrigida:** R3.2.84 / R3.2.84 · **Origem:** CI · **Datas:** 2026-11-11 / 2026-11-11
- **Sintoma:** a preparação do ecrã reprovava no runner com `Area de trabalho final {1024x728} nao atinge o minimo 1200x800`, embora a API tivesse mudado o modo (recibo: `ApiResult: 0`, `ObservedMode: 1920x1080@32/64`).
- **Cenário de reprodução:** ler a área de trabalho antes de uma mudança de ecrã e voltar a lê-la depois **no mesmo processo**; o valor continua o antigo.
- **Comportamento esperado:** cada medição reflete o estado atual do ecrã.
- **Causa raiz:** `System.Windows.Forms.Screen` mantém as métricas do ecrã em cache durante a vida do processo; a leitura posterior à mudança devolvia o valor obsoleto. **Categoria:** `outra`.
- **Correção:** a área de trabalho passou a ser lida do sistema operativo a cada medição (`SystemParametersInfo`/`SPI_GETWORKAREA`), sem cache, e o modo efetivo é confirmado por `EnumDisplaySettings`; a verificação usa sempre a leitura fresca.
- **Testes:** `REG-HOSTEDDISPLAY-001` (coerência entre a área observada e o contrato da janela) e a execução hospedada `43032309531`.
- **Evidência de falha prévia:** artefactos das execuções `43025119487`, `43028580983`, `43029400378` e `43030442755` (todos com `Applied: null` apesar de `ApiResult: 0`).
- **Verificação Windows:** `aprovada`.

## Classificação das suítes quanto ao ambiente de execução

| Grupo | Suítes | Ambiente | Estado |
| --- | --- | --- | --- |
| Headless (sem ecrã interativo) | REG-PROCESS-001, REG-HARNESS-001, REG-BUILD-001, REG-PERF-001, REG-EDGE-001, REG-ENDTASK-001, REG-SEARCH-001, REG-UIBATCH-001, REG-REPORT-001, REG-QOLBATCH-001, REG-EDGEBATCH-001, REG-EDGENEXT-001, REG-EDGEPRIV-001, REG-PIPELINE-001, REG-PRESENTMON-001, REG-MONITOR-001, REG-OVERLAYSETTINGS-001, REG-FRAMELIMITPLAN-001, REG-VMEDGE-001, REG-EDGECOMP-001, REG-NVAPIRO-001, REG-CATALOGBASE-001, REG-CAPTUREIO-001, REG-HOTKEY-001, REG-OVERLAYTHEME-001, REG-HOSTEDCI-001, REG-BUILDIDENTITY-001, REG-SECURITY-001, REG-HOSTEDDISPLAY-001 | qualquer Windows; ecrã interativo não é necessário | **Executadas** (gate local e CI hospedada) |
| Sessão interativa com área ≥ 1180x760 | REG-UI-001 (self-test WPF nativo, build real, XAML real) | sessão gráfica com ecrã adequado | **Executadas** após a preparação do ecrã; reprovam de forma explícita quando a sessão não comporta a janela |
| Aceite físico/VM | captura PresentMon em jogo real, multi-monitor, GPU NVIDIA, efeitos condicionais do Edge | hardware ou VM | **Pendentes** — não pertencem ao gate e não foram repetidos |

Nenhuma suíte foi desativada, afrouxada ou marcada como aprovada sem execução real.



