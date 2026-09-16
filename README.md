<p align="center">
  <img src="assets/feather-icon.svg" width="96" height="96" alt="Win-Slim" />
</p>

<h1 align="center">Win-Slim</h1>
<p align="center"><i>Transformando o Windows do jeito que você quiser.</i></p>

# Win-Slim Suite

**169 tweaks reversíveis para Windows 10/11 — com rollback do estado real do
seu sistema, não de valores assumidos.**

Toda ferramenta de debloat promete "reverter" o que faz. A maioria reverte
para um valor padrão *assumido* (ex.: "volta pra 0 porque geralmente é 0").
O Win-Slim Suite salva o valor **que estava no seu sistema antes de aplicar**
— chave por chave — em `winslim-rollback.json`, e desfaz para *aquele* valor
específico. É a diferença entre "provavelmente volta ao normal" e "volta
exatamente para onde estava".

[![Tweaks](https://img.shields.io/badge/tweaks-169-blue)](./catalog.json)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6)](#compatibilidade)
[![Catálogo](https://img.shields.io/badge/schemaVersion-1.3-informational)](./catalog.json)
[![CI](https://github.com/pauloatx/Win-Slim/actions/workflows/validate-catalog.yml/badge.svg)](./.github/workflows/validate-catalog.yml)
[![Licença](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

<!--
  TODO (autor): substituir por um GIF/screenshot real da Suite rodando.
  Sugestão de captura: aba Bem-vindo com os 3 presets visíveis, depois um
  GIF curto (10-15s) mostrando: marcar alguns tweaks na aba Avançado -> ligar
  o Modo Simulação -> clicar Aplicar -> mostrar o log detalhando o que
  "seria" alterado. Isso vende a proposta de confiança melhor que qualquer
  texto.
  ![Win-Slim Suite rodando](./docs/screenshot-avancado.png)
-->

## Sumário

- [Por que existe mais um debloater?](#por-que-existe-mais-um-debloater)
- [Instalação](#instalação)
- [Como isso é diferente do WinUtil / Atlas / Win-Debloat-Tools?](#como-isso-é-diferente-do-winutil--atlas--win-debloat-tools)
- [Qual versão eu uso?](#qual-versão-eu-uso)
- [Modo Simulação](#modo-simulação)
- [FAQ](#faq)
- [Segurança](#segurança)
- [Contribuindo](#contribuindo)
- [Créditos](#créditos)

## Por que existe mais um debloater?

O mercado de scripts de tweak para Windows é saturado — WinUtil, Atlas,
Win-Debloat-Tools já fazem "remover bloatware e desativar telemetria" muito
bem. O Win-Slim Suite não tenta competir em quantidade de tweaks. Compete em
**auditabilidade**: cada um dos 169 tweaks no `catalog.json` tem `risk`,
`description`, `source` (de qual projeto/documentação ele veio) e uma forma
de reverter que é validada automaticamente no CI antes de qualquer release
(veja [`scripts/Validate-Catalog.ps1`](./scripts/Validate-Catalog.ps1)).

## Instalação

> ⚠️ Prefira sempre uma **tag/release fixa** em vez de `main`. `main` pode
> mudar a qualquer momento; uma tag, não — isso importa especialmente para um
> comando que baixa e executa código como administrador.

**Win-Slim Suite (recomendado)** — interface gráfica, catálogo de 169 tweaks,
presets, rollback real, Modo Simulação:

```powershell
# baixa os dois arquivos de uma release fixa (troque v1.3 pela última tag)
irm https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/tags/v1.3/WinSlimSuite.ps1 -OutFile WinSlimSuite.ps1
irm https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/tags/v1.3/catalog.json -OutFile catalog.json

# confira o hash contra o SHA256SUMS.txt publicado na release antes de rodar
Get-FileHash .\WinSlimSuite.ps1, .\catalog.json -Algorithm SHA256

# rode como administrador (o script pede elevação via UAC sozinho)
powershell -ExecutionPolicy Bypass -File .\WinSlimSuite.ps1
```

Veja [SECURITY.md](./SECURITY.md) para o passo a passo completo de auditoria
antes de rodar, e o que exatamente o script faz e não faz.

## Como isso é diferente do WinUtil / Atlas / Win-Debloat-Tools?

Comparação honesta — cada projeto tem um objetivo diferente, nenhum é
estritamente "melhor":

| | **Win-Slim Suite** | WinUtil | Atlas | Win-Debloat-Tools |
|---|---|---|---|---|
| Rollback | Valor real capturado por tweak, por chave | Parcial (alguns tweaks) | Não é o foco (Atlas é uma imagem/config, não um toggle reversível) | Parcial |
| Cada tweak documentado (risco + origem) | Sim, em `catalog.json` | Parcial | Documentação separada (site) | Parcial |
| Modo simulação (dry-run) | Sim | Não | Não aplicável | Não |
| Interface | WPF (GUI nativa) | WPF (GUI nativa) | Ferramenta de imagem/instalação | Terminal/GUI simples |
| Foco | Reversibilidade auditável | Amplitude de utilitários (muito mais que tweaks) | Performance extrema para gaming (mexe mais fundo no SO) | Privacidade/debloat |
| Validação automática do catálogo (CI) | Sim | N/A (não é catálogo de dados) | N/A | Não |

Se você quer o máximo de utilitários num só lugar, o WinUtil provavelmente
serve melhor. Se você quer performance de nível "reinstalar o Windows do
zero", o Atlas existe pra isso. Se seu critério principal é **saber
exatamente o que vai mudar e ter certeza de que consegue voltar atrás**, é
para isso que o Win-Slim Suite foi desenhado.

## Qual versão eu uso?

Este repositório tem 3 scripts. Use esta tabela, não adivinhe:

| Arquivo | Status | Use se... |
|---|---|---|
| **`WinSlimSuite.ps1`** + `catalog.json` | ✅ Ativo — recomendado | Você quer a experiência completa: GUI, presets, rollback real, Modo Simulação, 169 tweaks documentados. |
| `Win-Slim.ps1` | 🟡 Legado — mantido, sem novas funcionalidades | Você só quer um one-liner rápido (`irm ... \| iex`), sem GUI, aceitando um conjunto menor e menos auditável de tweaks. |
| `Win-SlimBeta.ps1` | 🔴 Descontinuado | **Não use.** Era uma versão beta da *arquitetura antiga* — hoje o `WinSlimSuite.ps1` é estritamente superior em tudo que o Beta tentava fazer. Mantido só por histórico; será removido numa versão futura. |

Se você chegou aqui vindo de um link antigo para `Win-SlimBeta.ps1`, use o
`WinSlimSuite.ps1` — não há nenhum motivo para preferir o Beta hoje.

## Modo Simulação

A aba Avançado tem um toggle **"🧪 Modo Simulação (não altera nada)"**. Com
ele ligado, Aplicar e Desfazer mostram no log exatamente o que *seria*
alterado — cada chave de registro, valor atual e valor novo — sem tocar no
sistema de verdade. Use isso na primeira vez que for aplicar um preset novo,
antes de confiar de olhos fechados.

## FAQ

**É seguro?**
O script só altera o que está listado em `catalog.json`, e só quando você
clica em Aplicar — nada roda sozinho. Veja [SECURITY.md](./SECURITY.md) para
o detalhamento completo e como auditar o código você mesmo antes de rodar
como administrador.

**Como eu desfaço?**
Botão "↺ Rollback" (aba Avançado) ou "↺ Rollback" (aba Bem-vindo) restauram,
tweak por tweak, o valor que estava salvo em `winslim-rollback.json` — o
estado real do seu sistema antes da aplicação, não um valor padrão assumido.

**Funciona no 24H2/25H2?**
O catálogo declara `windowsVersion` por tweak (`"10"`/`"11"`), e a interface
só mostra os compatíveis com a build detectada automaticamente no seu
sistema. Builds específicas mais recentes (24H2, 25H2) são suportadas quando
o tweak em questão não depende de um recurso removido/alterado nessa build —
se algo quebrar numa build específica, abra uma issue usando o template
"Tweak não funcionou" informando a build exata.

**Precisa de internet?**
Não, para a maioria dos tweaks — eles mexem em registro/serviços/tarefas
locais. Alguns poucos tweaks (ex.: `UI-005`, que usa o ViVeTool oficial da
Microsoft) baixam uma ferramenta específica na primeira execução; isso está
documentado na `description` de cada tweak que precisa disso.

**O rollback é 100% garantido em qualquer combinação de tweaks?**
Não — se dois tweaks diferentes escrevem a mesma chave de registro sem se
declararem em conflito, desfazer um pode interferir no outro. É exatamente
essa classe de bug que o `scripts/Validate-Catalog.ps1` audita a cada
mudança no catálogo (veja o [CHANGELOG](./CHANGELOG.md) da v1.3 para um
exemplo real disso sendo encontrado e corrigido).

## Segurança

Ver [SECURITY.md](./SECURITY.md): o que o script faz, o que não faz, como
auditar antes de rodar, e como verificar o hash SHA-256 do download.

## Contribuindo

Quer sugerir um tweak, reportar um bug, ou avisar de um problema de rollback?
Use os templates de issue: ["🔧 Tweak não funcionou"](../../issues/new?template=tweak-nao-funcionou.md),
["💡 Pedido de tweak"](../../issues/new?template=pedido-de-tweak.md), ou
["↺ Bug de rollback"](../../issues/new?template=bug-de-rollback.md).

Antes de abrir um PR alterando `catalog.json`, rode a validação localmente:

```powershell
pwsh ./scripts/Validate-Catalog.ps1 -Strict
```

## Créditos

Este projeto foi inspirado e construído utilizando conceitos, ferramentas e
código de referência de projetos da comunidade de otimização do Windows:

- **[Win-Debloat-Tools](https://github.com/LeDragoX/Win-Debloat-Tools)** —
  scripts de remoção de telemetria, bloatware e otimizações de privacidade.
- **[Chris Titus Tech WinUtil](https://github.com/ChrisTitusTech/winutil)** —
  estrutura de utilitários rápidos e o modelo de distribuição via
  `irm ... | iex`.
- **[Atlas OS](https://github.com/Atlas-OS/Atlas)** — pesquisa avançada em
  redução de latência e input lag.
- **[meetrevision/playbook](https://github.com/meetrevision/playbook)** —
  metodologias de otimização extrema de performance e privacidade.

## Licença

[MIT](./LICENSE)
