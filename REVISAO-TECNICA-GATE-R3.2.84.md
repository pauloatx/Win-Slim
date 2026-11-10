# Revisão Técnica de Alcance do Bloqueio — WinSlim Fase 7 R3.2.84

## Extensão de CI Windows hospedada — 29/10/2026

O pedido do responsável autoriza implementar e validar a CI prevista no cronograma. A extensão acrescenta `REG-HOSTEDCI-001` e `REG-BUILDIDENTITY-001` ao cadastro: **30 casos e 53 activeFiles**, obtidos dos arquivos atuais. Sete arquivos entram no manifesto: `.gitattributes`, workflow, coletor Python, teste Python/runner da CI e helper/teste da integridade nativa. Os 46 activeFiles anteriores, os dois guard-only e as duas fontes retidas foram conferidos sem divergências antes da extensão. Posteriormente, somente o runner nativo entre os arquivos anteriores foi alterado pela correção de identidade descrita abaixo. Nenhuma fonte C#/WPF/backend, compilador ou regra de delegação do executor oficial foi alterada.

O workflow chama `Iniciar-Validacao.bat /ci`, preservando compilação, self-test WPF, cadastro completo e delegação oficial. Python é ferramenta de desenvolvimento; o coletor apenas transporta logs textuais novos/alterados, contexto permitido e hashes. Não decide aprovação técnica e não cria pacote de distribuição. Um par novo de relatórios da candidata é exigido quando o step oficial informa sucesso; relatórios históricos não suprem essa evidência. Binários, DLLs e ZIPs não entram no upload. A pré-validação usa a CLI oficial do empacotador sem destino, antes de o build produzir um novo EXE. Os testes do empacotador já pertencem a REG-SECURITY-001 e não são duplicados em outro step.

O teste Git em repositório descartável falhou antes da correção ao converter LF para CRLF com autocrlf ativo; `.gitattributes` conserva os bytes das baselines em ambos os formatos. Os testes do coletor exercitam sucesso de transporte, falha/indisponibilidade, estado anterior, credenciais, arquivos binários disfarçados e integridade. Não havia coletor anterior para executar um teste antes da implementação; o upload antigo não foi executado no GitHub nesta rodada. Resultados reais e limites estão em [CI Windows hospedada](docs/CI-WINDOWS-HOSPEDADA-R3.2.84.md).

A revisão final ampliou o teste de integridade e reproduziu a omissão de um arquivo aninhado `SHA256.json` no coletor novo. Corrigiu-se a exclusão por nome para excluir exclusivamente o manifesto raiz; a igualdade entre todos os arquivos copiados e todas as entradas de hash agora é exigida pelo teste, sem reduzir expectativas. Defeito registrado em REG-HOSTEDCI-001, evidência anterior preservada e gate fresco exigido após a alteração do coletor.

O primeiro gate desta rodada reproduziu uma falha real em REG-UI-001: build forçado, substituição do EXE e self-test WPF passaram, mas o teste final comparou o EXE recém-gerado com o hash do binário entregue. Não se pressupõe saída determinística do csc do .NET Framework. A correção verifica **todos** os hashes recebidos antes de compilar e bloqueia o build se houver divergência. Após self-test, verifica novamente todas as entradas e compara exclusivamente EXE/config com o recibo do build oficial, já validado e capturado antes do self-test. As expectativas recebidas não são modificadas; alteração de fonte, recibo obsoleto/incompleto ou alteração posterior do binário continuam falhando. Há 13 checks comportamentais em fixtures inertes, mais a integração pelo teste nativo real. A cópia histórica aceita de `logs/overlay-theme-vm-20261026-5410de9a/candidate-final/bin/` foi conferida e usada para restabelecer a entrada original antes da nova execução, sem alterar seu hash esperado. Nenhum hash divergente foi simplesmente promovido para ocultar a falha.

`component-contained`, `resolution=null`, `historicalIncidentResolved=false` e os bloqueios de publicação/produção continuam preservados. Nenhuma família retida foi gerada ou executada; a verificação das recusas foi feita somente pela função de política, sem chamar os geradores antigos. A revisão não equivale a parecer do fabricante. **CI hospedada permanece pendente até execução real bem-sucedida**; validação local de YAML e gate Windows local não substituem esse requisito. Aceites físicos e Apply/Undo Edge já aprovados não foram repetidos.

