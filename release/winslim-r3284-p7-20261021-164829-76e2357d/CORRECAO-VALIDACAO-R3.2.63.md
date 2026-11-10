# R3.2.63 — correção do teste de reaplicação

O log da VM encerrou a R3.2.62 com resultado 1: a atribuição de `Current` falhou logo após as verificações do primeiro lote, no preparo da reaplicação. A cópia do array por JSON foi substituída por uma fábrica de registros explícitos, cada um com `Current` e `Desired` independentes. Não foi removido nem enfraquecido o teste de idempotência: ele ainda exige zero escritas e cinco estados já configurados.

Há quatro verificações adicionais da estrutura das duas coleções e da preservação dos estados originais. Um erro inesperado passa a imprimir a posição e a pilha completas.

O motor e o layout da R3.2.62 foram preservados, exceto as identificações da revisão. O teste de escrita real usa apenas uma chave HKCU descartável. A aprovação no Windows depende de executar novamente `Validar-Aplicacao-Registro-R3.2.63.bat` e conferir o resultado 0.
