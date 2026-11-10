# Win-Slim Suite — FASE 7 R3.1.1

Hotfix de runtime da interface R3.1.

## O que aconteceu

O layout R3.1 estava correto estaticamente, mas o Windows PowerShell 5.1 executou
o callback WPF `ContentRendered` fora do escopo local em que
`Set-WinSlimControlText` havia sido declarado. Por isso a janela encerrava com
`CommandNotFoundException`.

## O que foi corrigido

Os helpers acionados por eventos WPF agora são funções top-level exclusivas
`R311`, e o estado necessário aos callbacks fica em escopo `script:`. Assim,
`ContentRendered`, `DispatcherTimer`, navegação, presets e overlays conseguem
resolver os helpers durante todo o ciclo de vida da janela.

O XAML da R3.1 foi mantido sem mudanças: o objetivo deste pacote é corrigir
somente o runtime, não alterar novamente o layout.

## Teste

```powershell
cd "D:\Desktop\winslim_fase7_r3_1_1"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.1.1-Runtime.ps1
```

Depois abra:

```text
Executar-WinSlim-R3.1.1.bat
```

A FASE 7 R4 só deve começar depois de a R3.1.1 abrir e permanecer estável.
