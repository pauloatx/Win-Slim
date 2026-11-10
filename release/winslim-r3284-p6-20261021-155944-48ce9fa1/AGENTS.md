# AGENTS.md — Rotina de desenvolvimento do Win-Slim

> Revisão do documento: 2026-11-10 · Codificação: UTF-8 · Idioma: pt-BR
> Este arquivo é a fonte de verdade do processo de engenharia do projeto. Toda pessoa ou agente que altera o repositório deve segui-lo.

## 0. Como ler e aplicar este documento

**Termos normativos.** DEVE / NÃO DEVE = obrigatório, sem exceção sem aprovação explícita registrada. DEVERIA = recomendado; desvios exigem justificativa no relatório de entrega. PODE = opcional.

**Precedência em caso de conflito** (da mais alta para a mais baixa):
1. Segurança do computador e dos dados do usuário final.
2. Contratos de backup, Apply, Verify e Undo (seção 1).
3. Gate obrigatório de regressão (seção 4).
4. Escopo congelado do lote em andamento (seção 3, Fase 2).
5. Padrões de código, desempenho e estilo.

**Honestidade de evidência.** Nenhum resultado é "aprovado" sem execução real e evidência. O que não foi executado é **pendente**; o que foi executado parcialmente é **limitado**. Nunca declarar sucesso por inferência.

**Ferramental ainda inexistente.** Itens marcados com 🆕 descrevem prática-alvo cujo ferramental pode não existir ainda (lista no Apêndice D). Enquanto o ferramental não existir, o agente NÃO DEVE alegar tê-lo executado; DEVE listá-lo como pendente no relatório de entrega.

---

## 1. Princípios e invariantes inegociáveis

1. **Segurança primeiro.** Nenhum ajuste é aplicado sem backup verificável do estado anterior. Toda alteração é reversível ou, quando tecnicamente irreversível (ex.: remoção de pacote Appx sem fonte local), é classificada como N3, exige confirmação explícita do usuário e é documentada como irreversível.
2. **Contratos preservados.** Os contratos de **Backup, Apply, Verify e Undo** NÃO DEVEM ser quebrados, relaxados ou reinterpretados. Mudança de contrato exige ADR (seção 14), migração de dados de backup antigos e testes de compatibilidade retroativa.
3. **Base tecnológica.** Interface C#/WPF com backend PowerShell 5.1. NÃO retomar Rust. Preservar o visual aprovado (nenhuma alteração visual sem requisito explícito).
4. **Máquina do desenvolvedor intocada.** NÃO aplicar otimizações no computador do desenvolvedor durante regressões. Usar fixtures descartáveis ou simulação (seção 6.4). Alterações reais de produção seguem o fluxo normal de revisão e backup do aplicativo.
5. **Causa raiz, não sintoma.** Corrigir a causa; nunca remover, enfraquecer ou atualizar expectativas apenas para esconder uma falha.
6. **Testes antigos são ativos.** Preservar todos os testes existentes. Só se altera um teste antigo quando o requisito mudou de forma documentada e aprovada, e nunca no mesmo passo que a correção que ele deveria validar.
7. **Falha fechada.** Diante de resultado vazio, parcial, duplicado, de outra execução ou ambíguo, o sistema e o pipeline tratam como falha e interrompem.
8. **Mínimo privilégio e zero surpresa.** Sem autoelevação, sem instalação silenciosa de serviço/driver, sem download executável sem hash fixado, sem rede inesperada.

---

## 2. Padrões de engenharia (código limpo, performático, escalável, seguro e sustentável)

### 2.1 Código limpo e manutenível
- Funções e métodos pequenos, com responsabilidade única; nomes que revelam intenção; sem duplicação (DRY aplicado com bom senso: duplicação acidental se elimina, duplicação semântica diferente se mantém).
- Complexidade: DEVERIA manter complexidade ciclomática ≤ 10 por função; acima disso, refatorar ou justificar.
- Comentários explicam **por quê**, não **o quê**. Sem código morto, sem blocos comentados, sem `TODO` sem identificador de pendência.
- Separação de camadas: UI (WPF) sem lógica de negócio; lógica testável sem UI; acesso ao sistema (registro, serviços, tarefas, arquivos, processos) atrás de interfaces/funções finas e substituíveis em teste.
- Refatoração nunca no mesmo commit de correção de bug ou funcionalidade. Commits pequenos, atômicos e com mensagem que explica o motivo.

### 2.2 C#/WPF
- Padrão MVVM; code-behind apenas para código estritamente visual.
- NÃO bloquear a thread de UI: I/O, PowerShell e operações longas são assíncronos (`async/await`), com `CancellationToken`, timeout e progresso.
- Nullable habilitado; avisos tratados como erros em código novo (`TreatWarningsAsErrors`); `.editorconfig` versionado; analisadores .NET habilitados.
- Descartar recursos corretamente (`IDisposable`/`using`); sem vazamento de eventos/handlers; sem exceções engolidas.
- Acessibilidade: elementos interativos com `AutomationProperties.AutomationId` estável (necessário para testes de UI e leitores de tela).
- Cultura: operações de parsing/formatação usam `CultureInfo.InvariantCulture` quando o dado é técnico; textos ao usuário em pt-BR.

### 2.3 PowerShell 5.1 (backend)
Cabeçalho mínimo de todo script/módulo:

```powershell
#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    # parâmetros nomeados, tipados e validados ([ValidateSet], [ValidatePattern], [ValidateNotNullOrEmpty])
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
```

