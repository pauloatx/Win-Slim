# Win-Slim Suite — FASE 7 R1

Esta revisão inicia a nova UI aprovada para a FASE 7.

## Escopo desta revisão

- Shell principal WPF.
- Tema preto / laranja seguindo o mockup aprovado.
- Header, branding, indicadores de segurança e status.
- Menu lateral: Início, Presets, Personalizado, Backup / Restore, Análise do Sistema, Configurações e Sobre.
- Navegação entre páginas sem recarregar a janela.
- Dashboard-base e estruturas visuais das páginas futuras.
- Conexão somente de leitura ao runtime promovido para exibir o estado Planner/Transaction e validar os 230 tweaks.

## Fora do escopo R1

A R1 não executa tweaks. Dashboard de hardware real entra em R2; Presets funcionais em R3; catálogo em R4; Preview em R5; Apply/rollback em R6; Backup/Restore em R7; polimento final/DPI/acessibilidade em R8.

## Executar

Clique em `Executar-WinSlim.bat` ou execute:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinSlimSuite.Fase7.ps1
```

## Teste

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\tests\Test-Fase7-R1-UI.ps1
```