## Extensão de tema do overlay — 26/10/2026

Escopo autorizado pelo responsável nesta rodada: preferências opcionais Claro/Escuro/Automático do overlay e seu editor, seguindo o Windows no automático, preservando captura e a correção UI-HOTKEY-WPARAM-001. O cadastro passa a **28 casos**, com `REG-OVERLAYTHEME-001`. O manifesto passa a **46 activeFiles**: inclui runner/fixture DLL-only novos e as três fontes de produção revisadas (`BenchmarkOverlay.cs`, `BenchmarkSettingsWindow.cs`, `MainWindowController.cs`, neste último somente ampliação do self-test de captura pendente). Os 41 activeFiles anteriores, guard-only e held sources foram conferidos sem divergências antes da extensão.

O novo runner compila exclusivamente produção e fixture em biblioteca sem Main; registra compilador/fontes/DLL antes da carga e conserva falhas. Seis checks comportamentais falharam antes da correção; 75 checks focados passaram após a implementação. Alterações de tema do Windows e validação visual ficam restritas à VM autorizada; fixtures no host usam diretórios descartáveis e fonte de tema injetada, sem mudar o Registro do host. Nenhuma compilação/execução de PresentMonHarness ou MonitorHarness foi introduzida. Status component-contained, bloqueios de publicação/produção e incidente histórico não resolvido permanecem preservados. Gate final completo 28/28 + WPF e validação visual na VM concluídos; fonte do Hook de atalhos intacta. Acessibilidade do conteúdo das abas e seleção efetiva corrigidas com reprodução comportamental. A limpeza externa do BenchmarkOverlayHarness reutiliza o helper delimitado existente e suas provas de IO transitório/persistente; nenhuma expectativa enfraquecida. Resultados e histórico em docs/OVERLAY-TEMAS-R3.2.84-20261026.md.

## Extensão autorizada de 26/10/2026 — REG-HOTKEY-001

O cadastro atual passa de 26 para **27 suítes**, acrescentando `tests/Test-Fase7-R3.2.84-HotkeyWParam.ps1` e `tests/fixtures/HotkeyWParamFixture.cs`. A biblioteca compila somente a fixture e `src/UI/Native/R3_2_84/BenchmarkSettings.cs`, com `/target:library`, C# 5 e as referências WPF explícitas do build oficial. Não contém Main, coletor, ETW ou fontes das duas famílias retidas. O runner verifica a política pela família independente `HotkeyWParamFixtures`, registra hashes do compilador/fontes/DLL antes da carga e conserva os artefatos e resultados.

Revisão comportamental: o Hook privado de produção é vinculado a `HwndSourceHook`; mensagens alheias e IDs extremos de 64 bits reproduziram **48 falhas em 113 checks**, todas OverflowException, antes da correção. Após filtrar `msg` primeiro e comparar o ID obtido por `ToInt64()` antes da subtração/conversão, **113/113 passaram**. Há HWND WPF real em STA, entrega por SendMessage e remoção no Dispose; Apply/rollback usa registros simulados e arquivo isolado, sem registrar atalhos globais ou aplicar otimizações no host. A sequência inicial de execução também revelou e corrigiu uma conversão PSObject/string no runner, antes de executar os checks; esse erro da infraestrutura não é a reprodução do produto.

`release/review.json` incorpora os dois arquivos novos, a fonte de produção e `tools/TestArtifactProvenance.ps1`; os 37 arquivos ativos anteriores foram conferidos sem divergência. Hash do cadastro → manifesto → incidente/escopo → spec. As famílias `PresentMonHarness`/`MonitorHarness` permanecem retidas e bloqueadas. A política, suas expectativas e o status `component-contained` não foram afrouxados. A ocorrência original não registrou o par msg/wParam; a reprodução determinística confirma o defeito do código, sem inventar esses parâmetros históricos. Gate fresco concluído em 26/10: Iniciar-Validacao.bat /ci retornou 0, 27/27 suítes, build oficial e self-test WPF aprovados; resultados em [ocorrência](docs/OCORRENCIA-UI-HOTKEY-WPARAM-20261024.md).