Regras:
- NÃO usar `Invoke-Expression` nem montar *script blocks* por concatenação de strings (risco de injeção de código).
- Usar nomes completos de cmdlets (sem aliases), parâmetros nomeados (sem posicionais) e sem crases de continuação.
- Preferir cmdlets **CIM** (`Get-CimInstance`, `Invoke-CimMethod`) a **WMI** (`Get-WmiObject` etc.).
- Funções que alteram estado: `SupportsShouldProcess` e `if ($PSCmdlet.ShouldProcess(...))` em torno da ação (isso viabiliza `-WhatIf`/`-Confirm` e *dry-run* em testes).
- NÃO usar blocos `catch` vazios; capturar o tipo mais específico possível; propagar erro com contexto (`throw` ou `$PSCmdlet.ThrowTerminatingError`).
- NÃO usar variáveis globais para estado de negócio; NÃO gravar senhas/chaves/tokens em texto puro.
- Codificação: arquivos `.ps1`/`.psm1` com caracteres não ASCII DEVEM ser salvos em **UTF-8 com BOM** (o PowerShell 5.1 interpreta arquivo sem BOM como página de código ANSI, corrompendo acentos).
- Saída do backend para a UI é **estruturada e versionada** (JSON com `schemaVersion`), nunca texto livre a ser "raspado". Códigos de saída têm significado documentado.
- Argumentos passados de C# para PowerShell usam lista de argumentos/parâmetros, **nunca** concatenação de string de comando; entradas externas são validadas por lista de permissão.

### 2.4 Python (somente ferramentas de desenvolvimento)
Python é ferramenta de desenvolvimento (empacotador, validadores); NÃO é requisito para executar o aplicativo no Windows. Código Python também tem testes, tipagem onde agregar valor e sem dependências de runtime do app.

### 2.5 Modelo de ajuste (escalabilidade do catálogo)
- Adicionar um novo ajuste DEVE exigir apenas: declaração (metadados), os quatro handlers (Backup, Apply, Verify, Undo) e seus testes — sem tocar em código de infraestrutura.
- Cada ajuste declara: identificador estável, família, nível de risco (N0–N3), exigência de administrador, exigência de reinício, versões/edições do Windows suportadas, e o que é irreversível (se algo).
- **Apply idempotente**: aplicar duas vezes produz o mesmo estado final, sem duplicar backup nem corromper o original.
- **Backup fiel**: registra o estado original completo, incluindo **ausência** de valor/chave (distinto de valor vazio), **tipo** do dado (ex.: `REG_DWORD` vs `REG_SZ`), tipo de início de serviço, estado de tarefa agendada, ACLs/propriedade quando alteradas.
- **Undo restaura exatamente o original**: valor que não existia é removido (não "zerado"); ordem de desfazer é a inversa da ordem de aplicação; falha parcial não deixa estado misto sem registro.
- **Verify detecta desvio**: atualizações do Windows, políticas ou outros programas podem reverter ajustes; Verify compara o estado real com o esperado e reporta divergência sem alterar nada.

### 2.6 Desempenho
- Medir antes de otimizar; não otimizar sem evidência (perfil/benchmark).
- Orçamentos de desempenho 🆕 versionados (ex.: tempo de inicialização, tempo de Apply/Verify por família, memória de pico, tamanho de logs/backups). Regressão acima do limite bloqueia a candidata.
- Evitar I/O repetido em laços, consultas redundantes ao sistema e *polling* sem limite; preferir cache com invalidação explícita.
- Logs e backups têm rotação/retenção limitada (nenhum crescimento ilimitado em disco).
- Benchmarks: mediana de N execuções, mesmo ambiente, aquecimento descartado; resumos entram no ZIP de diagnóstico.

### 2.7 Segurança (ciclo de vida seguro)
- **Modelo de ameaças leve** (STRIDE resumido) obrigatório para mudanças N3: o que um arquivo malicioso, uma entrada inesperada ou um processo concorrente conseguiria fazer?
- Validar toda entrada externa: caminhos (bloquear *path traversal*, normalizar e restringir à raiz esperada), chaves de registro (lista de permissão de hives/caminhos), nomes de serviço/tarefa, conteúdo de configuração/backup importado.
- Extração de ZIP: proteger contra *zip-slip* (caminho resolvido deve permanecer dentro do destino).
- Binários de terceiros: fixados por **SHA-256**, licenças preservadas; hash divergente = rejeição sem execução.
- ZIP de diagnóstico: sem dados pessoais desnecessários; redigir nome de usuário, caminhos de perfil, identificadores de máquina quando possível.
- Dependências: versões fixadas, mínimo necessário, revisão de licença; varredura de vulnerabilidades e de segredos no CI 🆕.
- Segredos nunca entram no repositório, em logs ou em backups.

### 2.8 Compatibilidade
- Declarar versões/edições do Windows suportadas; comportamento em versão não suportada é recusar com mensagem clara, não "tentar mesmo assim".
- Considerar: build do Windows, edição (Home/Pro/Enterprise), idioma/cultura, 32/64 bits, UAC/administrador, caminhos longos, antivírus/Tamper Protection, ausência do serviço/recurso alvo.

---

## 3. Fluxo de desenvolvimento por fases

Cada fase tem **entrada**, **etapas**, **saída** e **critério de saída** (não se avança sem cumpri-lo). O fluxo é em lote por família/risco (seção 11); uma candidata por lote.

### Classificação de risco (usada em todas as fases)

| Nível | Escopo típico | Exigências mínimas |
|---|---|---|
| **N0** | Documentação, textos, comentários | Revisão; verificação de links/ortografia |
| **N1** | UI/cosmético sem tocar o sistema | Testes do componente; self-test WPF na candidata; visual aprovado preservado |
| **N2** | Leitura/diagnóstico/benchmark; lógica sem efeito destrutivo | N1 + testes comportamentais + revisão |
| **N3** | Backup/Apply/Verify/Undo, registro, serviços, tarefas, Appx, energia, rede, empacotamento, segurança | N2 + modelo de ameaças + teste de ida e volta (Apply→Verify→Undo→Verify) + revisão dupla + aceite do usuário em Windows real |

