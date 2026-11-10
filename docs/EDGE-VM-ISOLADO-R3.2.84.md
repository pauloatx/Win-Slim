# Edge — prioridade imediata, teste isolado da família bloqueada

21/10/2026. EDGE-019/020/024/025 têm prioridade sobre SDK/ABI/adaptador do limitador, por instrução expressa do usuário. O protótipo já concluído fica preservado, com expansão pausada. Incidente AV-20261021-001, auxiliares, gate completo e produção permanecem bloqueados.

## Dependências verificadas

O teste `Test-Fase7-R3.2.84-EdgePrivacy.ps1` importa `WinSlim.UiBridge.ps1 -LibraryOnly`, usa o catálogo/revisões locais, planner, backup, contratos de Registro e restauração. Substitui as leituras/escritas por fixtures; **153 verificações passaram na VM**, sem aplicar políticas reais. Não chama `PresentMonHarness`, `MonitorHarness`, seus geradores, `Iniciar-Validacao`, `Validar-Regressoes` ou build da UI.

O fluxo real isolado usa as mesmas funções de produção para criar plano/prévia/revisão, `Invoke-WinSlimRegistryApply`, backup com manifesto/hash, `New-WinSlimRestorePreview` e `Invoke-WinSlimBackupRestore`. Não substitui o leitor/escritor de Registro por mocks. O aceite é automatizado pelo backend, sem declarar que os cliques de aplicação na UI foram testados.

O primeiro staging contém **41 arquivos de texto** e o corrigido **42** (`.ps1`/`.json`), incluindo o helper puro de coleta; não contêm aplicativo, coletor Intel, fontes/geradores dos dois auxiliares ou gate. Manifestos com SHA-256 em `logs/edge-vm-20261021-priority/`. A inicialização de contexto do backend também pode consultar inventário e compilar a interop de topologia de CPU do próprio projeto; isso é distinto dos auxiliares proibidos e não aplica afinidade/otimização. Nenhum source/gerador PresentMon/Monitor foi incluído ou chamado.

**Não usar o controlador genérico antigo:** `Test-WinSlimVmCandidate.ps1` chama `Iniciar-Validacao.bat /ci` e portanto depende do gate bloqueado. O runner genérico externo também copia toda a pasta Builds, incluindo candidatas antigas. A execução desta rodada usa staging textual restrito, diretório próprio e scripts `Inspect-WinSlimEdgeVm.ps1`, `Invoke-WinSlimEdgeIsolatedVm.ps1` e `Test-WinSlimEdgeRealVm.ps1`; nenhum controlador genérico foi executado.

## Ambiente observado e elevação

VM `teste win-slim-win11`, UUID `b71b4588-2e83-461c-9585-64ee77b9c851`, hostname `TESTE`, modelo VirtualBox. Antes do boot: desligada, snapshot identificado `WINSLIM_BASELINE`, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`. Esse marcador não substitui o backup dos valores atuais.

Edge Stable observado: **155.0.4283.62**. Consulta somente leitura em HKLM/HKCU, visões 64/32: quatro valores ausentes; HKLM tem chave Edge vazia, HKCU não tem a chave. A consulta da tarefa `WinSlimLabElevado` retornou `CmdletizationQuery_NotFound_TaskName`. GuestControl iniciou sem elevação. Após o boot apareceu sessão interativa 1/Explorer; foi solicitado **UAC normal**, com fornecedor Microsoft Windows, sem instalar tarefa ou alterar UAC/AV. O usuário confirmou disponibilidade para entrar e aprovar. Só o token administrativo real permite chegar à aplicação.

A primeira tentativa das fixtures encontrou a ExecutionPolicy padrão da VM. A repetição usa `-ExecutionPolicy Bypass` **somente nos processos de laboratório**, como o controlador existente, sem alterar política persistente, UAC ou antivírus. Não houve retry/renomeação de auxiliar AV. As fixtures passaram antes de solicitar o teste real.

## Escopo do aceite e evidências exigidas

| ID | HKLM\SOFTWARE\Policies\Microsoft\Edge | Estado aplicado esperado |
| --- | --- | --- |
| EDGE-019 | UserFeedbackAllowed | DWORD 0 |
| EDGE-020 | MicrosoftEdgeInsiderPromotionEnabled | DWORD 0 |
| EDGE-024 | AlternateErrorPagesEnabled | DWORD 0 |
| EDGE-025 | SearchSuggestEnabled | DWORD 0 |

O roteiro registra estados originais, preview e revisão, cria/verifica backup antes da escrita, aplica somente esses quatro destinos, verifica e reabre **uma instância própria do Edge com perfil de teste**. A coleta de `edge://policy` usa CDP em loopback dentro da VM e capturas do próprio navegador; não abre porta/firewall externo nem acessa o Edge do host. Reabrir contempla a exigência de reinício de UserFeedbackAllowed. A instância de teste é encerrada pelo seu endpoint; não se mata globalmente processos Edge.

