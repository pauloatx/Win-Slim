# Restauração transacional do gate — R3.2.84

## Âmbito

Correção de `WS-BUG-0007`: o gate local publicava o build de validação sobre o executável aceite, tornando a segunda execução impossível sem restauro manual. A correção é N3 porque o pipeline restaura ficheiros operacionais, mas não toca em Apply, Verify, Undo, registo, serviços, tarefas, energia ou rede.

## Desenho

1. Antes do gate, `tools/validation/NativeBuildRestoration.ps1` confirma que o EXE e a configuração correspondem ao baseline e que o cache de build corresponde a ambos.
2. Os três ficheiros aceites são guardados como blobs GZip/Base64 identificados por SHA-256 dentro da pasta da candidata. Não é criado um segundo executável na árvore.
3. O gate pode terminar com sucesso ou falha; a restauração ocorre sempre no `finally`.
4. Todos os ficheiros são preparados e verificados antes da publicação. Se uma substituição falhar a meio, as substituições anteriores são revertidas em ordem inversa.
5. O recibo da candidata regista os hashes aceites restaurados e as identidades separadas do build de validação.
6. Uma falha de captura, adulteração, ausência ou path fora da raiz falha fechada antes de escrever nos destinos.

## Regressão

`REG-RESTORE-001` usa apenas uma fixture inerte em `logs/`. Verifica 20 comportamentos: captura, restauração, cache, ficheiros alheios, propagação de falha, rollback de falha parcial, adulteração, ausência, path externo e divergência de baseline.

- Teste vermelho: `logs/reg-restore-001-red.log` — exit 1 porque o helper transacional ainda não existia.
- Teste verde: `logs/reg-restore-001-green.log` — 20 verificações, exit 0.

## Estado de validação

A correção foi validada. Duas candidatas oficiais consecutivas passaram 32/32 suítes, incluindo build e self-test WPF, e repuseram o estado aceite sem intervenção manual:

- `logs/candidato-r3284-20261112-040720-434-75e72501`: `TechnicalPassed=true`; build de validação `43f5036d...`; EXE aceite restaurado `62eb3819...`.
- `logs/candidato-r3284-20261112-041152-998-bd4d5e98`: `TechnicalPassed=true`; build de validação `afec5074...`; EXE aceite restaurado `62eb3819...`.

`WS-BUG-0007` está `corrigido`. `ProductionApproved=false` e a distribuição continua em hold.
