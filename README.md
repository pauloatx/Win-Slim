<p align="center">
  <img src="assets/feather-icon.svg" width="96" height="96" alt="Win-Slim" />
</p>

<h1 align="center">Win-Slim</h1>
<p align="center"><i>Transformando o Windows do jeito que você quiser.</i></p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-FF8C42?style=flat-square" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-171A21?style=flat-square" alt="Windows 10 e 11">
</p>

Conjunto de scripts para deixar o Windows 10 e 11 mais leve, rápido e sob seu
controle — sem depender de nada instalado, só um comando no PowerShell.
Escolha a versão que combina com você: **Win-Slim** (a original), **Win-Slim
Beta** (novidades em teste) ou **Win-Slim Suite** (interface gráfica completa,
com catálogo de tweaks, presets e rollback profissional).

---

**Executar o PowerShell como Administrador (recomendado)**

---

## 🪶 Win-Slim Suite

Versão com **interface gráfica completa**: aba de boas-vindas com presets
(Balanceado / Gamer / Extremo) e aba Avançado com um catálogo de mais de 140
tweaks individuais — privacidade, debloat de apps, serviços, performance,
interface, rede, segurança e updates — cada um com nível de risco, compatibilidade
por versão do Windows, e alguns com múltiplos níveis de intensidade ajustáveis.

Consolida e resolve conflitos/redundâncias entre WinUtil, Atlas-OS,
Win-Debloat-Tools, MeetRevision Playbook e o próprio Win-Slim, tudo numa
interface só.

**Destaques:**
- SysMain e Windows Search são sempre **otimizados**, nunca desativados às cegas.
- **Rollback profissional**: antes de aplicar qualquer coisa, o estado real do
  seu sistema é salvo — o botão de Desfazer restaura exatamente esse estado,
  não um valor genérico assumido.
- Verificação opcional de arquivos baixados via **VirusTotal** (API gratuita).
- Tema escuro com detalhes em laranja, pensado para ser simples de usar mesmo
  por quem não mexe com PowerShell no dia a dia.

```powershell
irm https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/heads/main/WinSlimSuite.ps1 | iex
```

> A Suite baixa automaticamente o catálogo de tweaks mais atualizado
> (`catalog.json`) na primeira execução — não precisa baixar nada manualmente.

---

## Créditos e agradecimentos

O catálogo de tweaks do **Win-Slim Suite** foi construído consolidando ideias,
tweaks e abordagens de outros projetos open-source de otimização do Windows —
com os devidos créditos aos seus criadores:

- **WinUtil**, de [Chris Titus Tech](https://github.com/ChrisTitusTech) —
  [github.com/ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil)
- **Win-Debloat-Tools**, de [LeDragoX](https://github.com/LeDragoX) —
  [github.com/LeDragoX/Win-Debloat-Tools](https://github.com/LeDragoX/Win-Debloat-Tools)
- **Playbook (MeetRevision, antigo ReviOS)**, da equipe
  [MeetRevision](https://github.com/meetrevision) —
  [github.com/meetrevision/playbook](https://github.com/meetrevision/playbook)
- **Atlas**, da equipe [Atlas-OS](https://github.com/Atlas-OS) —
  [github.com/Atlas-OS/Atlas](https://github.com/Atlas-OS/Atlas)

Obrigado a todos que mantêm esses projetos abertos — sem eles, boa parte do
conhecimento sobre tweaks, riscos e compatibilidade reunido aqui não existiria.

---

## Licença

Distribuído sob a licença **MIT**. Veja [LICENSE](LICENSE) para mais detalhes.