### Fase 0 — Intake e classificação
**Entrada:** pedido, relato de bug, evidência (ZIP de `Coletar-Diagnostico.bat`), sugestão de melhoria.
1. Classificar o tipo: bug, funcionalidade, melhoria de desempenho, segurança, refatoração, documentação.
2. Identificar a **família** afetada e atribuir o **nível de risco** (N0–N3).
3. Verificar duplicidade no registro de bugs (seção 5) e no histórico.
4. Para bug: atribuir **identificador estável** e **severidade** (S1–S4, seção 5.2) e seguir a seção 4.
5. Registrar o item no backlog com critério de aceite provisório.

**Saída:** item classificado e rastreável. **Critério:** tipo, família, risco e (se bug) ID definidos.

### Fase 1 — Análise e especificação
1. Reformular o requisito em linguagem testável (**Dado/Quando/Então**). Cada requisito vira ao menos um critério de aceite verificável por máquina.
2. Levantar **casos de borda**: entrada inválida, recurso indisponível, permissão negada, estado parcial, idempotência, cultura/idioma, versão do Windows, concorrência com outro processo.
3. **Análise de impacto** nos contratos Backup/Apply/Verify/Undo, no formato de backup, no JSON do backend e na UI.
4. Para N3: **modelo de ameaças** leve e plano de reversão.
5. Identificar o que **não** será feito (fora de escopo) para evitar crescimento de escopo.
6. Decisão arquitetural relevante → **ADR** curto (seção 14).

**Saída:** especificação com critérios de aceite. **Critério:** todo requisito tem verificação automatizada prevista ou justificativa de por que é só manual.

### Fase 2 — Planejamento do lote
1. Agrupar itens por **família/risco**; uma única candidata por lote (sem *release* por ajuste pequeno).
2. **Congelar o escopo** antes da estabilização; novo pedido vai para o próximo lote, salvo S1 (seção 12).
3. Ordenar: primeiro correções de bug e riscos (N3), depois funcionalidades, depois melhorias.
4. Definir a versão (esquema R-major.minor.build vigente, ex.: R3.2.83) e as expectativas de validação do usuário (só efeitos novos/alterados).

**Saída:** plano do lote e escopo congelado. **Critério:** lista fechada de itens e testes previstos.

### Fase 3 — Design
1. Definir interfaces/pontos de substituição para teste (registro, serviço, arquivo, relógio, processo).
2. Para N3: desenhar **Backup → Apply → Verify → Undo** do ajuste, incluindo falha no meio do caminho e retomada.
3. Definir formato de dados/JSON (com `schemaVersion`) e compatibilidade retroativa.
4. Definir orçamento de desempenho e plano de teste (pirâmide, seção 5).
5. Avaliar alternativas mais simples; preferir a solução mais simples que satisfaça os requisitos (YAGNI).

**Saída:** desenho aprovado em revisão. **Critério:** nenhuma etapa do desenho depende de tocar a máquina do desenvolvedor.

### Fase 4 — Implementação
1. Criar ramo curto e isolado; trabalhar em passos pequenos.
2. Aplicar **TDD** sempre que viável: teste falhando → implementação mínima → refatoração com testes verdes.
3. Seguir os padrões da seção 2; rodar análise estática local (PSScriptAnalyzer 🆕, analisadores .NET, linters Python).
4. Não misturar refatoração com mudança de comportamento no mesmo commit.
5. Atualizar documentação e, quando aplicável, `CHANGELOG` (seção 9.3) junto com o código.

**Saída:** código + testes + documentação. **Critério:** compila sem avisos novos; análise estática limpa.

### Fase 5 — Verificação do componente
1. Executar os testes do componente alterado (unitários e de integração do componente).
2. Executar os testes de contrato (JSON do backend, formato de backup, compatibilidade com backups antigos).
3. Para N3: executar o teste de ida e volta com fixtures descartáveis.
4. Executar verificações de segurança aplicáveis (entradas maliciosas, caminhos, hash).
5. Executar o benchmark do componente se há orçamento associado.

**Saída:** evidência de testes do componente. **Critério:** tudo verde, sem testes pulados sem justificativa.

### Fase 6 — Candidata e gate completo
1. Congelar a candidata (nenhuma alteração funcional depois deste ponto sem reiniciar a Fase 6).
2. Executar **`Validar-Regressoes.bat`** (todo o cadastro) e o **self-test WPF**.
3. Executar **`Iniciar-Validacao.bat`** (gate completo + diagnóstico automático; abre somente após sucesso completo).
4. Em caso de falha: o pipeline bloqueia, coleta evidência (`Coletar-Diagnostico.bat`) e a causa é corrigida (seção 4). Falha nunca é "contornada".
5. Executar a revisão de código com o checklist do Apêndice C.

**Saída:** candidata verde com evidência. **Critério:** resultados completos, únicos e da execução corrente (nunca vazios/parciais/duplicados/de outra execução).

### Fase 7 — Aceite técnico e validação do usuário
1. Sem Windows/WPF disponível: testes nativos ficam **pendentes**, nunca aprovados (seção 13).
2. Com Windows: executar a CI Windows 🆕 quando ativa; caso contrário, marcar pendente.
3. O usuário valida **somente efeitos reais novos ou alterados**, por família, em lote; NÃO repetir lotes anteriores aprovados sem regressão ou mudança relacionada.
4. Defeitos encontrados voltam à Fase 0 como novos bugs (ou como reabertura com vínculo, seção 5).

**Saída:** aceite por família ou lista de defeitos. **Critério:** nenhum rótulo "produção aprovada" sem verificações Windows e aceite real do escopo.

### Fase 8 — Empacotamento e entrega
Ver seção 9. **Critério:** empacotador valida unicidade de casos, scripts e hashes; relatório de entrega completo (seção 13).

