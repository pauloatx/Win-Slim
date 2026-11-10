# Win-Slim Suite — FASE 7 R2

## Objetivo
Conectar a nova UI ao **Dashboard + hardware/contexto real**, seguindo o mockup aprovado e mantendo a camada visual sem mutação direta do Windows.

## O que esta revisão lê
- Windows, build e arquitetura
- CPU, núcleos/threads
- GPU e driver
- RAM
- armazenamento / barramento / tamanho
- desktop ou notebook
- Secure Boot, TPM, VBS, HVCI e BitLocker
- reinício pendente
- adaptadores físicos ativos
- plano de energia ativo
- uso atual de CPU, GPU, RAM e disco

Alguns campos podem aparecer como **Indisponível** quando o Windows, firmware ou driver não expõe a informação. A UI não inventa valores; temperatura de CPU, por exemplo, não é apresentada como leitura real sem uma fonte confiável.

## Arquitetura
A R1 permanece congelada. Durante o desenvolvimento, a R2 usa arquivos próprios:

- `WinSlimSuite.Fase7R2.ps1`
- `Executar-WinSlim-R2.bat`
- `src/UI/Fase7/SystemContextView.R2.ps1`
- `src/UI/Fase7/WinSlimShell.R2.ps1`
- `src/UI/Fase7/WinSlimShell.R2.xaml`

Isso permite executar novamente o gate R1 sem falsos regressos por hash.

## Teste
No PowerShell aberto na raiz do pacote:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R2-UI.ps1
```

Após **FASE 7 R2 APROVADA**, abra:

```text
Executar-WinSlim-R2.bat
```

## Próxima etapa
FASE 7 R3 — Presets + overlays condicionais.