O `finally` tenta Undo pelo backup original e compara presença/tipo/dados de cada valor, inclusive ausência. Captura também a página de políticas após restaurar. Falha e evidências ficam registradas; nenhum resultado parcial significa aceite integral. Undo por snapshot da VM não substitui esse teste de restauração do aplicativo.

Antes de qualquer restauração de `WINSLIM_BASELINE`, copiar evidências e backups para o host em coleção nova, conferindo todos os hashes contra inventário do convidado. A restauração da baseline só pode ocorrer após essa coleta, com o processo do teste concluído. Se a coleta falhar, conservar estado da VM e registrar o bloqueio.

## Diagnóstico das políticas com erro

Na baseline observada, o Registro não contém políticas configuradas que reproduzam os erros anteriores. Sem exportação/captura anterior com nome e mensagem, não é possível atribuir causa ao erro histórico. A rodada deve distinguir isso de erros eventualmente vistos após Apply real.

Os quatro nomes/tipos/caminhos coincidem com os contratos oficiais. Três políticas por perfil não se aplicam a perfil conectado a conta Microsoft pessoal; UserFeedbackAllowed tem regras diferentes e requer reinício. Assim, valor verificado no Registro não basta para concluir aceitação/efeito no navegador. Fontes oficiais: [UserFeedbackAllowed](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/UserFeedbackAllowed), [MicrosoftEdgeInsiderPromotionEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/MicrosoftEdgeInsiderPromotionEnabled), [AlternateErrorPagesEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/AlternateErrorPagesEnabled), [SearchSuggestEnabled](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/SearchSuggestEnabled).

Conferir em cada captura: nome, valor, origem, escopo, nível e status/erro. Política reconhecida não demonstra sozinha todos os efeitos de feedback/promoção/rede; registrar quais superfícies foram efetivamente observadas. Não corrigir histórico supondo que houve erro de tipo, versão ou conta sem evidência.

## Resultado real e alcance do aceite

**Lote solicitado concluído no escopo de aplicação, carregamento no navegador e restauração:** VM TESTE, Edge **155.0.4283.62**, sessão interativa 1 e `Elevated=true` após aprovação humana do UAC. Resultado `Completed`, sem erros no roteiro.

