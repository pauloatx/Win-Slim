# Win-Slim R3.2.74 — primeiro lote do Microsoft Edge

Base: R3.2.73 validada pelo usuário. Catálogo, presets e interface aprovados preservados.

## Ajustes liberados
- EDGE-001: StartupBoostEnabled=0, desativa Startup Boost. Requer Edge Stable instalado, versão 88 ou posterior.
- EDGE-002: BackgroundModeEnabled=0, desativa execução em segundo plano após fechar o navegador. Requer versão 77 ou posterior.

Os destinos são HKLM\SOFTWARE\Policies\Microsoft\Edge, DWORD 0. Exigem aplicativo elevado e afetam todos os usuários do computador. O backend detecta Windows cliente 10/11 e lê metadados do msedge.exe instalado em caminhos conhecidos. Se não puder confirmar a compatibilidade ou elevação, exclui esses ajustes da aplicação com motivo. A checagem é repetida na aplicação; dados de versão e destino enviados pelo cliente não autorizam escritas.

A revisão informa o escopo de máquina. Antes de escrever, o motor salva e verifica um backup completo; Apply faz read-back, reaplicação não escreve valores iguais e falhas provocam tentativa de recuperação verificada. Backup / Restauração devolve existência, tipo e valor originais, individualmente ou de todo o backup selecionado.

A verificação automática confirma os valores no Registro. Não confirma que o navegador aceitou a política ou que nenhum outro gerenciamento a sobrescreveu. Feche e reabra o Edge manualmente, acesse edge://policy, recarregue as políticas e confira nome, valor false/0 e status. O aplicativo não encerra o navegador nem suas sessões. Desativar Startup Boost pode tornar a primeira abertura do Edge mais lenta; a finalidade é reduzir pré-inicialização e atividade residente. Não há promessa de ganho de FPS.

## Teste na VM
1. Extraia em uma pasta nova e execute Validar-Regressoes.bat. Aguarde Resultado: 0.
2. Abra Executar-WinSlim-R3.2.74.bat como administrador, usando a mesma conta do Windows que será testada.
3. Em Personalizado, selecione somente EDGE-001 e EDGE-002 (categoria Microsoft Edge). Confira os IDs em Aplicar selecionados → Revisar aplicação real.
4. Use Criar backup e aplicar. Se já estiverem configurados, isso é esperado: nenhuma nova escrita será necessária.
5. No Edge, abra edge://policy e confira StartupBoostEnabled e BackgroundModeEnabled. Registre uma captura dessa página para validar que o Edge aceitou as políticas.
6. Em Backup / Restauração, selecione Antes da aplicação desta execução e use Restaurar tudo. Essa ação restaura apenas os ajustes cobertos daquela cópia. Confira novamente as políticas no navegador.
7. Envie logs/regressao-..., logs/ui-native-r3.2.74.log e o backup correspondente de Backups/UI. Faça primeiro o ciclo na VM; depois repetimos na máquina real.

## Regressão e limites da validação
REG-EDGE-001 usa o catálogo e o motor reais com IO de Registro simulado: verifica contratos adulterados, hive, versões mínimas, ausência do Edge, Windows não compatível, falta de administrador, repetição da checagem, backup completo em disco antes das escritas, token, Apply/Verify/Undo, idempotência e recuperação após falha parcial.

A execução local de PowerShell/.NET Framework/WPF não está disponível neste ambiente. Foram conferidos XML/XAML, JSON, hashes, destinos do catálogo e preservação das versões anteriores. Os testes novos e a aplicação real aguardam Windows. A aprovação da R3.2.73 não é atribuída à R3.2.74.

## Fontes oficiais consultadas
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/startupboostenabled
- https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/backgroundmodeenabled
- https://learn.microsoft.com/en-us/deployedge/configure-microsoft-edge
