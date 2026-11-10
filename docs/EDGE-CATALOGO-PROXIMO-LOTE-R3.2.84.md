# Edge — próxima pendência executada: EDGE-003/004/005/006

21/10/2026. O levantamento do [catálogo completo](ESTADO-CATALOGO-EDGE-R3.2.84.md) identificou este lote com contrato Apply UI e regressão simulada existente, mas sem artefato real localizado. **O lote anterior EDGE-019/020/024/025 foi preservado, sem repetir seus testes.** Nenhum ajuste foi aplicado ao Edge do host. Incidente AV, auxiliares, gate completo e produção continuam bloqueados; limitador sem expansão.

## Isolamento e verificação automatizada

- Staging novo `logs/edge-vm-catalog-20261021/edge-priority-ed030006/`: **43 arquivos de texto**, mais manifesto, copiados de fontes atuais com SHA-256. Sem aplicativo, coletor Intel, fontes/geradores PresentMonHarness/MonitorHarness, gate ou teste EdgePrivacy. [Plano do lote](../logs/edge-vm-catalog-20261021/batch-plan.json).
- A seleção explícita `Core` usa somente EDGE-003/004/005/006 e `Test-Fase7-R3.2.84-EdgeBatch.ps1`. Definição pura em `tools/integration/EdgeVmBatch.ps1`; o nome do lote acompanha a reabertura pelo UAC. A opção histórica Privacy permanece disponível, mas não foi executada nesta rodada.
- **24 verificações comportamentais** passaram no coletor/seleção de lote: inventário, indisponibilidade, entradas inválidas, preservação de estado e separação entre os IDs. [Log](../logs/edge-vm-catalog-20261021/batch-evidence-fixtures.log). O cadastro continua com 22 suítes para o gate futuro; não houve novo bug de aplicação corrigido.
- **154 verificações EdgeBatch passaram na VM com I/O de Registro simulado.** [Log](../logs/edge-vm-catalog-20261021/core-fixtures.log). Isso é separado da execução real abaixo. Backend `-LibraryOnly`; nenhuma compilação/execução de auxiliar bloqueado, nenhuma execução do gate genérico.
- Revisão da compatibilidade nos documentos Microsoft: [EdgeShoppingAssistantEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/EdgeShoppingAssistantEnabled), [NewTabPageContentEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/NewTabPageContentEnabled), [PersonalizationReportingEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/PersonalizationReportingEnabled), [SleepingTabsEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/SleepingTabsEnabled). Reconhecimento da política não comprova efeitos em todos os perfis/contas nem economia de recursos.
- Conferência final: sintaxe PowerShell 5.1 dos quatro scripts alterados válida; inventário cruzado com catálogo/contratos/escopo; **323 evidências anteriores e 21 arquivos protegidos P9 intactos por hash**. Validação do cadastro/scripts/hashes pelo empacotador: **22 suítes únicas, 180 hashes**, sem gerar ZIP nem executar o gate. [Resumo](../logs/edge-vm-catalog-20261021/verification-summary.json).

## Execução real e evidências

