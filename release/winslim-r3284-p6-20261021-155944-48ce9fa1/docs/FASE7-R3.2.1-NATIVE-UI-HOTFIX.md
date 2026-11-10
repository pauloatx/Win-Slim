# FASE 7 R3.2.1 — Nota técnica

A R3.2.1 nao amplia escopo funcional. E um hotfix de fundacao.

- UI: C# WPF compilado.
- Backend: PowerShell 5.1 aprovado.
- IPC: processo PowerShell persistente, JSON por linha.
- Mutacao: nenhuma nesta fase.
- DPI: Per-Monitor V2 solicitado via `SetProcessDpiAwarenessContext`, fallback `SetProcessDPIAware`.
- Build: `csc.exe` via response file UTF-8; log persistente de compilacao.
- Compatibilidade: Windows 10/11 + .NET Framework 4.8.

A R3.2 reprovada e mantida no pacote para auditoria; a R3.2.1 vive em `src/UI/Native/R3_2_1` e possui entrypoint/teste proprios.