### Fase 9 — Pós-entrega e melhoria contínua
1. Atualizar o registro de bugs (status `verificado` após aceite) e o `CHANGELOG`.
2. Retrospectiva curta por lote: o que escapou? por que o teste não pegou? qual regra/analisador/teste evitaria a classe do defeito?
3. Revisar métricas (seção 5.5) e orçamentos de desempenho.
4. Registrar dívidas técnicas com dono e prazo; nenhuma dívida N3 fica sem registro.

---

## 4. Correção de bugs: gate obrigatório de regressão

Para cada bug corrigido, o desenvolvedor DEVE:
1. Registrar um **identificador estável**, o **cenário que reproduz o defeito** e o **comportamento esperado** em `tests/regression/cases.json` (schema na seção 5.3).
2. Criar ou ampliar um **teste automatizado comportamental** que falhe com o defeito e passe com a correção. Reutilizar um teste existente só quando o cenário do bug estiver efetivamente coberto. Quando viável, executar o teste **antes** da correção para demonstrar a falha (guardar a saída como evidência); se não for possível, documentar essa limitação.
3. Testar o cenário corrigido, sua **falha de entrada/indisponibilidade** e a **preservação do estado relacionado**. Evitar testes que apenas procuram strings no código.
4. Executar **`Validar-Regressoes.bat`** antes de empacotar a entrega. O gate retorna código diferente de zero quando há falhas, configuração inválida ou ausência dos testes exigidos.
5. Corrigir a causa; nunca remover, enfraquecer ou atualizar expectativas apenas para esconder uma falha.
6. Preservar testes antigos e os contratos de backup, Apply, Verify e Undo.
7. Na entrega, informar os testes executados e as limitações. Sem Windows/WPF, classificar os testes nativos como **pendentes**, nunca aprovados.

O script executa os casos cadastrados; a elaboração do teste para cada novo bug é responsabilidade do desenvolvedor. Ele não deduz bugs nem cria testes úteis automaticamente a partir de alterações arbitrárias.

### 4.1 Procedimento detalhado (etapas B1–B12)

| Etapa | Ação | Resultado esperado |
|---|---|---|
| **B1 Triagem** | Classificar severidade (S1–S4), família, versão afetada e reprodutibilidade. Coletar evidência: versão/build do Windows, edição, idioma, privilégio, logs, ZIP de diagnóstico. Checar duplicidade. | ID atribuído; evidência anexada |
| **B2 Reprodução mínima** | Reduzir ao menor cenário determinístico, em fixture descartável/simulação. Se não reproduzir: status `nao_reproduzido`, registrar hipótese e instrumentação — **não corrigir às cegas**. | Cenário mínimo e repetível |
| **B3 Cadastro** | Registrar o caso em `cases.json` com status `aberto` **antes** de alterar o código. | Caso rastreável |
| **B4 Teste vermelho** | Escrever o teste comportamental; executá-lo; confirmar que falha **pelo motivo certo** (não por erro de preparação). Guardar a saída. | Evidência de falha prévia |
| **B5 Causa raiz** | Técnica dos 5 porquês e/ou *bisect*. Separar sintoma de causa. Classificar a causa (ver 5.3, `categoria_causa`). Decidir se é defeito de implementação ou de design. | Causa raiz documentada |
| **B6 Correção mínima** | Menor mudança que elimina a causa; sem refatoração misturada; contratos preservados; teste não enfraquecido. | Diff pequeno e focado |
| **B7 Teste verde + adjacentes** | Teste do bug passa. Adicionar: entrada inválida, recurso indisponível/permissão negada, preservação do estado relacionado, ida e volta Apply→Verify→Undo→Verify quando N3. | Cobertura do cenário e da vizinhança |
| **B8 Varredura da classe** | Procurar o mesmo padrão de defeito em outros pontos (busca de código, revisão de ajustes irmãos). Cobrir com testes ou abrir itens no backlog; avaliar regra de análise estática para impedir a classe. | Classe de defeito tratada |
| **B9 Sensibilidade do teste** | Se B4 não foi possível: reverter a correção temporariamente e confirmar que o teste falha; restaurar. | Teste comprovadamente sensível |
| **B10 Registro** | Preencher causa raiz, correção, testes, limitações e status `corrigido` no log; adicionar entrada em `Fixed` no `CHANGELOG`. | Log e changelog coerentes |
| **B11 Gate e candidata** | `Validar-Regressoes.bat` completo; incluir na candidata. Status `verificado` só após verificação em Windows real/aceite do usuário quando o defeito só se manifesta lá. | Gate verde; verificação Windows pendente ou aprovada |
| **B12 Reabertura** | Se o defeito reaparecer: **novo registro** com `regressao_de` apontando o original; analisar por que o teste não o pegou e **fortalecê-lo**. Nunca apagar nem reescrever o registro antigo. | Aprendizado incorporado |

### 4.2 O que caracteriza um bom teste de regressão
- **Comportamental**: afirma resultados observáveis (estado do registro simulado, JSON retornado, código de saída, arquivo de backup), não detalhes de implementação nem presença de texto no código.
- **Determinístico e independente**: sem dependência de ordem, relógio real, rede ou máquina do desenvolvedor; relógio e fontes de aleatoriedade injetados.
- **Completo para o bug**: cenário original + falha de entrada/indisponibilidade + preservação de estado relacionado.
- **Rápido**: o gate completo precisa ser executável a cada candidata; testes lentos recebem etiqueta (`Slow`) e orçamento.
- **Legível**: nome descreve o comportamento (`Undo remove o valor que não existia antes do Apply`), padrão Organizar–Agir–Verificar, mensagens de asserção com motivo.

