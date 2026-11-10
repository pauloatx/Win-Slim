# Temas do overlay e configurações — R3.2.84

Validação em 26/10/2026; conferência documental final em 27/10/2026, America/Sao_Paulo. **Implementação e validação técnica/visual concluídas; produção não aprovada.** Escopo congelado: tema das configurações e do overlay flutuante, sincronização/persistência e correções de acessibilidade necessárias para operar os novos controles. Aceites Edge/P4/P7/P9 preservados.

## Comportamento final

- Claro, Escuro e Automático aparecem como escolhas exclusivas na aba Aparência. A seleção aplica imediatamente ao editor, à prévia e ao overlay aberto; Salvar confirma e Cancelar/fechar restaura a preferência anterior.
- O campo opcional `ThemeMode` usa o mesmo perfil existente por executável e os padrões gerais para jogos novos. Um perfil antigo sem esse campo respeita a preferência manual salva em `config/WinSlim-theme.json`; sem escolha manual, inicia no automático. Perfis de outros jogos não são regravados. Automático acompanha `AppsUseLightTheme`, notificações nativas e `SystemEvents.UserPreferenceChanged`.
- O botão compacto ☀/☾ indica o tema ativo, oferece nome/ajuda acessível com a próxima ação e alterna imediatamente. Fora do editor salva o perfil; com o editor aberto participa da prévia e respeita Salvar/Cancelar. Falha de armazenamento conserva a preferência e a aparência anteriores.
- O botão utiliza o HWND separado já existente para os controles. Continua clicável com o overlay travado, mantendo o HWND das métricas com passagem de cliques. Pequeno/Médio, Mover/Travar, atalhos, amostras e referência permanecem preservados.
- Fundos, textos, campos, sliders, abas, tooltips, bordas e estados selecionados seguem a paleta. Pincéis ligados ao modelo evitam o congelamento pelo WPF durante mudanças de tema. O gráfico conserva os valores RGB aprovados de atual laranja e referência azul tracejada; no claro, uma borda de contraste acompanha as mesmas curvas sem alterar amostras/escala.