VM `teste win-slim-win11`, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`, hostname TESTE, VirtualBox, Edge **155.0.4283.62**. Após o usuário entrar no desktop, execução com `Elevated=true`, sessão interativa 1, pelo fluxo normal de elevação. Nenhuma tarefa elevada foi instalada ou usada para contornar UAC.

| ID | Nome em edge://policy | DWORD aplicado | Valor no navegador | Fonte / escopo / nível / status |
| --- | --- | --- | --- | --- |
| EDGE-003 | EdgeShoppingAssistantEnabled | 0 | false | Plataforma / Dispositivo / Obrigatório / OK |
| EDGE-004 | NewTabPageContentEnabled | 0 | false | Plataforma / Dispositivo / Obrigatório / OK |
| EDGE-005 | PersonalizationReportingEnabled | 0 | false | Plataforma / Dispositivo / Obrigatório / OK |
| EDGE-006 | SleepingTabsEnabled | 1 | true | Plataforma / Dispositivo / Obrigatório / OK |

**Concluído no escopo backend/Registro, carregamento das políticas no navegador e Undo exato:**

- Backup **4df087e546404cfe8540cece012338db**, manifesto verificado, `CapturedCount=4`; SHA-256 do snapshot `63879552ef118394d93846b7c4049a1f181c5a27882228dfb25ef6e095726f6c`.
- Apply/Verify real: `verified=true`, `changed=4`, quatro `AppliedVerified`. A seleção e o preview usam as funções de produção; não há mock do leitor/escritor nessa execução.
- Undo real: `verified=true`, `changed=4`; backup de recuperação **75266a7f0c774cb6bf95514005350483**. Presença/tipo/dados iguais ao original: quatro valores **ausentes**, sem deixar zeros. Consulta independente HKLM/HKCU nas visões 32/64 idêntica à leitura inicial.
- [Captura aplicada](../logs/edge-vm-catalog-20261021/collection-224614614/evidence/applied-edge-policy.png), [antes](../logs/edge-vm-catalog-20261021/collection-224614614/evidence/before-edge-policy.png) e [depois do Undo](../logs/edge-vm-catalog-20261021/collection-224614614/evidence/restored-edge-policy.png), estas duas sem políticas definidas. Os quatro status foram classificados por **inspeção visual das capturas reais**. O extrator DOM continua parcial e não foi tratado como exportação completa nem como prova autônoma de status.
- [Resultado real](../logs/edge-vm-catalog-20261021/collection-224614614/evidence/status.json), [revisão visual](../logs/edge-vm-catalog-20261021/collection-224614614/policy-ui-review.json), [conferência independente após Undo](../logs/edge-vm-catalog-20261021/after-undo/guest-probe.json).
- **41 arquivos** de evidências/backups/journals copiados ao host e comparados por SHA-256 contra o inventário do convidado **antes** da restauração da baseline. [Comprovante de coleta](../logs/edge-vm-catalog-20261021/collection-224614614/collection-receipt.json).
- Após o Undo já comprovado e a conferência dos arquivos, desligamento normal ACPI e restauração de **WINSLIM_BASELINE**, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`. Estado final `poweroff`, sem desligamento forçado. [Comprovante](../logs/edge-vm-catalog-20261021/collection-224614614/baseline-restore-receipt.json).

Cliques de Apply/Undo no Win-Slim e os efeitos específicos em compras, conteúdo, personalização ou suspensão efetiva de guias **não foram exercitados**. A captura de políticas comprova carregamento e status nesse ambiente, sem aprovação dessas superfícies por inferência. Não se testou ausência de consumo de dados em conta diferente nem ganho de memória. Nenhuma aprovação de produção decorre deste lote.

## Próxima pendência e bloqueios

1. **EDGE-008/011/012/016:** revisão da vigência por versão/perfil antes do próximo lote real; já possuem contrato UI e 155 verificações históricas simuladas. O filtro atual só tem limite mínimo de versão; isso não comprova suporte atual de cada política.
2. **EDGE-001/002:** localizar evidência individual dos ciclos antigos referidos em READMEs; 47 verificações simuladas estão localizadas. Falta de rastreabilidade não autoriza reclassificar como aceite real nem repetir automaticamente um ciclo aprovado.
3. **17 IDs sem contrato UI:** revisão da semântica, compatibilidade e dependências (EDGE-007 depende de 006), implementação/liberação revisada e regressões; depois aceite real. Declaração no catálogo não é implementação UI concluída.
4. **Incidente/gate/produção:** amostra/hash original e resposta correlacionável do fabricante pendentes; resolução documentada antes de revisar bloqueio e executar gate completo fresco. CI e aceites físicos restantes continuam pendentes.

Há trabalho Edge independente restante; o limitador não foi retomado. Aplicativo, fontes visuais/estatísticas e protótipo permanecem preservados. Não foi criada candidata ou ZIP de aplicativo.