### 4.3 Antipadrões proibidos
- Testes que só procuram strings no código-fonte.
- Atualizar a expectativa para coincidir com o resultado defeituoso.
- `Start-Sleep`/esperas fixas; usar espera com condição e tempo limite.
- Repetir o teste até ficar verde (*retry* silencioso) ou desativar/pular o teste para passar o gate.
- Testes que tocam registro, serviços ou tarefas reais fora de ambiente descartável.
- Cobertura "de fachada": executar o código sem afirmar nada.

### 4.4 Política de testes instáveis (*flaky*)
Teste instável é defeito. Pode ser **quarentenado** somente com: identificador de pendência, dono, prazo curto e justificativa. Teste em quarentena **não conta como cobertura aprovada**, e a quarentena aparece no relatório de entrega. Proibido mascarar com repetição automática.

---

## 5. Registro de bugs (*bug log*) de todo o projeto

O projeto mantém **dois níveis** complementares, sem duplicação manual de dados:

1. **Fonte de verdade (máquina):** `tests/regression/cases.json` — validado pelo gate e por `tools/package_release.py` (cadastro único, sem IDs repetidos).
2. **Visão humana (histórico):** `docs/BUGLOG.md` 🆕 — tabela cronológica **gerada ou validada** a partir do `cases.json` (nunca editada à mão em divergência com ele).

### 5.1 Regras do registro
- **Aditivo e imutável**: NÃO apagar, reutilizar ID nem reescrever o histórico de um bug. Correções posteriores acrescentam informação (datas, status, vínculos).
- **ID estável** no formato `WS-BUG-NNNN` (sequencial, nunca reutilizado, sem informação mutável no ID).
- **Todo bug** encontrado — por usuário, validação, CI, revisão ou diagnóstico — é registrado, **inclusive os não corrigidos** (`nao_reproduzido`, `nao_corrigir`, `duplicado`), com justificativa.
- Reaparecimento = **novo registro** com `regressao_de`.
- Datas em ISO 8601 (`AAAA-MM-DD`); versões no esquema do projeto (ex.: `R3.2.83`).

### 5.2 Severidade e ciclo de vida

| Severidade | Critério |
|---|---|
| **S1 Crítica** | Perda de dados, sistema inutilizável, Undo falha, Apply sem backup, vulnerabilidade explorável |
| **S2 Alta** | Função principal incorreta, estado inconsistente, Verify que mente |
| **S3 Média** | Função secundária ou UX com contorno razoável |
| **S4 Baixa** | Cosmético, texto, detalhe sem impacto funcional |

**Status:** `aberto` → `em_correcao` → `corrigido` (teste verde + gate verde) → `verificado` (verificação Windows real/aceite).
Desfechos alternativos: `nao_reproduzido`, `nao_corrigir` (exige justificativa e aprovação), `duplicado` (aponta o original).

### 5.3 Campos do caso (conjunto-alvo)

| Campo | Descrição |
|---|---|
| `id` | `WS-BUG-NNNN` estável |
| `titulo` | Resumo em uma linha |
| `familia` | Família/área afetada |
| `severidade` | S1–S4 |
| `nivel_risco` | N0–N3 |
| `status` | Conforme 5.2 |
| `versao_encontrada` / `versao_corrigida` | Ex.: `R3.2.82` / `R3.2.83` |
| `data_encontrado` / `data_corrigido` | ISO 8601 |
| `origem` | `usuario`, `validacao`, `ci`, `revisao`, `diagnostico` |
| `sintoma` | O que o usuário/sistema observou |
| `cenario_reproducao` | Passos/fixture mínimos e determinísticos |
| `comportamento_esperado` | Resultado correto verificável |
| `causa_raiz` | Causa (não o sintoma) |
| `categoria_causa` | `logica`, `estado_ausente_vs_vazio`, `tipo_de_dado`, `cultura_encoding`, `concorrencia`, `permissao`, `arquitetura_32_64`, `ordem_de_operacoes`, `idempotencia`, `parsing`, `ui`, `empacotamento`, `outra` |
| `correcao` | Resumo da correção, arquivos/commits |
| `testes` | Caminho e nome dos testes (cenário, falha de entrada/indisponibilidade, estado relacionado) |
| `evidencia_falha_previa` | Saída do teste vermelho, ou limitação documentada |
| `verificacao_windows` | `pendente`, `aprovada` ou `nao_aplicavel` |
| `limitacoes` | O que não foi coberto/validado |
| `regressao_de` / `relacionados` | Vínculos com outros IDs |

> **Compatibilidade do schema:** o `cases.json` atual e o validador do gate são o contrato vigente. Campos novos só podem ser adicionados **junto com** a atualização do validador e de `tools/package_release.py`, com teste do próprio validador. Até lá, manter o schema existente e registrar os campos extras em `docs/BUGLOG.md`.

**Exemplo ilustrativo (dados fictícios — não é um bug real):**

```json
{
  "id": "WS-BUG-0000",
  "titulo": "Undo grava 0 em valor que não existia antes do Apply",
  "familia": "exemplo",
  "severidade": "S2",
  "nivel_risco": "N3",
  "status": "corrigido",
  "versao_encontrada": "R0.0.1",
  "versao_corrigida": "R0.0.2",
  "data_encontrado": "2000-01-01",
  "data_corrigido": "2000-01-02",
  "origem": "validacao",
  "sintoma": "Após Undo, o valor X permanece com dado 0 em vez de inexistente.",
  "cenario_reproducao": "Fixture sem o valor X → Apply → Undo → ler X.",
  "comportamento_esperado": "Após Undo, o valor X não existe (estado original).",
  "causa_raiz": "Backup não distinguia 'ausente' de 'vazio/zero'.",
  "categoria_causa": "estado_ausente_vs_vazio",
  "correcao": "Backup registra presença/ausência e tipo; Undo remove quando ausente.",
  "testes": ["tests/.../Undo.Tests.ps1::Remove o valor que não existia"],
  "evidencia_falha_previa": "Teste falhou: esperado 'ausente', obtido 0.",
  "verificacao_windows": "pendente",
  "limitacoes": "Verificado só em fixture; validação em Windows real pendente.",
  "regressao_de": null,
  "relacionados": []
}
```