O template das abas passou a fornecer `PART_SelectedContentHost`, e as escolhas de tema usam seleção de radio button/Checked. Isso expõe o conteúdo selecionado e executa a preferência também pela automação, além de atualizar o estado visual. A relação entre o conteúdo selecionado e a árvore de automação é documentada no [código oficial do TabItemAutomationPeer](https://source.dot.net/presentationframework/System/Windows/Automation/Peers/TabItemAutomationPeer.cs.html); a implementação foi conferida por travessia real de peers e pela UI Automation na VM.

## Arquivos alterados

| Arquivo | Alteração |
| --- | --- |
| `src/UI/Native/R3_2_84/BenchmarkOverlay.cs` | Preferência opcional, paletas, leitura/notificações Windows, botão compacto, persistência/rollback e sincronização por eventos; sem interromper transporte/captura |
| `src/UI/Native/R3_2_84/BenchmarkSettingsWindow.cs` | Escolhas de tema, recursos dinâmicos, prévia/Save/Cancel, sincronização com overlay anexado e conteúdo das abas acessível |
| `src/UI/Native/R3_2_84/MainWindowController.cs` | Somente ampliação do self-test: troca de tema durante tarefa de captura pendente e restauração por Cancelar |
| `tests/fixtures/OverlayThemeFixture.cs` | Nova fixture comportamental WPF em DLL sem Main, 75 checks |
| `tests/Test-Fase7-R3.2.84-OverlayTheme.ps1` | Runner com política independente, proveniência antes da carga e conservação dos resultados |
| `tests/BenchmarkOverlayHarness.cs` | Limpeza final passa a usar a rotina delimitada já testada, com tentativas limitadas; caminho interno curto continua contendo espaço |
| `tests/regression/cases.json` | REG-OVERLAYTHEME-001 e cenário de limpeza externa da REG-OVERLAY-001; 28 casos únicos |
| `release/review.json`, `release/security-incidents.json` | Manifesto estendido a 46 activeFiles e cadeia de hashes; disposição/bloqueios AV preservados |
| `release/escopo-R3.2.84.json`, `specs/FASE7-R3.2.84-baseline.json` | Escopo, resultados, identidade e hashes atuais |
| `REVISAO-TECNICA-GATE-R3.2.84.md`, `RETOMADA-R3.2.84-AV.md`, `docs/PROMPT-RETOMADA-WINSLIM-20261024.md` | Revisão de alcance e continuidade atualizadas |
| Este relatório | Resultados, evidências e limites |

`BenchmarkSettings.cs` e a correção UI-HOTKEY-WPARAM-001 permanecem byte a byte iguais. Build oficial, fontes explícitas e C# 5/.NET Framework/WPF/PowerShell 5.1 preservados; Python continua sendo ferramenta de desenvolvimento.

## Regressões e gate

- **Antes da correção:** seis checks comportamentais falharam, confirmando paleta fixa escura e ausência dos controles: `logs/overlay-theme-fixture-0f36ac5b8e344f6f87f4d36aaa8977b2/`.
- **Acessibilidade:** a travessia real do conteúdo selecionado falhou antes do ajuste do template; a seleção pelo provider também reproduziu o caso em que só o checkmark mudava. Evidências em `logs/overlay-theme-20261026-81ef16dd/accessibility-before.log` e `accessible-selection-before.log`. Ambos corrigidos sem alterar as expectativas.
- **Resultado final:** 75 checks de tema, 82 do overlay existente, 118 de configurações existentes e 113 da regressão de atalhos aprovados dentro do gate. Há entrada ausente/corrompida, fonte de sistema indisponível, Save bloqueado, rollback/Cancel, bytes de outros jogos, restauração de preferência, HWND travado/proxy, geometria, cores/curvas, controles e contraste de texto ≥4,5 em DPI simulados 100/125/150.
- **Captura pendente:** o self-test do controlador real mantém sua tarefa de captura de fixture pendente enquanto alterna claro/escuro/auto; verifica processo/seleção, cancelamento, resultado, referência, tamanho, posição e restauração pelo Cancelar. Não se apresenta essa fixture como captura física.
- **Gate final:** `Iniciar-Validacao.bat /ci`, exit **0**, **28/28 IDs distintos**, completos e correspondentes ao cadastro. [Resultado](../logs/regressao-20261027-023740-948-e5a40289/resultado.json), [resumo](../logs/candidato-r3284-20261027-023740-681-8521325d/summary.json). Build oficial e self-test WPF incluídos. `TechnicalPassed=true`, `ProductionApproved=false`.
- **Empacotador:** 22 testes Python aprovados; cadastro único, scripts e hashes finais conferidos por `tools/package_release.py`, sem publicação de ZIP de aplicação.

Histórico preservado: um gate intermediário 28/28 aprovou a implementação anterior à descoberta visual de acessibilidade. A tentativa seguinte foi corretamente bloqueada por `REG-OVERLAY-001`: todos os checks comportamentais haviam passado, mas a limpeza externa por Directory.Delete falhou com pasta não vazia. A causa imediata de IO não foi atribuída ao AV. O harness passou a reutilizar a limpeza exclusiva com retry limitado, já coberta por injeção de IO transitório/persistente e preservação de diretório alheio. Uma tentativa de organização com caminho interno longo foi reduzida para respeitar o limite do .NET Framework. Nenhuma expectativa foi removida. O gate final acima é o único que aprova a candidata final. Relatório bloqueado: `logs/regressao-20261027-023218-036-d9dd9421/resultado.json`.

Durante a ampliação da fixture, a verificação de ausência de arquivo foi posicionada antes da criação do HWND: a posição nativa já é persistida legitimamente pelo contrato anterior. Após posicionar, a notificação de tema é verificada pela preservação dos bytes dessa geometria, não pela proibição de sua criação.

## Build final

`bin/WinSlim.UI.Native.R3.2.84.exe`

**SHA-256: `62EB3819580EFA1D1E80151E9934646B796572FE2E9AC786BDB961241A04DE62`**

Conferido no host, na cópia da VM e ao final. Foram usados os 89 arquivos completos da candidata atual, com XAML, catálogos, presets, backend/Core/Providers e EXE/config. Nenhuma mistura com a candidata intermediária. Logs e impressão das entradas: `logs/overlay-theme-vm-20261026-5410de9a/build-final.log`, `build-final-inputs.json`, `candidate-final-manifest.json` e `guest-final-staging.json`.

## Validação visual na VM

VM `teste win-slim-win11`, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`. Inicialmente desligada, no snapshot `WINSLIM_BASELINE`. A gravação anterior foi conferida contra sua cópia já preservada; o convidado foi inspecionado antes de qualquer restauração e não continha raiz Win-Slim com dados pendentes.

Evidências: [pasta da validação](../logs/overlay-theme-vm-20261026-5410de9a/) e [resultado estruturado](../logs/overlay-theme-vm-20261026-5410de9a/validation-results.json). Capturas efetivamente inspecionadas pelo Codex:

| Cenário | Captura |
| --- | --- |
| Editor e overlay claro / Pequeno | [10-final-light-small.png](../logs/overlay-theme-vm-20261026-5410de9a/10-final-light-small.png) |
| Editor e overlay escuro / Pequeno | [11-final-dark-small.png](../logs/overlay-theme-vm-20261026-5410de9a/11-final-dark-small.png) |
| Editor e overlay escuro / Médio, duas curvas | [12-final-dark-medium.png](../logs/overlay-theme-vm-20261026-5410de9a/12-final-dark-medium.png) |
| Editor e overlay claro / Médio, duas curvas | [13-final-light-medium.png](../logs/overlay-theme-vm-20261026-5410de9a/13-final-light-medium.png) |
| Botão físico clicado com overlay travado, preferência salva | [16-locked-theme-button-persisted.png](../logs/overlay-theme-vm-20261026-5410de9a/16-locked-theme-button-persisted.png) |
| Automático após alterar a preferência real do Windows para escuro | [22-auto-dark-windows-change.png](../logs/overlay-theme-vm-20261026-5410de9a/22-auto-dark-windows-change.png) |
| Automático após restaurar Windows claro | [24-auto-light-restored-system.png](../logs/overlay-theme-vm-20261026-5410de9a/24-auto-light-restored-system.png) |
| Informações e Atalhos, ambos os temas | `26-information-light.png`, `27-shortcuts-light.png`, `28-shortcuts-dark.png`, `29-information-dark.png` |
| Janela aberta pelo aplicativo completo, escuro e automático/claro | [35-native-settings-dark-clean.png](../logs/overlay-theme-vm-20261026-5410de9a/35-native-settings-dark-clean.png), [36-native-settings-auto-light.png](../logs/overlay-theme-vm-20261026-5410de9a/36-native-settings-auto-light.png) |

O teste flutuante carregou as classes de produção **do EXE final** por reflexão, sem recompilar uma variante. Os valores eram explicitamente ilustrativos e continuaram atualizando durante as trocas. O aplicativo completo também foi aberto normalmente, exibiu o editor nos dois temas e fechou pelo WindowPattern.Close com exit 0. Nenhum diálogo de erro, OverflowException ou erro visual registrado nos logs.

Provas adicionais em JSON/`ui-actions.jsonl`: Save persistiu claro; clique real no botão do HWND de controles, travado, persistiu escuro; reabertura mostrou a escolha correspondente; Cancelar preservou exatamente o hash do perfil anterior. Clique nas métricas aumentou o contador da janela de teste atrás delas, enquanto o botão não o acionou. Posição/handles/referência e medidas foram preservados durante as trocas de tema de cada tamanho.

Somente na VM, `AppsUseLightTheme` foi alterado de 1 para 0 e novamente 1, com notificação WM_SETTINGCHANGE ao HWND de produção. O automático acompanhou as duas mudanças; o perfil salvo permaneceu byte a byte igual após a notificação. A preferência original foi restaurada **antes** do desligamento. A baseline usa Defender ativo, sem Kaspersky instalado; nenhuma proteção foi alterada. Não houve Apply/Undo Edge, política alterada, backup novo, coletor/ETW ou execução das famílias retidas.

## Coleta e estado final

Nove arquivos de logs/configuração/evidência dos dois stagings foram copiados e verificados individualmente por SHA-256 **antes** de desligar/restaurar. Os estados Edge antes/depois são byte a byte iguais. Capturas, ações e gravação da sessão também foram preservadas. A gravação foi copiada/conferida após sua finalização, antes do restore; não foi analisada quadro a quadro.

**Estado final: VM desligada normalmente por ACPI, snapshot WINSLIM_BASELINE restaurado, exit 0.** UUID do snapshot `4aa21603-c0b4-4139-9630-1e5d0acaef20`; novo disco diferencial ligado à imagem da baseline. Recibos: `collection-initial-receipt.json`, `collection-final-receipt.json`, `recording-receipt.json`, `baseline-restore-receipt.json`, `vm-after-baseline.txt` e `baseline-disk-info.txt`.

**Limites:** alternância durante captura física de um jogo não foi exercitada nesta rodada; os testes de captura usam o controlador de produção com entrada determinística e a validação visual usa métricas ilustrativas. DPI físico/múltiplos monitores e CI Windows hospedada não foram reaceitos. Os aceites anteriores permanecem válidos; a interação de tema em jogo real é um aceite adicional, não um cancelamento deles. Incidente AV histórico sem resolução do fabricante, harnesses PresentMon/Monitor retidos e `distribution: hold` preservados. Nenhuma publicação ou aprovação de produção.
