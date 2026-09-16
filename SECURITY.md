# Segurança e Confiança

O Win-Slim Suite modifica configurações do sistema (registro, serviços, tarefas
agendadas, pacotes do Windows). Isso é inerentemente sensível. Este documento
explica exatamente o que o script faz, o que ele **não** faz, e como você pode
verificar isso por conta própria antes de rodar como administrador.

## O que o script faz

- Lê `catalog.json` (na mesma pasta) e monta a interface a partir dele. **Nenhum
  tweak é aplicado automaticamente** — cada um só roda quando você marca a caixa
  correspondente e clica em Aplicar (ou em "Aplicar selecionadas", na aba
  Manutenção).
- Antes de qualquer alteração, salva o valor **original** de cada chave/serviço
  tocado em `winslim-rollback.json`, na mesma pasta do script. É esse arquivo,
  e não um valor "assumido" ou hardcoded, que a função de desfazer usa.
- Loga cada ação em `winslim-log.txt` (mesma pasta), com timestamp.
- Pode se auto-elevar via UAC (`Start-Process -Verb RunAs`) — isso é o próprio
  Windows pedindo sua confirmação explícita, o script não ganha admin escondido.

## O que o script NÃO faz

- Não se conecta a servidores externos, exceto quando um tweak específico
  precisa baixar uma ferramenta oficial da Microsoft (ex.: ViVeTool, usado pelo
  tweak `UI-005`) — e isso é sempre logado e visível no código-fonte daquele
  tweak específico no `catalog.json`.
- Não coleta, envia ou telemetriza nada sobre você ou sobre o seu uso do
  próprio Win-Slim Suite.
- Não executa nada fora do que está listado em `catalog.json` — o motor
  (`Invoke-TweakEngine`) só sabe fazer 6 tipos de operação (`registry`,
  `service`, `script`, `appx`, `composite`, `multilevel`), e cada uma delas é
  auditável lendo o próprio JSON, sem precisar entender PowerShell a fundo.

## Como auditar antes de rodar

Você não precisa confiar cegamente. Duas formas de conferir:

1. **Leia o `catalog.json`.** É texto plano. Cada tweak tem `name`, `description`,
   `risk` e a ação exata (`registry`/`service`/`InvokeScript`). Se um tweak
   mexe em algo que você não reconhece, procure a chave de registro ou o nome
   do serviço antes de marcar a caixa.
2. **Rode em modo simulação primeiro.** A partir da v1.3, a aba Avançado tem um
   toggle **"Modo Simulação (não altera nada)"**. Com ele ativo, o botão
   Aplicar mostra no log exatamente o que *seria* alterado — cada chave, valor
   antigo e valor novo — sem tocar no sistema de verdade. Use isso para
   verificar o comportamento antes da primeira aplicação real.

## Verificando a integridade do download

Antes de rodar um script baixado da internet como administrador, confira o
hash SHA-256 contra o publicado na página de [Releases](../../releases) deste
repositório:

```powershell
Get-FileHash .\WinSlimSuite.ps1 -Algorithm SHA256
Get-FileHash .\catalog.json -Algorithm SHA256
```

Compare o resultado com o arquivo `SHA256SUMS.txt` anexado à mesma release.
Cada release do CI já publica esse arquivo automaticamente (veja
`.github/workflows/validate-catalog.yml`).

Prefira sempre baixar de uma **tag/release fixa** em vez de `main`:

```powershell
irm https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/tags/v1.0/WinSlimSuite.ps1 -OutFile WinSlimSuite.ps1
irm https://raw.githubusercontent.com/pauloatx/Win-Slim/refs/tags/v1.0/catalog.json -OutFile catalog.json
```

`main` pode mudar a qualquer momento; uma tag, não. Isso importa especialmente
se você automatiza a instalação (ex.: `irm ... | iex`) — **evite `| iex`
direto de `main`** por princípio, mesmo confiando no autor.

## Reportando uma vulnerabilidade ou tweak perigoso

Se você encontrar um tweak que:
- faz algo diferente do que a `description` diz,
- não é reversível apesar do catálogo afirmar que é,
- ou representa risco de segurança não classificado como `Alto`,

abra uma [issue](../../issues/new/choose) usando o template "Bug de rollback"
ou "Tweak não funcionou", ou marque como confidencial se envolver uma falha de
segurança mais séria (ex.: execução de código não solicitada).