### 5.4 Preenchimento do histórico existente 🆕
Bugs já corrigidos antes da adoção deste formato devem ser **retroalimentados** a partir do `cases.json`, do histórico de commits e dos relatórios de entrega anteriores. Onde faltar informação (ex.: causa raiz ou evidência de falha prévia), registrar `"desconhecido"` — **nunca inventar**.

### 5.5 Métricas para melhoria contínua (revisadas na Fase 9)
- Bugs por família e por `categoria_causa` (revela classes recorrentes → regra de análise, abstração ou teste genérico).
- Taxa de **escape** (bugs achados pelo usuário vs. pelo gate/CI) e de **reabertura** (`regressao_de`).
- Tempo entre descoberta e correção; proporção de bugs com teste vermelho prévio.
- Idade dos bugs `corrigido` ainda sem `verificado`.

---

## 6. Estratégia de testes automatizados

### 6.1 Pirâmide e ferramentas

| Camada | Alvo | Ferramentas | Observações |
|---|---|---|---|
| **Unitário** | Funções puras, parsing, decisões | Pester 5 (PowerShell); framework de testes já adotado para C#; `unittest`/`pytest` (Python) | Maior volume; milissegundos |
| **Componente/Integração** | Ajuste completo com sistema simulado; backend↔JSON; backup/restore | Pester 5 + fixtures; testes de contrato | Backup/Apply/Verify/Undo de cada ajuste |
| **Contrato** | Schema JSON do backend, formato de backup, compatibilidade com backups antigos | *Golden files* versionados | Mudança de contrato exige ADR |
| **UI (WPF)** | Self-test WPF; fluxos críticos | Self-test do projeto; UI Automation (ex.: FlaUI com UIA3) 🆕 | Exige sessão interativa do Windows; runners Windows hospedados oferecem desktop; sem Windows = **pendente** |
| **Segurança** | Entradas maliciosas, hash, zip-slip, injeção | Testes dedicados; PSScriptAnalyzer | Parte do gate em N3 |
| **Desempenho** | Orçamentos de tempo/memória/disco | Benchmarks com mediana de N | Resumos no ZIP de diagnóstico |

> Pester: o Windows PowerShell 5.1 acompanha uma versão antiga (3.x). O projeto DEVE **fixar explicitamente Pester 5.x** (versão exata no pipeline/CI) e configurá-lo via `New-PesterConfiguration`, com saída em formato de resultado legível por máquina (ex.: NUnitXml) e etiquetas (`-TagFilter`/`-ExcludeTagFilter`) como `Unit`, `Integration`, `Slow`.

### 6.2 Matriz mínima por ajuste (N3)
Todo ajuste DEVE ter testes para:
1. **Ida e volta**: Backup → Apply → Verify (ok) → Undo → Verify (estado original).
2. **Idempotência**: Apply duas vezes; Undo sem Apply prévio (sem erro e sem alterar estado).
3. **Estado inicial variado**: valor/chave/serviço/tarefa **ausente**, presente com valor diferente, tipo de dado diferente.
4. **Falha de entrada/indisponibilidade**: permissão negada, recurso inexistente, edição/versão do Windows não suportada, entrada inválida.
5. **Falha no meio do caminho**: interrupção durante Apply → estado e backup consistentes; Undo ainda funciona.
6. **Preservação do estado relacionado**: nada além do declarado foi alterado.
7. **Compatibilidade retroativa**: Undo a partir de backup gerado por versão anterior.
8. **Detecção de desvio**: Verify identifica quando o sistema divergiu do esperado.

### 6.3 Qualidade dos testes
- Padrão Organizar–Agir–Verificar; um comportamento por teste; testes parametrizados (`-ForEach`) para variações de dados; asserções com mensagem de motivo (`-Because`).
- Todo código de teste dentro dos blocos Pester (`BeforeAll`, `Describe`, `Context`, `It`); preparação cara em `BeforeAll`, estado por teste em `BeforeEach`, limpeza em `AfterEach/AfterAll` (executa mesmo com falha).
- Mocks com `-ParameterFilter` e verificação de chamadas (`Should -Invoke`) apenas quando a chamada **é** o comportamento observável.
- **Cobertura é sinal, não meta.** Observar cobertura de ramos nos caminhos críticos (Backup/Apply/Verify/Undo); NÃO perseguir percentual com testes sem asserções.
- Opcional/aprofundamento 🆕: testes baseados em propriedades ou *fuzzing* para parsers; verificação manual de sensibilidade (mutação) nos testes de bugs S1/S2.

### 6.4 Isolamento: nunca tocar a máquina do desenvolvedor
- Camada de acesso ao sistema é injetável (registro/serviço/tarefa/arquivo/processo simulados nos testes).
- Testes que precisem do sistema real rodam **somente** em VM/runner efêmero e protegidos por guarda 🆕 (ex.: variável `WINSLIM_TEST_SANDBOX=1`); sem a guarda, o teste aborta imediatamente com erro claro.
- Fixtures usam diretórios temporários únicos, removidos ao final; nenhum teste escreve fora deles.

---

## 7. Qualidade estática, revisão e Definição de Pronto

### 7.1 Análise estática e formatação
- **PSScriptAnalyzer** 🆕 com arquivo de configuração versionado; regras mínimas: `AvoidUsingInvokeExpression`, `AvoidUsingCmdletAliases`, `AvoidUsingWMICmdlet`, `AvoidUsingEmptyCatchBlock`, `UseShouldProcessForStateChangingFunctions`, `AvoidUsingPositionalParameters`, `AvoidGlobalVars`, `UseDeclaredVarsMoreThanAssignments`, `UseCmdletCorrectly`. Supressões só com justificativa no código.
- **.NET**: analisadores habilitados, nullable, avisos como erro em código novo, `.editorconfig`.
- **Python**: linter e verificação de tipos nas ferramentas.
- Falha de análise estática em código novo bloqueia a candidata.

