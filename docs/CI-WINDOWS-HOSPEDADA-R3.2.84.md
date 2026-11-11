# CI Windows hospedada — R3.2.84

29/10/2026, America/Sao_Paulo. **Implementação local preparada; execução hospedada pendente; produção pendente.** Não foi criado pacote de distribuição, release, commit, branch remoto ou publicação.

## Fluxo implementado

[Workflow](../.github/workflows/windows-candidate.yml): `push`, `pull_request` e `workflow_dispatch`; um job `windows-2022`, Windows PowerShell 5.1 x64, limite de 45 minutos. Permissão única `contents: read`, checkout sem persistência de credencial, sem secrets adicionais, cache de dependências ou ambiente de produção. As três ações estão fixadas por commit. O workflow não usa `pull_request_target` nem autoelevação.

O início registra contexto e hashes dos arquivos recebidos, com diretório exclusivo fora do checkout em `$RUNNER_TEMP/winslim-ci-<run_id>-<run_attempt>`. A CLI oficial `python tools/package_release.py . specs/FASE7-R3.2.84-baseline.json`, **sem destino**, verifica cadastro único, scripts e hashes antes da compilação. O aceite técnico é exclusivamente `Iniciar-Validacao.bat /ci` → `Validar-Candidato-R3.2.84.ps1 -NoLaunch` → `Executar-Regressoes.ps1`, usando todo o cadastro atual, build oficial e self-test WPF. As dez delegações nativas permanecem intactas. Os 22 testes do empacotador pertencem à suíte REG-SECURITY-001 e não são repetidos em um step adicional.

O coletor não decide aprovação do gate. Depois da execução, conserva somente logs textuais novos/alterados, resultados, contexto permitido e hashes. Se o step oficial informar sucesso sem um par novo `summary.json`/`regressions.json` da candidata, a coleta falha. Resultados vazios/parciais/duplicados continuam recusados pelas funções oficiais. DLLs, EXEs, arquivos MZ disfarçados e ZIPs não entram no upload. O EXE/config e o diagnóstico oficial gerados são identificados por hash. Mesmo a coleta de uma falha não declara aprovação.

`always()` tenta coletar e enviar evidências em falhas normais. Ausência de arquivos é erro; upload falho impede sucesso do job. Encerramento abrupto do runner pode impedir coleta; execução cancelada/parcial nunca aprova a CI. O artefato `WinSlim-CI-<run_id>-<run_attempt>` tem retenção de 14 dias. URL, ID e digest do artefato aparecem no resumo do job; devem ser preservados no projeto antes de expirar a retenção.

## Dependências e origens

