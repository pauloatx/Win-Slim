# Win-Slim R3.2.81 — preferências de interface do Edge

## Estado validado da base

A captura de 17/10/2026 às 23:23 confirmou Resultado: 0 na repetição da R3.2.80, incluindo REG-UI-001 e REG-EDGEBATCH-001. A execução anterior havia sido bloqueada porque o aplicativo estava aberto; o teste protege o executável em uso. A aplicação/restauração do lote EDGE-003/004/005/006 já foi conferida em backups da VM e da máquina real. Na máquina real, dois valores já existiam e dois foram alterados; os originalmente ausentes voltaram a ficar ausentes, conforme a consulta direta recebida. As quatro políticas foram vistas com status OK no Edge, e os snapshots recebidos tinham hashes corretos.

Essa aprovação vale para os cenários testados da R3.2.80. Esta build precisa de compilação e regressões próprias.

## Novo lote: quatro políticas opcionais

| ID | Política | DWORD desejado | Edge Stable mínimo |
|---|---|---:|---:|
| EDGE-008 | HideFirstRunExperience | 1 | 80 |
| EDGE-011 | SearchInSidebarEnabled | 2 | 110 |
| EDGE-012 | ShowRecommendationsEnabled | 0 | 89 |
| EDGE-016 | NewTabPageQuickLinksEnabled | 0 | 91 |

Todas usam HKLM\SOFTWARE\Policies\Microsoft\Edge, exigem administrador e Windows 10/11 cliente. A compatibilidade utiliza metadados locais do Edge Stable. Versões abaixo dos limites, detecção ausente/falha e falta de elevação excluem os ajustes. A confirmação é repetida antes de escrever; dados enviados pelo cliente não substituem a detecção local.

- EDGE-008 oculta a experiência de primeira execução e a tela inicial correspondente. Exige fechar e reabrir o Edge manualmente. Não redefine perfis existentes; não garante que um perfil já utilizado volte a exibir essa experiência após desfazer. A documentação também descreve padrões adotados no primeiro uso, incluindo a configuração inicial da nova guia; revisar essa preferência antes de aplicar.
- EDGE-011 desativa a pesquisa na barra lateral e permite a experiência de pesquisa tradicional nas superfícies correspondentes. O valor autorizado é o inteiro 2, não um booleano 0/1.
- EDGE-012 desativa recomendações de recursos e mensagens de assistência cobertas pela política. Não é um bloqueador geral de notificações de sites.
- EDGE-016 oculta os atalhos da nova guia e desabilita seu controle. Não apaga favoritos ou histórico. A nova guia corporativa de perfis Entra ID pode ter gerenciamento próprio.

A documentação das políticas possui limitações por tipo de perfil e, em alguns casos, divergência entre descrição e tabela de conta Microsoft. A gravação verificada no Registro não garante aceitação em todo perfil. Confira o status no navegador. Essas preferências não prometem ganho de FPS.

O fluxo continua explícito: importar seleciona; revisão mostra os destinos; backup completo e verificado antecede toda escrita; leitura após escrita; idempotência; recuperação em falha; restauração da existência, tipo e valor reais anteriores. O Win-Slim não encerra o Edge automaticamente. O catálogo permanece com 230 IDs, presets-base e arquivos anteriores preservados.

## Testar sem repetir os lotes anteriores

1. Extraia em pasta nova. FECHE o Win-Slim antes de executar Validar-Regressoes.bat e mantenha fechado até terminar. São treze suítes; aguarde Resultado: 0. Se houver falha, envie a pasta logs/regressao-... e não prossiga para a aplicação.
2. Abra Executar-WinSlim-R3.2.81.bat como administrador. Em Personalizado, importe exatamente Teste-Lote-Edge-R3.2.81.json. Confirme quatro IDs: EDGE-008, EDGE-011, EDGE-012 e EDGE-016. Os arquivos de teste das versões antigas permanecem identificados por suas versões.
3. Revise os quatro destinos e itens excluídos. Use Criar backup e aplicar. Anote o backup Antes da aplicação deste lote.
4. Salve o trabalho do navegador, feche o Edge e reabra manualmente. Na mesma máquina (VM e máquina real têm Registros separados), abra edge://policy, clique Recarregar políticas e confira os quatro nomes/valores/status. A versão 110+ é necessária para aceitar os quatro contratos deste lote.
5. Confira os atalhos da nova guia e as opções disponíveis de pesquisa lateral/recomendações. O teste de EDGE-008 não exige apagar ou recriar um perfil; em perfis já utilizados, confira a aceitação da política e registre que a primeira execução não foi reproduzida.
6. Em Backup / Restauração, selecione o backup Antes da aplicação deste lote e use Restaurar tudo. Selecione a cópia correta: Antes da restauração guarda o estado aplicado e permite desfazer a própria restauração.
7. Feche/reabra o Edge manualmente e recarregue as políticas. Valores originalmente existentes devem permanecer conforme salvos; originalmente ausentes devem desaparecer do Registro. Se a página ainda mostrar os valores, a tela isolada não prova falha da restauração; confira o Registro na mesma máquina.
8. Envie a pasta de regressões, as capturas de políticas após aplicar/restaurar e os backups. Não precisa repetir a aplicação manual dos lotes UI, QoL ou EDGE-003 a EDGE-006 já concluídos.

## Regressões e limites de validação

REG-EDGENEXT-001 cobre os quatro contratos, incluindo o DWORD enumerado 2, adulteração de campos/hive/permissão/reinício, limites imediatamente abaixo/no mínimo por política, versões do Windows, Server, falha de detecção e falta/perda de elevação. Executa Apply/Verify/Undo individualmente e em lote com IO simulado, backup em disco, estados existentes/ausentes, idempotência, falha de leitura/backup, recuperação após cada escrita e rejeição de snapshot incompleto. As doze suítes anteriores continuam exigidas.

Neste ambiente foram executados os seis testes Python do empacotador e conferidos JSON/XAML, cadastro único, contratos estáticos, hashes e preservação da base. PowerShell 5.1, .NET Framework e WPF não estão disponíveis: compilação e treze suítes Windows da R3.2.81 estão PENDENTES. Python é ferramenta do desenvolvedor, não requisito do aplicativo.

## Fontes oficiais revisadas

- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/hidefirstrunexperience
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/searchinsidebarenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/showrecommendationsenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/newtabpagequicklinksenabled
