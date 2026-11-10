# Win-Slim Suite — FASE 7 R3.1

Esta revisão corrige a interpretação visual da imagem de referência.

A faixa superior grande com slogan e selos "Seguro / Confiável / Simples" pertence à **prancha de apresentação**, não às janelas internas do aplicativo. A R3.1 passa a reproduzir o layout das janelas internas: barra de título fina, menu lateral estreito, cards compactos e alta densidade de informação.

## Executar

```powershell
cd "D:\Desktop\winslim_fase7_r3_1"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R3.1-Layout.ps1
```

Depois:

```text
Executar-WinSlim-R3.1.bat
```

A R3 original continua preservada byte a byte. Esta revisão é visual e não avança a semântica transacional do projeto.
