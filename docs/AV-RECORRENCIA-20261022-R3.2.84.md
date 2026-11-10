# AV-20261021-001 — recorrência na validação autorizada de 22/10/2026

**A avaliação de falso positivo do responsável pelo projeto foi registrada e preservada. Não é um parecer do Kaspersky.** O usuário confirmou atualização das bases, teste próprio aprovado e autorização para compilar/executar localmente os auxiliares e retomar o gate, sem liberar produção. [Decisão e limites](DECISAO-RESPONSAVEL-AV-20261021-001.md).

## Nova evidência observada

Em **22/10/2026 às 06:58:39**, o Kaspersky registrou novamente `VHO:Trojan-PSW.Win32.Disco.gen`, por análise heurística/proteção na nuvem. O caminho correlacionado em **HvmMonitorTask e File_Monitoring** é:

`C:\Users\Administrator\AppData\Local\Temp\winslim-pm-regression-3b9cadb7c8504a0183e958f028c1b4e9\PresentMonHarness.exe`

- **SHA-256 desta nova compilação:** `b1cd7b2617e6cda191d3d01b053ecca38316b26dfd9caced2093f0438236e1d6`.
- Tamanho: **51.712 bytes**; compilador retornou 0. O hash, compilador e quatro fontes foram registrados **antes da tentativa de execução**, às 09:58:39.441 UTC, pelo fluxo de proveniência existente.
- A tentativa de iniciar retornou **Acesso negado**. O registro de falha conserva a indisponibilidade da leitura posterior, sem apagar o hash anterior. Metadados do arquivo ainda estavam visíveis; leitura do conteúdo foi negada/bloqueada. Não foi contornado o bloqueio, copiado o binário protegido ou restaurada quarentena.
- O código-fonte do auxiliar não foi alterado ou renomeado para evitar detecção. A correlação comprova novo evento no objeto recém-gerado, sem demonstrar a regra interna que causou o alerta ou estabelecer um parecer independente de malware/falso positivo.
- **Esse hash não pertence à amostra de 21/10 às 15:03:27**, cujo SHA-256 continua desconhecido.

[Correlação com relatórios e proveniência](../logs/av-owner-review-20261022/recurrence-correlation.json), [registro pré-execução](../logs/av-owner-review-20261022/provenance/artifact-f1497f0ec7c540c5a0e2a153814bdb76.json), [falha](../logs/av-owner-review-20261022/provenance/artifact-f16e390393e14f2dafe142c37413115d.json). Os relatórios integrais contêm dados locais e não foram enviados a ninguém.

## Resultado técnico, sem aprovação parcial

1. Primeira rodada parou na suíte nativa: três catálogos Edge já revisados divergiam do hash histórico; o teste de Registro em chave HKCU descartável não tinha acesso no ambiente restrito. Falha preservada. O teste HKCU passou fora da restrição (**12 verificações**), sem ajuste do catálogo.
2. A validação histórica passou a exigir originais preservados pelo hash antigo e uma transição explícita para os hashes atuais revisados. Auditoria confirmou apenas metadados de 17 IDs Edge, sem mudar operações ou a baseline histórica R4. **19 verificações comportamentais** cobriram transição válida, adulteração, original ausente e identidade incorreta. Não houve substituição cega dos hashes antigos nem repetição de políticas reais na VM.
3. Segunda rodada: **15 suítes passaram, REG-PRESENTMON-001 falhou e nove suítes não foram executadas**, de 25 cadastradas. Compilação e self-test WPF passaram dentro da suíte nativa. O gate completo **não passou**. A política controlada interrompeu na primeira falha e **MonitorHarness não foi compilado/executado nessa rodada**.

Relatórios completos: [primeira rodada](../logs/regressao-20261022-095241-333-1c6a7d59/resultado.json), [segunda rodada](../logs/regressao-20261022-095648-468-e6958805/resultado.json). Diagnósticos das duas execuções preservados separadamente; são ZIPs de logs, não candidata de distribuição.

O relatório de atualização do Kaspersky registra tarefa iniciada às 05:33:33 e concluída às **05:34:16** em 22/10. Isso corrobora atualização anterior à tentativa, sem provar erro de base, versão exata da base ou resolução da detecção. Consultas STATUS antes/depois mostram proteção em execução. Nenhum comando alterou o antivírus, criou exclusão ou refez o auxiliar sob outro nome.

## Estado e próximo passo

A autorização local condicionada foi **suspensa após a recorrência**, conforme a condição registrada antes do teste. Política voltou a `investigating`, retendo geração/execução da família, gate completo, publicação e produção. O registro de avaliação do responsável permanece íntegro; não houve laudo atribuído ao fabricante.

Para retomar a família, primeiro tratar a nova detecção com esse hash e seus registros: análise do fabricante/atualização aplicável ou correção de código justificada pela evidência, com regressão. Não reexecutar apenas para verificar se o alerta desapareceu. Qualquer nova decisão de escopo deve considerar esta ocorrência; não reutilizar a autorização anterior como liberação automática.

Etapas independentes AMD permanecem permitidas; leitura física NVIDIA segue pendente por falta de hardware, sem instalar driver. Aceites Edge e visual anteriores preservados. CI, interação pela UI, efeitos condicionais e aceites físicos restantes continuam pendentes. Produção não aprovada.