As seções abaixo preservam a revisão histórica de 23/10; suas contagens e menções à transição ainda não aplicada descrevem aquele momento, não o estado vigente.

**Data:** 23/10/2026  
**Autoridade:** Revisão técnica autorizada (não resolução de fabricante)  
**Incidente:** AV-20261021-001 — `status: investigating` (não resolvido pelo fabricante)  
**Antivírus:** Kaspersky ativo, sem exclusões, detecção recorrente VHO:Trojan-PSW.Win32.Disco.gen

---

## 1. Registro Exato de Logs, Comandos, Códigos de Saída e Identidade dos Arquivos Testados

### 1.1 Suítes de Dados/Fixtures Executadas (114 verificações comportamentais)

| Suíte | Script | Caminho do Log (padrão) | Verificações | Código de Saída |
|-------|--------|------------------------|--------------|-----------------|
| **CaptureTransport** | `tests/Test-Fase7-R3.2.84-CaptureTransport.ps1` | `logs/capture-data-<GUID>/` + `compiler.log` + `provenance-before-load.json` | 57 | 0 (sucesso) |
| **PresentMonData** | `tests/Test-Fase7-R3.2.84-PresentMonData.ps1` | `logs/capture-data-<GUID>/` + `provenance-before-load.json` | 36 | 0 (sucesso) |
| **MonitorData** | `tests/Test-Fase7-R3.2.84-MonitorData.ps1` | `logs/capture-data-<GUID>/` + `provenance-before-load.json` | 20 | 0 (sucesso) |
| **OverlaySensors** | `tests/Test-Fase7-R3.2.84-OverlaySensors.ps1` | Incluso em MonitorData | 1 | 0 (sucesso) |

**Total:** 114 verificações comportamentais — **todas aprovadas**.

### 1.2 Identidade dos Artefatos Compilados (DLL-only, sem entry point)

| Artefato | Caminho de Saída | SHA-256 (exemplo) | Fontes | Contém Main? | Harness Incluído? |
|----------|------------------|-------------------|--------|--------------|-------------------|
| `WinSlim.Capture.Data.dll` | `logs/capture-data-<GUID>/WinSlim.Capture.Data.dll` | Variável por execução | `PresentMonBenchmark.cs`, `BenchmarkLive.cs`, `PresentMonMonitor.cs`, `CaptureTransportFixture.cs` (quando transport) | **Não** | **Não** |

**Proveniência registrada antes da carga** (`provenance-before-load.json`):
- `Kind: "data-fixture-library"`
- `ContainsEntryPoint: false`
- `BlockedHarnessSourceIncluded: false`
- `Compiler: "C:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe"` (SHA-256 do compilador registrado)
- Fontes e hashes individuais listados
- DLL hash registrado

### 1.3 Comandos de Compilação (apenas biblioteca, sem executável)

