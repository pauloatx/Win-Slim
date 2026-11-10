# Win-Slim R3.2.80 — lote Edge

Base: R3.2.79, com onze suítes aprovadas nos logs do usuário. No ciclo QoL recebido, quatro valores de QOL-003 e QOL-012 foram cobertos: um alterado, três já configurados. A restauração terminou com um valor recuperado e quatro snapshots íntegros (incluindo o lote UI anterior). QOL-008 ficou excluído por compatibilidade local; não foi aplicado nem aprovado em execução real nessa máquina.

## Quatro políticas liberadas para revisão explícita

| ID | Política | Valor DWORD | Edge mínimo |
|---|---|---:|---:|
| EDGE-003 | EdgeShoppingAssistantEnabled: desativar recursos automáticos de compras | 0 | 87 |
| EDGE-004 | NewTabPageContentEnabled: desligar conteúdo Microsoft na nova guia | 0 | 91 |
| EDGE-005 | PersonalizationReportingEnabled: desativar envio de dados para personalização coberto pela política | 0 | 80 |
| EDGE-006 | SleepingTabsEnabled: manter guias ociosas em suspensão | 1 | 88 |

Destino fixo: HKLM\SOFTWARE\Policies\Microsoft\Edge. Todas exigem administrador, Windows 10/11 cliente e Edge Stable instalado com metadados locais confirmados. A versão do navegador enviada por um cliente não autoriza escrita. Sem confirmação local, o ajuste fica excluído. Edição Home do Windows não é excluída por si só dessas políticas do navegador.

A aceitação depende do perfil e das regras do Edge. A documentação de EDGE-003, EDGE-004 e EDGE-006 indica restrições em perfis conectados a conta Microsoft; EDGE-005 não está disponível para contas infantis ou empresariais. Há também ressalvas entre descrição e tabela de perfis na página oficial de nova guia. Por isso esta build não declara efeito garantido para todo perfil. O motor confirma a escrita no Registro e preserva o motivo das exclusões de versão/permissão; não inspeciona nem altera credenciais ou dados de perfil.

Guias em suspensão já são habilitadas por padrão no Edge; EDGE-006 fixa a preferência por política. Não implica economia adicional garantida. A desativação de compras/personalização não é promessa de aumento de FPS. Não são alterados antivírus, atualizações, segurança de navegação, histórico ou arquivos do navegador.

Cada contrato fixa ID, hive, caminho, nome, tipo, valor, risco e escopo de reinício. Backup completo e verificado antes da primeira escrita; leitura após escrever; idempotência; recuperação em falha; restauração do estado original incluindo ausência. Não há fechamento automático do Edge. As políticas EDGE-001/002 e todos os ajustes anteriores mantêm seus contratos.

## Teste conjunto

1. Extraia em pasta nova e execute Validar-Regressoes.bat. Aguarde Resultado: 0. São doze suítes nesta build; o novo lote usa IO simulado nos testes automatizados.
2. Abra Executar-WinSlim-R3.2.80.bat como administrador. Em Personalizado, importe exatamente Teste-Lote-Edge-R3.2.80.json. São quatro IDs: EDGE-003, EDGE-004, EDGE-005 e EDGE-006.
3. Revise os itens aceitos/excluídos e use Criar backup e aplicar. Em Edge atualizado e com elevação, são quatro valores; itens incompatíveis não devem ser forçados.
4. No Edge, abra edge://policy, clique Recarregar políticas e confira Nome, Valor, Escopo e Status de cada uma. Salve/capture o estado exibido. Registro verificado com política ignorada ou erro no navegador não comprova efeito aplicado ao perfil.
5. Confira compras, conteúdo da nova guia e as opções de privacidade/desempenho conforme disponíveis no perfil. Guias precisam ficar ociosas para entrar em suspensão; não há um tempo de economia garantido.
6. Em Backup / Restauração, selecione a cópia Antes da aplicação deste lote e use Restaurar tudo. Depois recarregue edge://policy ou feche/reabra o Edge manualmente para conferir o retorno ao estado anterior. Uma política originalmente existente é restaurada ao seu valor anterior; uma originalmente ausente é removida.
7. Envie logs/regressao-..., capturas do resultado/edge://policy e os backups deste ciclo. Não precisa repetir manualmente os lotes UI ou QoL já concluídos.

## Regressão

REG-EDGEBATCH-001 testa cada contrato, troca de hive, adulteração de operações/permissão, versões imediatamente abaixo e no mínimo, Windows antigo/Server, falta de metadados e elevação. Exercita os quatro ajustes individualmente e juntos: backup em disco, Apply/Verify/Undo, estados originalmente ausentes/existentes, idempotência, falhas de leitura/backup, perda de compatibilidade/elevacão após a revisão, recuperação após cada escrita e rejeição de snapshot incompleto. As onze suítes anteriores continuam exigidas.

Validação local disponível: seis testes Python do empacotador, JSON/XAML, hashes e preservação da base. PowerShell 5.1, .NET Framework e WPF não estão disponíveis neste ambiente: compilação e doze suítes desta R3.2.80 estão PENDENTES no Windows. Python não é requisito para o usuário. A aprovação da R3.2.79 não é transferida automaticamente a esta build.

## Fontes primárias revisadas

- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/edgeshoppingassistantenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagecontentenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/personalizationreportingenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/sleepingtabsenabled