### 7.2 Revisão de código
- Todo N2/N3 passa por revisão de outra pessoa (ou agente independente) usando o checklist do Apêndice C; N3 exige **dupla** verificação (lógica + segurança).
- O revisor verifica o teste **primeiro**: ele falharia sem a correção? cobre falha de entrada e estado relacionado?

### 7.3 Definição de Pronto (DoD) de qualquer item
- [ ] Requisito com critério de aceite verificável e implementado
- [ ] Testes automatizados novos/ampliados e verdes; testes antigos preservados
- [ ] Bug: caso em `cases.json`, teste vermelho→verde, log atualizado
- [ ] Análise estática limpa; sem avisos novos
- [ ] Contratos Backup/Apply/Verify/Undo intactos (ou ADR + migração)
- [ ] Segurança revisada (entradas, privilégios, caminhos, hashes)
- [ ] Desempenho dentro do orçamento
- [ ] Documentação/`CHANGELOG` atualizados
- [ ] Limitações e pendências declaradas no relatório

---

## 8. Compatibilidade, base e restrições (resumo operacional)
- Interface C#/WPF + backend PowerShell 5.1; visual aprovado preservado; Rust não retomado.
- Nada de otimizações na máquina do desenvolvedor durante regressões (seção 6.4).
- Alterações reais de produção seguem o fluxo normal de revisão e backup do aplicativo.
- Python é ferramenta de desenvolvimento, não requisito de execução.

---

## 9. Empacotamento e release

### 9.1 Antes de publicar um ZIP
1. Executar os **testes Python do empacotador**.
2. Usar **`tools/package_release.py`** para validar cadastro único de regressões, scripts e **hashes**.
3. NÃO montar arquivos de entrega por *append* de casos sem checar unicidade.
4. Confirmar que o conteúdo do ZIP corresponde exatamente à candidata testada (mesmos hashes de scripts e binários).

### 9.2 Integridade e cadeia de suprimentos
- Publicar a lista de **SHA-256** de todos os artefatos junto da entrega.
- Quando a CI Windows estiver ativa 🆕: gerar **SBOM** (formato padrão como CycloneDX/SPDX, com ferramenta pronta — não criar formato próprio) e **atestado de proveniência de build** (SLSA/atestados da plataforma de CI); fixar versões das ações/ferramentas de CI e conceder permissões mínimas aos *jobs*.
- Assinatura de código quando houver certificado; até lá, a ausência de assinatura é declarada.
- Builds reprodutíveis são desejáveis: mesma entrada → mesmos hashes (ou diferenças explicadas).

### 9.3 `CHANGELOG`
Registrar por versão, em categorias: **Added / Changed / Fixed / Security / Removed / Known issues**. Cada `Fixed` referencia o ID `WS-BUG-NNNN`.

### 9.4 Rotulagem de estado da entrega
- **Candidata**: passou nos testes executáveis no ambiente do desenvolvimento.
- **Aprovada para teste do usuário**: gate completo + diagnóstico verdes.
- **Produção aprovada**: somente com verificações Windows executadas **e** aceite real do escopo. Nunca publicar automaticamente nem rotular produção sem isso.

---

## 10. Segurança operacional do aplicativo (resumo)
- Sem autoelevação; pedir elevação de forma explícita e visível ao usuário.
- Sem instalar serviço/driver silenciosamente.
- Confirmação explícita para ações N3 e para qualquer ação irreversível.
- Backups protegidos contra sobrescrita acidental, com checagem de integridade (hash) antes de qualquer Undo.
- Logs sem dados pessoais desnecessários; ZIP de diagnóstico com redação de identificadores.

---

## 11. Fluxo acelerado de entrega (R3.2.83 em diante)

- **Lotes.** Consolidar requisitos por família/risco e produzir **uma única candidata**; não criar *release* para cada ajuste pequeno. Congelar escopo antes da estabilização.
- **Testes por etapa.** Durante o desenvolvimento, executar os testes do componente alterado; na candidata, exigir **todo o cadastro** e o **self-test WPF**. Cada bug continua com regressão comportamental.
- **`Iniciar-Validacao.bat` é o ponto de entrada do aceite técnico:** gate completo, diagnóstico automático e abertura **somente após sucesso completo**. O gate integrado delega as dez suítes ao *harness*, sem execução duplicada; a execução isolada da suíte nativa continua completa.
- **Integridade dos resultados.** Resultados vazios, parciais, duplicados ou de outra execução **nunca** autorizam progressão. Falha bloqueia a abertura pelo pipeline, coleta evidência e exige correção.
- **Validação do usuário.** Valida somente efeitos reais novos/alterados por família, em lote; não repetir manualmente lotes anteriores aprovados sem regressão ou mudança relacionada. `Coletar-Diagnostico.bat` gera um ZIP com resultados, backups e resumos de benchmarks.
- **CI Windows.** Está preparada no *workflow*; enquanto não executada, marcar **pendente**. Não publicar automaticamente nem rotular produção aprovada sem verificações Windows e aceite real do escopo.

---

## 12. Hotfix e resposta a incidentes (S1)

Defeito S1 (perda de dados, Undo falho, Apply sem backup, vulnerabilidade) interrompe o fluxo normal:
1. **Conter**: suspender distribuição da versão afetada e comunicar o risco e o contorno (se houver).
2. **Reproduzir** e registrar (B1–B3) com prioridade máxima.
3. **Corrigir** com o procedimento B4–B10 — o **gate NÃO pode ser pulado**; só o escopo é reduzido (hotfix contém apenas a correção).
4. **Verificar** em Windows real (ou declarar pendência com aviso explícito) e publicar nova versão.
5. **Análise pós-incidente sem culpados**: linha do tempo, causa raiz, por que os testes não detectaram, ações preventivas (teste, regra de análise, orçamento); registrar no log (seção 5).