```powershell
csc.exe /nologo /noconfig /target:library /langversion:5 /warnaserror:4014 \
  /reference:System.dll /reference:System.Core.dll \
  /out:WinSlim.Capture.Data.dll \
  PresentMonBenchmark.cs BenchmarkLive.cs PresentMonMonitor.cs [CaptureTransportFixture.cs]
### 2.1 Catálogo de Regressão Ativo (`tests/regression/cases.json`)

25 casos cadastrados, **zero** referenciando harness antigos:

| ID | Script | Família |
|----|--------|---------|
| REG-PROCESS-001 | `tests/regression/Test-ProcessExitCode.ps1` | Processo |
| REG-HARNESS-001 | `tests/regression/Test-RegressionPaths-R3.2.84.ps1` | Caminhos |
| REG-BUILD-001 | `tests/regression/Test-DispatcherAwait.ps1` | Build UI |
| REG-PERF-001 | `tests/Test-Fase7-R3.2.84-Performance.ps1` | Performance |
| REG-UI-001 | `tests/Test-Fase7-R3.2.84-NativeUI.ps1` | UI Nativa |
| REG-EDGE-001 | `tests/Test-Fase7-R3.2.84-Edge.ps1` | Edge |
| REG-ENDTASK-001 | `tests/Test-Fase7-R3.2.84-EndTask.ps1` | EndTask |
| REG-SEARCH-001 | `tests/Test-Fase7-R3.2.84-SearchIcon.ps1` | Search |
| REG-UIBATCH-001 | `tests/Test-Fase7-R3.2.84-UiBatch.ps1` | UI Batch |
| REG-REPORT-001 | `tests/Test-Fase7-R3.2.84-Report.ps1` | Relatório |
| REG-QOLBATCH-001 | `tests/Test-Fase7-R3.2.84-QolBatch.ps1` | QoL |
| REG-EDGEBATCH-001 | `tests/Test-Fase7-R3.2.84-EdgeBatch.ps1` | Edge Batch |
| REG-EDGENEXT-001 | `tests/Test-Fase7-R3.2.84-EdgeNext.ps1` | Edge Next |
| REG-EDGEPRIV-001 | `tests/Test-Fase7-R3.2.84-EdgePrivacy.ps1` | Edge Privacy |
| REG-PIPELINE-001 | `tests/Test-Fase7-R3.2.84-Pipeline.ps1` | Pipeline |
| **REG-PRESENTMON-001** | **`tests/Test-Fase7-R3.2.84-PresentMonData.ps1`** | **Dados (DLL-only)** |
| REG-OVERLAY-001 | `tests/Test-Fase7-R3.2.84-BenchmarkOverlay.ps1` | Overlay |
| **REG-MONITOR-001** | **`tests/Test-Fase7-R3.2.84-MonitorData.ps1`** | **Dados (DLL-only)** |
| REG-OVERLAYSETTINGS-001 | `tests/Test-Fase7-R3.2.84-OverlaySettings.ps1` | Overlay Settings |
| REG-SECURITY-001 | `tests/regression/Test-SecurityHold-R3.2.84.ps1` | Segurança |
| REG-FRAMELIMITPLAN-001 | `tests/regression/Test-FrameLimitPlan-R3.2.84.ps1` | Limitador |
| REG-VMEDGE-001 | `tests/regression/Test-EdgeVmEvidence-R3.2.84.ps1` | Edge VM |
| REG-EDGECOMP-001 | `tests/Test-Fase7-R3.2.84-EdgeCompletion.ps1` | Edge Completion |
| REG-NVAPIRO-001 | `tests/regression/Test-NvapiReadOnly-R3.2.84.ps1` | NVAPI Read-only |
| REG-CATALOGBASE-001 | `tests/regression/Test-HistoricalCatalog-R3.2.84.ps1` | Catálogo Histórico |
| **REG-CAPTUREIO-001** | **`tests/Test-Fase7-R3.2.84-CaptureTransport.ps1`** | **Transport/Preview (DLL-only)** |

### 2.2 Build da UI Nativa (`Build-NativeUI-R3.2.84.ps1`)

**Fontes explícitas compiladas (14 arquivos C#):**
```
Program.cs, BridgeClient.cs, MainWindowController.cs, UiLanguage.cs, UiTheme.cs,
ApplicationReport.cs, PresentMonBenchmark.cs, BenchmarkLive.cs, PresentMonMonitor.cs,
BenchmarkGameWindow.cs, BenchmarkOverlay.cs, BenchmarkOverlayDesktop.cs,
BenchmarkSettings.cs, BenchmarkSettingsWindow.cs
```

**NÃO incluídos:** `tests/PresentMonHarness.cs`, `tests/MonitorHarness.cs`, `tests/BenchmarkOverlayHarness.cs`, `tests/OverlaySettingsHarness.cs`

**Saída:** `bin/WinSlim.UI.Native.R3.2.84.exe` (aplicação WPF, não harness)

### 2.3 Empacotamento (`tools/package_release.py`)

- **Perfil `validation`**: Inclui fontes de teste, scripts, DLLs de fixture
- **Perfil `runtime`**: Requer `--runtime-manifest` com allowlist revisada; **não inclui** harness sources/executables
- **Validação de segurança** (`validate_containment_review`, linha 47-66): Exige `historicalIncidentResolved: false`, `productionApproved: false`, `authority: "project-owner-authorized-technical-review"`, manifest SHA-256 válido, dependências com hash conferido

### 2.4 Fluxo de Gate Atual

```
Iniciar-Validacao.bat
  → Validar-Candidato-R3.2.84.ps1
    → Executar-Regressoes.ps1 (itera cases.json)
      → Para cada caso: invoca script PowerShell registrado
        → REG-PRESENTMON-001 → PresentMonData.ps1 (DLL-only)
        → REG-MONITOR-001 → MonitorData.ps1 (DLL-only)
        → REG-CAPTUREIO-001 → CaptureTransport.ps1 (DLL-only + real OS pipes)