| Dependência | Versão/origem e motivo |
| --- | --- |
| Windows Server / PowerShell / .NET Framework / WPF / csc / Git | Imagem oficial [`windows-2022`](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md). PowerShell **5.1 x64** e csc do Framework em `v4.0.30319`; o build continua C# 5. Imagem e patches são móveis: `context.json` conserva ImageOS/ImageVersion, e `dependencies.json` conserva versão do SO/PowerShell/Git, Release do Framework, identidade WPF e versão/hash do compilador. Não se atribuiu à imagem hospedada a versão observada no host local. |
| Python de desenvolvimento | **3.13.12 x64**, selecionado por setup-python. [Manifesto oficial](https://github.com/actions/python-versions/blob/main/versions-manifest.json), [artefato identificado](https://github.com/actions/python-versions/releases/download/3.13.12-21673645133/python-3.13.12-win32-x64.zip); cópia da origem em `logs/ci-hosted-implementation-20261029/python-3.13.12-origin.json`. Usado pelo empacotador em modo validação, testes unittest, oráculo ctypes NVAPI e transporte de evidências. Somente biblioteca padrão; nenhum pip install. O app não passa a exigir Python. Versão completa/hash do interpretador entram no contexto da execução. |
| actions/checkout | **v4.3.1**, `34e114876b0b11c390a56381ad16ebd13914f8d5`, [origem oficial](https://github.com/actions/checkout/tree/34e114876b0b11c390a56381ad16ebd13914f8d5). |
| actions/setup-python | **v5.6.0**, `a26af69be951a213d495a4c3e4e4022e16d87065`, [origem oficial](https://github.com/actions/setup-python/tree/a26af69be951a213d495a4c3e4e4022e16d87065). |
| actions/upload-artifact | **v4.6.2**, `ea165f8d65b6e75b540449e92b4886f43607fa02`, [origem oficial](https://github.com/actions/upload-artifact/tree/ea165f8d65b6e75b540449e92b4886f43607fa02). |
| Corpus já revisado | Catálogos, baselines e fontes fixadas NVAPI/PresentMon que o cadastro já exige. O console oficial PresentMon 2.6.0 continua opcional no runtime; os testes do gate são de dados/transporte DLL-only, sem captura ETW real. Não há download/instalação de driver, SDK NVIDIA/AMD, serviço ou coletor de teste. |
| actionlint, somente validação local | **1.7.12 windows/amd64**, [release oficial](https://github.com/rhysd/actionlint/releases/tag/v1.7.12). ZIP SHA-256 `6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9`, conferido contra checksums oficiais antes da execução. Arquivos/origem/licença conservados em `logs/ci-hosted-implementation-20261029/`. Não foi incluído no aplicativo. |

Tags/commits das ações foram resolvidos pela API oficial; registro em `action-origins.json`. A fixação por SHA e a permissão mínima seguem a [documentação de segurança do GitHub](https://docs.github.com/en/actions/reference/security/secure-use).

## Correções necessárias à CI

**REG-HOSTEDCI-001:** o teste de checkout com autocrlf ativo falhou antes da correção: `b'first\nsecond\n'` tornou-se CRLF. `.gitattributes` usa `* -text` para preservar os bytes existentes, inclusive a mistura legítima LF/CRLF das baselines. Não houve renormalização de arquivos ou alteração da configuração global do Git. Os oito testes exercitam checkout real em repositórios descartáveis, seleção de evidências, falha/indisponibilidade, preservação do estado, hashes e ausência de credenciais. O coletor não existia: não há teste hospedado antes/depois do upload antigo; essa limitação não é apresentada como aprovação.

Na conferência final, um teste ampliado reproduziu a omissão de um log aninhado chamado `SHA256.json` no manifesto de integridade do coletor novo. A correção exclui somente o manifesto raiz de seu próprio hash; os nomes iguais em subpastas são cobertos. O teste exige igualdade entre o conjunto integral de arquivos copiados e as entradas do manifesto, além de conferir cada digest. A falha anterior está em `nested-integrity-before.log`; o cadastro registra o defeito dentro de REG-HOSTEDCI-001.

**REG-BUILDIDENTITY-001:** a primeira candidata local falhou em REG-UI-001 após build e WPF aprovados, pois o EXE recompilado foi comparado ao hash da entrega anterior. O csc do Framework não tem contrato de saída determinística entre compilações/ambientes. Agora **todos** os arquivos da baseline são conferidos antes de compilar. Depois do self-test, todas as entradas continuam conferidas e somente EXE/config usam o recibo do build oficial, capturado e validado antes do teste. Treze checks inertes rejeitam recibo antigo/ausente/parcial, fonte alterada, binário alterado após teste e entradas indisponíveis/externas; o dicionário de expectativas não é modificado. Os relatórios `native-integrity-r3.2.84-before.json` e `-after.json` conservam as duas identidades. O builder e as fontes do aplicativo não foram alterados.

O cadastro possui **30 casos**, e o manifesto **53 activeFiles**. A extensão e os hashes estão em [revisão de escopo](../REVISAO-TECNICA-GATE-R3.2.84.md), `release/review.json` e `release/security-incidents.json`. Guard-only/fontes retidas continuam idênticos; nenhuma geração ou execução dos dois harnesses retidos. `component-contained`, incidente histórico não resolvido e hold de publicação/produção permanecem.

## Escopo dos ambientes

| Ambiente | Incluído / separado |
| --- | --- |
| Runner hospedado | Cadastro completo atual, fixtures isoladas de IO/Registro, ABI ctypes/.NET, pipes locais, DLLs independentes, WPF automatizado/STA/HWND e geometria/DPI simulados; build e IfNeeded oficiais; segurança e empacotador em modo teste/validação. Sem Apply real no Windows do runner. |
| VM autorizada | Alterar tema do Windows, interação visual do aplicativo, Edge real/Review/Apply/Verify/Undo e reconhecimento no navegador. Aceites anteriores permanecem preservados; nada foi repetido nesta rodada. |
| Hardware/jogo/interação física | Jogo real, ETW/PresentMon oficial real, passagem de cliques/foco físicos, sensores e GPU reais, DPI físico e múltiplos monitores. CI não os aprova. Aceites de temas/jogo e Edge já informados continuam válidos. Multimonitor físico permanece não demonstrado; arraste livre/overlay visível é o requisito. |

## Validações e evidências locais

Pasta principal: `logs/ci-hosted-implementation-20261029/`.

- `workflow-validation.json` e `actionlint-final.log`: actionlint **exit 0**, YAML/esquema/expressões. `workflow-powershell-syntax.json`: **seis** blocos `run` analisados pelo parser real do PowerShell 5.1, sem erros.
- `git-eol-before.log`: falha comportamental antes da correção. `ci-evidence-final-python311.log`: **8 testes aprovados** com Python 3.11.9; a regressão oficial também executa os testes com Python 3.13.0 local.
- `build-identity-focused.log`: **13 checks aprovados**. A falha completa anterior permanece em `official-candidate.log`, `first-failed-evidence/` e `first-failed-diagnostic.zip`.
- `repository-access.json`, `initial-state.json`, `repository-public-discovery.json`: estado de acesso, sem credenciais persistidas/expostas. `preserved-scope.json` e `held-policy-check.json`: arquivos anteriores e recusa das famílias, sem invocar geradores.
- `before/` e `before-files.json`: arquivos alterados e identidades anteriores. O teste nativo foi reconstituído pelo patch e gravado somente após corresponder exatamente ao SHA-256 original revisado `8a0cabf58458aa06f9fa172e708032f5e5680ea0e864cf7ee381500fd20c32cb`; `native-test.diff` permite a comparação textual.

**Gate oficial local final aprovado: 30/30 IDs distintos, build e self-test WPF, exit 0.** [Relatório completo](../logs/regressao-20261029-164438-685-d188a4dd/resultado.json), [resumo da candidata](../logs/candidato-r3284-20261029-164438-424-5847dd2f/summary.json), `official-candidate-stabilized.log`. TechnicalPassed=true, ProductionApproved=false. Os 22 testes do empacotador passaram dentro de REG-SECURITY-001; testes de CI passaram também pelo runner oficial usando Python 3.13.0 local. A versão hospedada 3.13.12 foi executada a partir de 10/11/2026 (ver "Execução hospedada").

O transporte real local conservou **111 logs textuais novos/alterados** em `stabilized-evidence/logs/`; `stabilized-evidence/context.json` registra Hosted=false e RunURL=null, e `stabilized-evidence/SHA256.json` identifica todos os arquivos copiados. Nenhum EXE/DLL/ZIP entrou nessa pasta. Foram conferidos novamente os hashes da cópia preservada. O build validado tem SHA-256 `d783a3d5c62b222d6bfe62e92cb1aa365a847de23812759d7982412870161365`; sua identidade e recibo constam nas evidências, sem distribuição do binário.

Como esta alteração é de infraestrutura, o EXE operacional aceito `62eb3819580efa1d1e80151e9934646b796572fe2e9ac786bdb961241a04de62` e seu cache original compatível foram restaurados byte a byte ao final. A identidade de todas as entradas do build permaneceu igual à cópia aceita. [Recibo de restauração](../logs/ci-hosted-implementation-20261029/post-validation-restoration-stabilized.json). Os relatórios do gate continuam identificando o build novo efetivamente testado, sem atribuir a ele os aceites físicos anteriores. A baseline final mantém o hash do EXE entregue/aceito; nenhuma expectativa foi atualizada para encobrir a falha inicial.

## Execução hospedada: registo real e o que falta

**Execuções hospedadas iniciadas em 10/11/2026.** A pasta de trabalho foi inicializada como repositório Git, recebeu o remoto `https://github.com/pauloatx/Win-Slim.git` e envia a branch `master`. `gh` continua não instalado; a autenticação non-interactive foi feita com token de conta autenticada do proprietário, nunca gravado no repositório nem em log.

| Run | Evento | SHA | Resultado | Causa registrada |
| --- | --- | --- | --- | --- |
| [42917048392](https://github.com/pauloatx/Win-Slim/actions/runs/42917048392) | `workflow_dispatch` | `41909af` | **failure** | `REJECTED: Missing or outside release: bin/WinSlim.UI.Native.R3.2.84.exe` — as regras de exclusão do repositório removiam do checkout os artefatos entregues exigidos pelo baseline |
| [42917525392](https://github.com/pauloatx/Win-Slim/actions/runs/42917525392) | `workflow_dispatch` | `d901a9b` | **failure** | `[FALHA] Reviewed dependency changed: .github/workflows/windows-candidate.yml` — a reordenação dos passos invalidou o hash revisado do manifesto de segurança |
| [42918314152](https://github.com/pauloatx/Win-Slim/actions/runs/42918314152) | `workflow_dispatch` | `8de239b` | **cancelled** | cancelado pelo grupo de concorrência quando o evento `push` iniciou a execução seguinte; cancelamento não aprova nada |
| [42918325245](https://github.com/pauloatx/Win-Slim/actions/runs/42918325245) | `push` | `8de239b` | **failure** | `[FAIL] R3.2.84 recebido: third_party/PresentMon/PresentMon-2.6.0-x64.exe` → `Integridade de entrada reprovada; compilacao bloqueada.` (TEST 06B, REG-UI-001) |
| [42977834181](https://github.com/pauloatx/Win-Slim/actions/runs/42977834181) | `push` | `7ac35c2` | **failure** | workflow inválido: o corpo do here-string PowerShell ficou com indentação 0 e encerrou o bloco YAML; nenhuma suíte executou |
| [42978644088](https://github.com/pauloatx/Win-Slim/actions/runs/42978644088) | `push` | `c02f516` | **failure** | diagnóstico executado: `Detalhe: dimensão ou nome incorreto.` reproduzido; nome confirmado correto pelo bridge e janela medida pelo SO |
| [42980308809](https://github.com/pauloatx/Win-Slim/actions/runs/42980308809) | `push` | `39431b2` | **success** | **CI hospedada aprovada**: 30/30 suítes, build e self-test WPF verdes, `TechnicalPassed=true` |

Artefato da execução aprovada: `WinSlim-CI-42980308809-1`, ID `13837042851`, 192 467 bytes, retenção 14 dias. As evidências textuais da execução (contexto, hashes de entrada, `dependencies.json`, `display-preparation.json`, par `summary.json`/`regressions.json` da candidata, `resultado.json` com 30 casos aprovados e `SHA256.json`) foram preservadas no artefacto.

Ambiente real observado: GitHub Actions `windows-2022`, imagem `20261101.353.1`, Windows Server 2022 `10.0.20348`, Windows PowerShell **5.1.20348.5773 x64**, .NET Framework release `533509`, `csc.exe` `4.8.9363.0` (SHA-256 `baef2676444878d5818628f46483f4e55241d6380ecff0bbb855c470852e1872`), Python **3.13.12 x64**, Git `2.56.0.windows.4`.

### Correções aplicadas após a execução real

1. **Corpus de entrega rastreado.** As regras de exclusão passaram a ignorar apenas conteúdo gerado (`logs/`, `evidencias/`, cache Python, ZIP de diagnóstico, staging transitório de build). O repositório passa a rastrear **os 248 ficheiros do baseline byte a byte**, incluindo o executável nativo aceite `bin/WinSlim.UI.Native.R3.2.84.exe` (`62eb3819580efa1d...`), o respetivo `.exe.config` e o binário oficial de terceiros fixado `third_party/PresentMon/PresentMon-2.6.0-x64.exe` (`b2a706bc6ad47574...`). As cópias históricas sob `release/winslim-r3284-p*/` continuam excluídas e citadas apenas por `RETOMADA-R3.2.84-P*.md` e `release/candidate-p*-artifacts.json`.
2. **Ordem do workflow restaurada.** A reordenação temporária (validação depois do build) foi revertida: o desenho oficial valida os hashes **antes** da compilação, porque o baseline regista o executável operacional aceite. O workflow volta ao byte revisado `47f6235262499ca3ae269615112ec9b6d8fbdc58d5f2ffabe8a7638f6508c39f`, e `release/review.json` / `release/security-incidents.json` / o baseline mantêm a cadeia de revisão intacta.
3. **Baseline renovado para a revisão de `AGENTS.md` de 10/11/2026** (`dfb83a8893fb49deb...`). A revisão do documento de processo pelo responsável ocorreu depois do último reprocessamento do baseline e fazia o TEST 06B reprovar localmente e na CI.
4. **Diagnóstico hospedado antes de qualquer alteração de produto.** O `REG-UI-001` reprovava dentro do próprio self-test com `Detalhe: dimensão ou nome incorreto.`, mensagem sem valores. Um passo de diagnóstico **apenas de CI** capturou o ambiente real (ecrã 1024x768, área de trabalho 1024x728, cultura en-US), a resposta real do bridge (`name` correto e ASCII) e a evolução do tamanho da janela: `1180x760` antes de ser apresentada e **1044x760** depois. Conclusão: a janela contratada de 1180x760 não cabe na área de trabalho do runner e o SO restringe-a; a asserção de tamanho exato falha por ambiente, não por defeito do produto.
5. **Preparação do ecrã do runner antes do gate.** Um passo novo aplica um modo de ecrã compatível (1920x1080 → área de trabalho 1920x1040) e **falha fechada** se a área ficar abaixo de 1200x800, em vez de deixar o gate reprovar por uma limitação do runner. Com o ecrã preparado, a janela mantém 1180x760 e o self-test fecha verde.

Nenhuma fonte de produção, contrato Apply/Verify/Undo, harness retido ou aceite físico foi alterado por estas correções de infraestrutura. O binário aceite `62eb3819580efa1d...` e as cadeias de revisão mantêm-se intactos.

### Execução aprovada

| Item | Valor real |
| --- | --- |
| Run | [42980308809](https://github.com/pauloatx/Win-Slim/actions/runs/42980308809) (evento `push`, SHA `39431b2`, tentativa 1) |
| Conclusão | **success**, job `candidate` com 12/12 passos aprovados |
| Gate | **30/30 casos de regressão**, `Passed=true`, `ExitCode=0`, nenhuma falha |
| Candidata | `TechnicalPassed=true`, `ProductionApproved=false`, `ManualValidation=Pending`, `Error=null` |
| Evidência | `FreshCandidateEvidence=true`, 111 logs textuais alterados, `SHA256.json` do artefacto |
| Ambiente | `windows-2022` imagem `20261101.353.1`, PowerShell 5.1.20348.5773 x64, Python 3.13.12 x64, ecrã 1920x1080 (área 1920x1040) |
| Artefato | `WinSlim-CI-42980308809-1`, ID `13837042851`, retenção 14 dias |

### O que falta

1. Conservar URL/run_id/run_attempt, SHA/branch/evento e imagem reais, logs, artefacto ID/URL/digest e o seu `SHA256.json` antes do expirar a retenção de 14 dias, e anexar o artefacto ao registo do projeto.
2. Preparar a revisão textual do resultado hospedado (incluindo a rejeição do `REG-UI-001` no ecrã pequeno e a preparação do ecrã como evidência de ambiente).
3. Publicação/produção continuam pendentes: incidente AV-20261021-001 não resolvido pelo fabricante, `productionApproved=false`, distribuição em `hold`, aceites físicos e de VM pendentes. Nenhuma família física já aceita precisa ser repetida por esta alteração de infraestrutura.

## Arquivos da implementação

| Grupo | Arquivos novos/alterados |
| --- | --- |
| CI e transporte | `.github/workflows/windows-candidate.yml`, `.gitattributes`, `.gitignore`, `tools/ci_evidence.py` |
| Integridade nativa | `tools/validation/NativeBuildIntegrity.ps1`, `tests/Test-Fase7-R3.2.84-NativeUI.ps1` |
| Regressões | `tests/test_ci_evidence.py`, `tests/regression/Test-HostedCI-R3.2.84.ps1`, `tests/regression/Test-NativeBuildIntegrity-R3.2.84.ps1`, `tests/regression/cases.json` |
| Cadeia de revisão | `release/review.json`, `release/security-incidents.json`, `specs/FASE7-R3.2.84-baseline.json`, `REVISAO-TECNICA-GATE-R3.2.84.md` |
| Continuidade | `RETOMADA-R3.2.84-AV.md`, `docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md`, este relatório e `docs/REVISAO-NEMOTRON-CI-R3.2.84.md` |
| Corpus entregue (rastreado pelo Git) | `bin/WinSlim.UI.Native.R3.2.84.exe`, `bin/WinSlim.UI.Native.R3.2.84.exe.config`, `third_party/PresentMon/PresentMon-2.6.0-x64.exe` |

Os arquivos auxiliares/evidências desta rodada ficam na pasta de logs indicada. Não houve alteração de produção nas fontes C#/XAML/backend, nos contratos Apply/Verify/Undo ou no runtime PresentMon.
