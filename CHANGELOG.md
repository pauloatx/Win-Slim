# Changelog

Este projeto documenta mudanças de forma que dê pra confiar: cada entrada diz
o que mudou e, quando relevante, **por quê** — principalmente para os bugs de
catálogo, que não davam erro nenhum na tela.

## [Suite v1.3] — catalog.json schemaVersion 1.3

### Corrigido — integridade do catálogo
Encontrados numa auditoria completa (ver `scripts/Validate-Catalog.ps1`, criado
nesta versão justamente para pegar essa classe de bug automaticamente daqui pra
frente):

- **Duplicata exata removida:** `PERF-003` fazia exatamente a mesma coisa que
  `RESP-005` (desativar hibernação). Mantido `RESP-005` (já era o ID
  corretamente referenciado por `RESP-006.conflicts`).
- **Duplicata exata removida:** `APP-013` ("Get Started") e `APP-047` ("Tips")
  removiam o mesmo pacote appx (`Microsoft.Getstarted` — o app foi renomeado
  pela Microsoft, o pacote é o mesmo). Mantido `APP-047`.
- **Acentuação padronizada:** 11 tweaks tinham `"risk": "Medio"` sem acento em
  vez de `"Médio"`. Isso não é só estética — o seletor de cor do badge de risco
  na UI compara com o literal `'Médio'`, então esses 11 apareciam com a cor
  cinza de "risco desconhecido" em vez da cor amarela correta. Afetava:
  `UI-005, SEC-005, SEC-007, MLV-002, RESP-005, PERF-013, MLV-004, NET-007,
  SEC-009, SEC-010`.
- **Vazamento de rollback corrigido (PRIV-002 / PRIV-008):** os dois escreviam
  a mesma chave `PublishUserActivities`. Como o motor de undo restaura pelo
  valor original *daquele tweak específico*, desativar só um dos dois revertia
  a chave mesmo com o outro ainda "ativo". Removida a duplicata de `PRIV-008`.
- **Vazamento de rollback corrigido (PERF-001 / RESP-002):** mesmo problema,
  com `MenuShowDelay`. Removida a duplicata de `RESP-002` (nenhum preset perde
  o efeito, `PERF-001` cobre 100% dos presets onde `RESP-002` também aparece).
- **Conflito real declarado (PERF-012 ↔ EXTRA-005):** os dois escrevem
  `SystemResponsiveness`, mas com valores diferentes (10 vs 0). Não eram
  duplicatas — eram dois tweaks competindo pela mesma chave, sem se
  declararem em conflito, **e ambos estavam nos presets Gamer/Extremo ao mesmo
  tempo** — ou seja, todo preset aplicado colidia silenciosamente. Declarado
  conflito mútuo; `PERF-012` (mais brando) saiu dos presets automáticos e
  ficou como opção manual. `EXTRA-005` (mais agressivo) permanece nos presets.
- **Conflito assimétrico corrigido (PERF-011 ↔ SEC-006):** `SEC-006` já
  declarava conflito com `PERF-011`, mas não o contrário. Como a resolução de
  conflitos depende da ordem de seleção, isso permitia os dois ficarem ativos
  ao mesmo tempo dependendo de qual foi marcado primeiro. Agora é simétrico.

### Adicionado
- **Modo Simulação** (aba Avançado): toggle que faz Aplicar/Desfazer mostrarem
  no log exatamente o que *seria* alterado — chave por chave, valor atual vs.
  novo — sem tocar no sistema real. Motor de simulação é um caminho de código
  totalmente separado do motor real, para ficar fácil de auditar que ele não
  escreve nada.
- `scripts/Validate-Catalog.ps1`: valida IDs únicos, presets válidos, cada
  tweak reversível (tem `UndoScript` ou `OriginalValue`/`OriginalType`),
  sintaxe PowerShell real de todo `InvokeScript`/`UndoScript` (via
  `[System.Management.Automation.Language.Parser]::ParseInput`), simetria de
  `conflicts`, e duplicatas de ação entre IDs diferentes.
- `.github/workflows/validate-catalog.yml`: roda o validador acima em todo
  push/PR que toque `catalog.json`, confere BOM UTF-8 nos `.ps1` (ver nota
  abaixo) e publica `SHA256SUMS.txt` como artefato do build.
- `SECURITY.md`: o que o script faz, o que não faz, como auditar antes de
  rodar, e como conferir o hash do download.
- Tweaks de GPU: `PRIV-015` (telemetria AMD) e `PERF-018` (MSI Mode).

### Corrigido — engine (`WinSlimSuite.ps1`)
- Bug de `NaN` na barra de progresso da aba Manutenção quando exatamente 1
  ação era selecionada (PowerShell "desembrulha" um array de 1 elemento vindo
  de `foreach`, então `.Count` virava `$null` e a divisão por zero gerava
  `NaN`, que o WPF rejeita como valor de `ProgressBar.Value`).
- Mesma classe de bug corrigida em duas contagens de UI que podiam mostrar
  número errado com exatamente 1 item ativo.
- **Encoding:** `.ps1` sem BOM UTF-8 fazia o PowerShell 5.1 interpretar
  acentos como ANSI, corrompendo strings e quebrando o parser inteiro do
  script. BOM adicionado; CI agora falha o build se algum `.ps1` publicado não
  tiver BOM.

### Aba Manutenção
- Os 5 itens viraram checkboxes com um botão "Aplicar selecionadas" no
  rodapé, em vez de cada um executar imediatamente ao clicar.
- Janela de confirmação agora só aparece para ações de risco **Alto** entre as
  selecionadas (nenhuma das 5 atuais é Alto, então normalmente não aparece) —
  antes aparecia sempre, para qualquer ação, independente do risco real.

### Outros
- Badge discreto de hardware detectado (CPU/RAM/GPU/disco) no cabeçalho,
  sempre visível, com detalhamento completo no tooltip.

---

## Versionamento

A partir desta versão, `catalog.json.schemaVersion` é incrementado sempre que
uma mudança de dados no catálogo puder afetar comportamento (não só ao mudar a
estrutura do schema). Mudanças de schema puramente aditivas (novo campo
opcional) não exigem bump de major.