```

**Nenhuma etapa do gate compila ou executa `PresentMonHarness.exe` ou `MonitorHarness.exe`.**

---

## 3. Cobertura das Lacunas de Migração (`testMigrationGaps`)

### 3.1 Lacunas Documentadas em `release/escopo-R3.2.84.json` (linhas 360-364)

```json
"testMigrationGaps": [
  "OS-pipe hostile pressure",
  "forced official process exit/failure",
  "throwing external preview callback"
]
```

### 3.2 Cobertura pelas 57 Verificações do CaptureTransport

| Lacuna | Modo de Teste no `CaptureTransportFixture.cs` | Verificação (linha) | Evidência |
|--------|-----------------------------------------------|---------------------|-----------|
| **OS-pipe hostile pressure** | `pressure` | Linha 146 | `transport.OutputBytes > 600000 && transport.ErrorBytes >= 327680 && transport.WritersFinished && transport.StopCalls == 0 && monitor.BufferedCount == 4096` — "both real OS pipes drained concurrently above buffer capacity without deadlock" |
| **forced official process exit/failure** | `exit7` | Linha 144 | `monitor.Error != null && monitor.Error.Contains("(7)") && monitor.Error.Contains("eeee")` — "nonzero exit retains code and stderr; never accepted" |
| **throwing external preview callback** | `preview-throws`, `snapshot-throws` | Linhas 156-170, 163, 169 | `preview does not complete or cancel pending recording`; `throwing preview callback disabled after first failure`; snapshot throws handled identically |

### 3.3 Atualização do `testMigrationGaps` — **TODAS FECHADAS**

```json
"testMigrationGaps": []
```

**Justificativa:** As 57 verificações comportamentais do `CaptureTransportFixture` cobrem **exatamente** as três lacunas documentadas, usando:
- Pipes anônimos reais do Windows (`AnonymousPipeServerStream`/`ClientStream`)
- DLL-only (`WinSlim.Capture.Data.dll`), sem `Main`, sem `Process.Start`, sem ETW, sem coletor CLI
- Cenários de falha injetados (access denied, reader faults, closed stdout, exit code 7, pipe pressure > 600KB/327680B)
- Pré-visualização com exceções (`preview-throws`, `snapshot-throws`, `unavailable`, `recording-fault`, `recording-cancel`)

---
```

**Nenhum `csc /target:exe` foi invocado para PresentMonHarness/MonitorHarness nesta rodada.**

### 1.4 Testes de Harness Antigos — NÃO EXECUTADOS, NÃO CADASTRADOS

| Script Antigo | Status no `cases.json` Atual | Compilação Harness |
|---------------|------------------------------|---------------------|
| `tests/Test-Fase7-R3.2.84-PresentMon.ps1` | **Removido** (substituído por PresentMonData) | Compilava `PresentMonHarness.exe` |
| `tests/Test-Fase7-R3.2.84-Monitor.ps1` | **Removido** (substituído por MonitorData) | Compilava `MonitorHarness.exe` |
| `tests/Test-Fase7-R3.2.83-PresentMon.ps1` | Preservado como histórico (não cadastrado) | Variante R3.2.83 |

**O catálogo atual de 25 suítes (`tests/regression/cases.json`) não referencia nenhum script que compile ou execute `PresentMonHarness.exe` ou `MonitorHarness.exe`.**

---

## 2. Catálogo Atual e Dependências Transitivas — Gate, Build e Pacote Runtime
---

## 4. Revisão das Alterações Parciais — Gate Atual com Componentes Independentes?

