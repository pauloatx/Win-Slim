# FASE 7 R3.2.2 — Native UI Build Hotfix

## Diagnostico
O build R3.2.1 falhou com `CS1703` para `System.Web.Extensions`, `System.Xml`, `System` e `System.Core`. A causa e a importacao simultanea de uma referencia pelo `csc.rsp` e de outra referencia explicita com a mesma identidade de assembly.

## Estrategia
A R3.2.2 usa o `csc.exe` do .NET Framework com:

- `/noconfig` para impedir a importacao automatica do `csc.rsp`;
- referencias explicitas obtidas do runtime .NET Framework ja carregado;
- response file UTF-8 sem BOM para evitar problemas de quoting do PowerShell 5.1;
- log integral do compilador;
- copia do `.exe.config` somente apos build bem-sucedido.

Essa abordagem reduz dependencia do estado do GAC/csc.rsp e torna a entrada do compilador deterministica.

## Escopo
Nao altera Planner, Transaction, Preview, PresetRuntime, Providers, catalogos ou presets.
