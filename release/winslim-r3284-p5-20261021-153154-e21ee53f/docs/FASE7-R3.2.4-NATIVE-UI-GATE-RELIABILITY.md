# FASE 7 R3.2.4 — Gate Reliability

## Diagnóstico
A R3.2.3 compilou a Native UI e passou o self-test real. As duas falhas restantes eram do próprio mecanismo de verificação:

- a expressão usada pelo gate para reconhecer a invocação do compilador não correspondia de forma robusta ao texto real do script;
- `Set-Content` recebia uma pipeline vazia quando o `csc.exe` encerrava com sucesso sem emitir texto, portanto nenhum arquivo de log era criado.

## Decisão
Não alterar backend, XAML, PresetRuntime ou semântica dos overlays para corrigir um problema de teste/build observability.

A R3.2.4 aplica somente:
- array splatting explícito para argumentos nativos;
- log preflight persistente;
- registro de ExitCode;
- assertions menos frágeis.

Isso mantém o hotfix pequeno e auditável.