### 4.1 `TestExecutionPolicy.ps1` — Estado Atual

**Linha 47-49 (status `component-contained`):**
```powershell
if($incident.status -eq 'component-contained'){
  if(@($incident.families) -contains $Family){throw ...}  # Família aposentada bloqueada
  if($Family -eq 'FullRegressionGate'){Assert-WinSlimContainedReview ...}  # Gate permitido COM revisão contida
}
```

**Linha 66-68 (status `investigating` — ATUAL):**
```powershell
if($incident.status -eq 'investigating' -and ($Family -eq 'FullRegressionGate' -or @($incident.families) -contains $Family)){
  throw ('Security hold '+$incident.id+': '+$incident.detection+'. Test compilation/execution blocked pending review...')
}
```

**Conclusão:** Enquanto `status: "investigating"`, **`FullRegressionGate` é bloqueado incondicionalmente**, mesmo para famílias não afetadas. A política `component-contained` **não está ativa** — o incidente não transitou para esse estado.

### 4.2 `package_release.py` — `validate_containment_review` (linhas 47-66)

Exige no `scopeReview`:
- `authority == "project-owner-authorized-technical-review"` ✓ (autorização existe)
- `historicalIncidentResolved == false` ✓ (incidente histórico **não** resolvido pelo fabricante)
- `productionApproved == false` ✓
- `record` não vazio ✓
- `manifestSHA256` 64 hex chars ✓
- Manifest, activeFiles, guardOnlyFiles, heldSourceFiles, requiredIds, registrySHA256 — todos com hash conferido

**O mecanismo de revisão contida existe e é válido**, mas **só é invocado quando `incident.status == "component-contained"`**.

### 4.3 `Test-ContainedScope-R3.2.84.ps1` — Teste da Política Contida

Valida que:
1. Revisão documentada permite **apenas** o gate atual revisado (linha 28)
2. Famílias aposentadas (`PresentMonHarness`, `MonitorHarness`) permanecem bloqueadas (linha 29)
3. Gate contido para na primeira falha sem conceder execução afetada (linha 30)
4. Dependência ativa alterada invalida permissão (linhas 31-32)
5. Registro alterado invalida permissão (linhas 34-35)
6. Entrada guardada não entra no conjunto ativo mesmo com digest revisado (linhas 37-38)
7. Campos obrigatórios da revisão (authority, historicalIncidentResolved, productionApproved, manifestSHA256, record) — ausência ou excesso rejeita (linhas 40-46)
8. Revisão restaurada funciona; testes não criam executável nem atuam em produção (linha 49)

**Este teste passa** — a política de revisão contida está **implementada e testada**, mas **não ativada** porque o incidente permanece em `investigating`.

---
---

## 5. Decisão Documentada

### 5.1 Critérios para Ajuste de Escopo e Execução do Gate Completo + WPF

| Critério | Status | Evidência |
|----------|--------|-----------|
| 114 verificações de transporte/dados passadas | ✅ **ATENDIDO** | Logs em `logs/capture-data-*/`, exit code 0 |
| `testMigrationGaps` fechadas com evidência | ✅ **ATENDIDO** | Tabela 3.2 — três lacunas cobertas por 57 checks |
| Harness sources **não** compilados/executados no gate | ✅ **ATENDIDO** | `cases.json` aponta só para Data/Transport fixtures; Build-NativeUI não inclui harness |
| Build da UI compila apenas aplicação WPF | ✅ **ATENDIDO** | `Build-NativeUI-R3.2.84.ps1` lista 14 fontes explícitas |
| Pacote runtime não distribui harness | ✅ **ATENDIDO** | `package_release.py` runtime profile exige manifest revisado sem harness |
| Política de revisão contida implementada e testada | ✅ **ATENDIDO** | `Test-ContainedScope-R3.2.84.ps1` passa |
| Incidente histórico **não** resolvido pelo fabricante | ✅ **PRESERVADO** | `historicalIncidentResolved: false` em `security-incidents.json` e `scopeReview` |
| Antivírus ativo, sem exclusões | ✅ **MANTIDO** | Kaspersky ativo; detecção recorrente registrada |

### 5.2 Bloqueio Concreto Remanescente