- Backup original **af09d54a8c4147fb87b33b591019ffee**, manifesto verificado, quatro operações cobertas e `CapturedCount=4`. SHA-256 do snapshot: `c9e8c730285ed9a1c8cce0533910402745dfcc3b3faa1fb25828950b59b29f72`.
- Apply/Verify real: `verified=true`, `changed=4`, quatro itens `AppliedVerified`. Todos os valores são DWORD 0 após a escrita.
- Inspeção visual da captura real de `edge://policy`: **AlternateErrorPagesEnabled, MicrosoftEdgeInsiderPromotionEnabled, SearchSuggestEnabled e UserFeedbackAllowed** com valor **false**, fonte **Plataforma**, escopo **Dispositivo**, nível **Obrigatório**, status **OK**. Nenhuma das quatro apresenta erro nessa execução.
- Undo pelo backend real: `verified=true`, `changed=4`; backup de recuperação **360a7cfe33fc46139d8770c9b82c986d**. Presença/tipo/dados dos quatro valores correspondem exatamente ao original: **ausentes**, não zeros mantidos. Consulta independente posterior confirma HKLM/HKCU nas duas visões iguais à leitura inicial.
- Capturas antes e após Undo mostram **“Nenhuma política definida”**. A restauração foi comprovada antes de restaurar o snapshot da VM.
- **40 arquivos** de evidência/backup/journals copiados para `logs/edge-vm-20261021-priority/collection-222515842/`, com hashes conferidos contra inventário do convidado **antes da restauração da baseline**. Evidências de falhas anteriores também foram preservadas em coleções separadas.
- Depois de conferir novamente esses 40 hashes e o Undo exato, a VM foi desligada normalmente por ACPI e restaurada para **WINSLIM_BASELINE**, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`. Estado final **poweroff**. Comprovante: `collection-222515842/baseline-restore-receipt.json`. Não houve desligamento forçado.

Capturas: [aplicado](../logs/edge-vm-20261021-priority/collection-222515842/evidence/applied-edge-policy.png), [original](../logs/edge-vm-20261021-priority/collection-222515842/evidence/before-edge-policy.png), [restaurado](../logs/edge-vm-20261021-priority/collection-222515842/evidence/restored-edge-policy.png). [Resultado](../logs/edge-vm-20261021-priority/collection-222515842/evidence/status.json), [comprovante de coleta](../logs/edge-vm-20261021-priority/collection-222515842/collection-receipt.json).

O extrator DOM registrou URL/título/botões, mas `text` vazio e `rows=[]` nessa versão da página. Portanto, **a classificação dos quatro status foi feita pela inspeção visual das capturas PNG reais**, não por esse JSON parcial ou por simulação. Não se repetiu uma aplicação já verificada somente para obter outro formato de exportação. Cliques na UI do Win-Slim e efeitos específicos de feedback/promoção/rede não foram exercitados; não recebem aprovação por inferência. A causa dos erros históricos permanece indeterminada sem o registro anterior, embora os quatro erros não tenham sido reproduzidos.

## Falhas de infraestrutura corrigidas e regressões

1. O primeiro UAC encerrou sem aprovação; nenhuma política foi escrita. A tarefa elevada ausente não foi criada nem usada como contorno. Após exibir/localizar a VM, o usuário aprovou o UAC e a execução confirmou o token administrativo real.
2. O coletor tratava array JSON do PowerShell 5.1 como um elemento e selecionava `Backups` mesmo quando a pasta não existia. A tentativa ficou preservada; o teste comportamental falhou antes da correção e passou depois. O novo parser valida/enumera registros e recusa inventários vazios, duplicados, caminhos externos/traversal/streams e hash inválido.
3. A primeira tentativa elevada encontrou apenas a aba inicial `edge://newtab/`, embora CDP estivesse disponível. Parou **antes do Apply**. Corrigido para selecionar uma página real e navegar explicitamente a `edge://policy/`, conferindo a URL. Teste comportamental reproduziu a falha antes e passou depois; a execução real corrigida usou staging novo, preservando a anterior. Somente a instância de Edge desse teste falho foi encerrada pelo seu endpoint, após conferir o perfil.

`REG-VMEDGE-001`: **18 verificações comportamentais passaram**, sem VM/Edge/auxiliares no teste de unidade; duas falhas anteriores registradas em `evidence-parser-before.log` e `cdp-target-before.log`. Cadastro atual: **22 suítes exigidas para futuro gate**, que permanece bloqueado. Nenhuma aprovação do gate completo ou da produção decorre deste lote. O Edge da máquina principal não foi aberto/configurado por esses roteiros.