---

## 13. Relatório de entrega (modelo obrigatório)

Toda entrega informa:

1. **Versão/candidata** e escopo do lote (famílias, itens).
2. **Bugs corrigidos** (IDs `WS-BUG-NNNN`, severidade, causa raiz resumida).
3. **Testes executados** com resultado por suíte, usando apenas estes estados:
   - ✅ **Aprovado** — executado, com evidência (comando/saída/arquivo);
   - ⏳ **Pendente** — não executado (ex.: sem Windows/WPF; testes nativos **sempre** pendentes nessa situação);
   - ⚠️ **Limitado** — executado parcialmente, com a limitação descrita;
   - ❌ **Falhou** — com evidência e plano.
4. **Teste vermelho prévio** de cada bug (ou limitação documentada).
5. **Limitações e riscos residuais**; itens de ferramental 🆕 ainda inexistentes.
6. **Mudanças de contrato** (backup/JSON) e compatibilidade retroativa.
7. **O que o usuário precisa validar** (somente efeitos novos/alterados, por família).
8. **Como reverter** (backups, Undo, versão anterior).
9. **Hashes** dos artefatos e confirmação do empacotador.

---

## 14. Decisões de arquitetura e governança deste documento
- **ADR** curto em `docs/adr/NNNN-titulo.md` para decisões que afetem contratos, segurança, arquitetura, formato de dados ou dependências: contexto, decisão, alternativas, consequências.
- Mudanças neste `AGENTS.md` passam por revisão como código N3-lite; registrar o motivo no `CHANGELOG`. Conflito entre este arquivo e a prática: corrigir um dos dois explicitamente — não conviver com a divergência.

---

## 15. PresentMon (opcional)
- Opcional e **acionado pelo usuário**; nunca executa por conta própria.
- Binário oficial **fixado por SHA-256**; licenças preservadas.
- A captura **não aplica ajustes** e só encerra a sua **sessão ETW exclusiva**.
- **Nunca** usar *stop* global, autoelevação ou instalar serviço/driver silenciosamente.

---

## Apêndice A — Fluxo resumido

```
Intake → Especificação → Plano do lote (escopo congelado) → Design
   → Implementação (TDD) → Verificação do componente
   → Candidata: Validar-Regressoes.bat + self-test WPF + Iniciar-Validacao.bat
   → Aceite (Windows real; usuário valida só o novo, em lote)
   → Empacotamento (package_release.py, hashes, CHANGELOG) → Entrega + relatório
   → Pós-entrega (log de bugs, retrospectiva, métricas)
```

## Apêndice B — Fluxo resumido de bug

```
B1 Triagem → B2 Reprodução mínima → B3 Cadastro em cases.json (aberto)
 → B4 Teste vermelho → B5 Causa raiz → B6 Correção mínima
 → B7 Verde + adjacentes → B8 Varredura da classe → B9 Sensibilidade
 → B10 Log + CHANGELOG → B11 Gate + candidata → (aceite) verificado
 → B12 Reabertura (novo registro com regressao_de, se reaparecer)
```

## Apêndice C — Checklist do revisor
- [ ] O teste falharia sem a correção? Cobre entrada inválida/indisponibilidade e estado relacionado?
- [ ] Nenhuma expectativa foi enfraquecida; testes antigos intactos?
- [ ] Backup fiel (ausente vs. vazio, tipo de dado) e Undo restaura exatamente o original?
- [ ] Apply idempotente; falha parcial deixa estado e backup consistentes?
- [ ] Entradas externas validadas (caminhos, chaves, nomes); sem concatenação de comando; sem `Invoke-Expression`?
- [ ] Sem elevação/serviço/driver silencioso; hashes verificados?
- [ ] UI não bloqueada; recursos descartados; cancelamento/timeout tratados?
- [ ] Desempenho dentro do orçamento; sem I/O desnecessário em laços?
- [ ] Mudança mínima, legível, sem refatoração misturada; documentação/CHANGELOG atualizados?
- [ ] Relatório honesto: pendente ≠ aprovado; limitações declaradas?

## Apêndice D — Pendências de ferramental 🆕 (a implementar)
Enquanto cada item não existir, reportá-lo como **pendente** (seção 0):
1. Schema formal (JSON Schema) do `cases.json` estendido + validador integrado ao gate e ao `package_release.py`, com testes do próprio validador.
2. `tools/` gerador/validador de `docs/BUGLOG.md` a partir do `cases.json` e retroalimentação do histórico (seção 5.4).
3. Arquivo de configuração do PSScriptAnalyzer e etapa de análise estática no gate.
4. Configuração fixa do Pester 5.x (versão exata, etiquetas, saída NUnitXml).
5. Guarda de *sandbox* (`WINSLIM_TEST_SANDBOX`) para testes que tocam o sistema real.
6. Arquivo de orçamentos de desempenho versionado e comparação automática no gate.
7. Geração de SBOM e atestado de proveniência na CI Windows; fixação de versões das ações de CI.
8. Testes de UI Automation (ex.: FlaUI/UIA3) para fluxos críticos, rodando em runner Windows com sessão interativa.
9. Modelo de relatório de entrega (seção 13) e de ADR (seção 14) em `docs/`.

## Apêndice E — Referências
- PSScriptAnalyzer — regras e recomendações: https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/rules-recommendations
- Pester (testes PowerShell): https://pester.dev
- FlaUI (UI Automation para WPF/Win32): https://github.com/FlaUI/FlaUI
- SLSA (integridade de cadeia de suprimentos): https://slsa.dev
- Keep a Changelog: https://keepachangelog.com