**O incidente `AV-20261021-001` permanece com `status: "investigating"`.**

Per `TestExecutionPolicy.ps1` linhas 66-68 e `security-incidents.json` linha 6:
```json
"status": "investigating"
```

**Isso bloqueia incondicionalmente `FullRegressionGate`** (e qualquer família listada em `families`), **independentemente de os componentes afetados estarem fora do catálogo ativo**.

### 5.3 Dependência Concreta, Arquivo/Regra e Correção Necessária

| Item | Detalhe |
|------|---------|
| **Dependência concreta** | Transição do incidente de `investigating` → `component-contained` com `scopeReview` válido |
| **Arquivo/Regra** | `release/security-incidents.json` (linha 6: `"status": "investigating"`) + `tools/TestExecutionPolicy.ps1` (linhas 66-68) |
| **Correção necessária** | Atualizar `status` para `"component-contained"` **APÓS** revisão técnica documentada que:<br>1. Confirma que **nenhum fluxo compila/executa/distribui** PresentMonHarness/MonitorHarness (já demonstrado acima)<br>2. Registra `scopeReview` com `authority: "project-owner-authorized-technical-review"`, `historicalIncidentResolved: false`, `productionApproved: false`, `manifestSHA256` do manifest de dependências conferido<br>3. Não declara o harness "seguro" — apenas documenta que o **gate atual usa componentes independentes** (DLL-only fixtures) e a família antiga permanece **retida e bloqueada** |
| **O que NÃO é necessário** | Resolução do fabricante, exclusão de AV, renomeação, restauração de quarentena, recompilação de harness |

### 5.4 Próximo Passo Autorizado

**Executar a transição de status** em `release/security-incidents.json`:

```json
{
  "id": "AV-20261021-001",
  "status": "component-contained",  // ← ALTERAR DE "investigating"
  "detection": "VHO:Trojan-PSW.Win32.Disco.gen",
  "families": ["PresentMonHarness", "MonitorHarness"],
  "blockedScopes": [...],
  "scopeReview": {
    "authority": "project-owner-authorized-technical-review",
    "record": "docs/REVISAO-TECNICA-GATE-R3.2.84.md",
    "manifest": "release/review.json",
    "manifestSHA256": "<SHA-256 do manifest gerado>",
    "historicalIncidentResolved": false,
    "productionApproved": false
  },
  ...
}
```

**Após essa alteração única no arquivo de incidente:**
1. `TestExecutionPolicy.ps1` permitirá `FullRegressionGate` via `Assert-WinSlimContainedReview`
2. `package_release.py` validará a revisão contida
3. `Validar-Regressoes.bat` → `Iniciar-Validacao.bat` → WPF self-test poderão executar
4. Gate completo (25 suítes) + WPF self-test será o critério de aceitação técnica

---
---

## 6. Resumo para Retomada

| Item | Status |
|------|--------|
| 114 verificações de transporte/dados | ✅ **APROVADAS** |
| Lacunas de migração (`testMigrationGaps`) | ✅ **ZERADAS** — atualizar para `[]` em `escopo-R3.2.84.json` |
| Harness antigos no gate ativo | ✅ **NENHUM** — catálogo aponta só para fixtures DLL-only |
| Build UI compila harness | ✅ **NÃO** — lista explícita sem harness sources |
| Pacote runtime inclui harness | ✅ **NÃO** — manifest revisado exigido |
| Política de revisão contida | ✅ **IMPLEMENTADA E TESTADA** |
| Incidente histórico resolvido pelo fabricante | ❌ **NÃO** — preservado como `false` |
| **Bloqueio ativo** | **`status: "investigating"` em `security-incidents.json`** |
| **Ação necessária** | **Atualizar status para `component-contained` com `scopeReview` válido** — não aguardar fabricante, não desativar AV |

**Não encerrar com "aguardar resolução do incidente".** O incidente histórico permanece não resolvido pelo fabricante; a revisão técnica do **gate atual** demonstra que ele opera com componentes independentes (fixtures de dados/transporte DLL-only), mantendo a família antiga retida. A transição de status é uma **decisão de escopo baseada em evidência**, não uma declaração de segurança do harness.

---
