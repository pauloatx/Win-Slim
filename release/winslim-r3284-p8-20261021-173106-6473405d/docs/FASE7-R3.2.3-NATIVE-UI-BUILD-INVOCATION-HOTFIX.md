# FASE 7 R3.2.3 — correção de invocação do csc.exe

## Falha da R3.2.2
A R3.2.2 tentou desativar o `csc.rsp` adicionando `/noconfig` ao próprio response file. O compilador emitiu `CS2023` e ignorou a opção. O `csc.rsp` padrão continuou ativo e as referências padrão entraram em conflito com as referências explícitas, gerando `CS1703`.

## Regra correta
`/noconfig` precisa ser argumento direto do compilador:

```text
csc.exe /noconfig @arquivo.rsp
```

e **não** uma linha dentro de `arquivo.rsp`.

## Escopo
Nenhuma mudança no backend, PresetRuntime, Planner, Transaction, Providers, catálogo ou semântica da UI. Apenas build/invocação, versionamento do host e gate de regressão.
