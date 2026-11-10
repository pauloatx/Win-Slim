# Win-Slim R3.2.78 — relatório nativo e categoria unificada

Base: R3.2.77. Os arquivos enviados em 17/10/2026 confirmam duas execuções da regressão com nove suítes aprovadas, 325 verificações do lote UI e aplicação/restauração verificadas de quatro ajustes na máquina testada. UI-023 e UI-024 foram excluídos por compatibilidade; não foram aplicados nesse teste. Duas operações mudaram e seis já estavam configuradas. Os quatro snapshots recebidos têm SHA-256 correto.

## Mudanças
- A tela de conclusão exibe um relatório legível, agrupado por ID. Os valores de tema e mouse aparecem dentro do mesmo ajuste, com contagens separadas de valores aplicados, já configurados e ajustes distintos.
- Exclusões e seus motivos aparecem no relatório. Resultado não verificado, erro, contagem divergente, status desconhecido ou recuperação incompleta exigem revisão; não recebem indicação de sucesso no relatório.
- Botão Exportar relatório salva HTML independente, com detalhes por ajuste, tema claro/escuro e sem scripts ou recursos externos. Conteúdo variável é escapado. O botão fica desabilitado até existir resultado e durante operações. A exportação não pode sobrescrever arquivos da pasta Backups.
- O outcome.json e os logs originais são preservados. Não há Python obrigatório no aplicativo: o formatador integrado é C#/.NET Framework.
- A prévia agora reúne UI / QoL e UI/QoL numa única categoria, somando quantidades e reinícios e mantendo o maior risco. Os nomes originais no catálogo permanecem intactos.
- O subtítulo da revisão é genérico para políticas Windows e Edge.

A apresentação nativa está integrada ao fluxo após aplicar. Exportar HTML usa esse resultado da sessão. Não altera operações de Apply, Verify, Undo, contratos, compatibilidade, snapshots ou journals. Exportar HTML não exige nem provoca outra aplicação.

## Verificação desta revisão
1. Extraia em pasta nova.
2. Execute Validar-Regressoes.bat; espere Resultado: 0. Agora são dez suítes. Não é necessário repetir a bateria manual de aplicação/restauração já concluída para aprovar apenas o formatador.
3. Abra Executar-WinSlim-R3.2.78.bat. A prévia de seis itens UI / QoL deve mostrar uma única linha dessa categoria. O self-test WPF valida a posição dos quatro botões no rodapé nos temas claro/escuro e nos tamanhos previstos.
4. No próximo ciclo normal de aplicação, confira a conclusão agrupada e use Exportar relatório se desejar um arquivo HTML. O arquivo JSON original continua no backup. A leitura do relatório confirma o resultado declarado pelo motor; efeitos visuais ainda dependem da superfície do Windows.
5. Envie logs/regressao-... em caso de falha. Não avance com falhas; esta revisão precisa de seu próprio gate Windows.

## Testes e limitações
REG-REPORT-001 compila o formatador C# e testa agrupamento por ID, distinção de valores/ajustes, exclusões, origem, preservação da entrada, erros, divergência, estados desconhecidos/rollback, resultado vazio e escape de HTML. Usa também o catálogo real para conferir os seis ajustes em uma linha da prévia; risco e reinícios são testados com fixtures mistas. O gate NativeUI executa essa suíte e inclui o novo botão nas verificações de layout e bloqueio durante operação. As nove suítes anteriores continuam exigidas.

A implementação foi revisada e XML/XAML, JSON, hashes, referências e preservação da base foram conferidos neste ambiente. Os cinco testes do protótipo Python também podem ser executados aqui, mas não substituem o formatador integrado. PowerShell 5.1, .NET Framework e WPF não estão disponíveis aqui: compilação e dez suítes desta R3.2.78 PENDENTES no Windows. Não atribuir a aprovação da R3.2.77 à R3.2.78.

O protótipo previamente autorizado foi consultado e os scripts de referência estão em docs/relatorio-prototype-r3278; o aplicativo não depende deles. Nenhum novo tweak é liberado nesta revisão de apresentação.

## Correção do pacote — cadastro de regressão
O pacote inicial incluiu REG-REPORT-001 duas vezes e a rotina interrompeu corretamente antes de executar as suítes. O cadastro foi corrigido para dez IDs únicos e a chamada redundante da suíte de relatório no gate foi removida. O empacotador agora valida IDs únicos, caminhos e hashes antes de publicar o ZIP; sua regressão reproduz e rejeita a duplicação. A regressão Windows do harness também ganhou o cenário de ID duplicado, exigindo ausência de execução dos scripts filhos.

A causa foi reproduzida localmente: o empacotador recusou o cadastro original com REG-REPORT-001 duplicado. Após corrigir, seis testes do empacotador passaram. Nas evidências enviadas, a compilação C# da R3.2.78 passou, a categoria foi unificada e houve aplicação/restauração verificadas; a suíte completa não rodou por causa do cadastro duplicado. Execute novamente apenas Validar-Regressoes.bat nesta cópia corrigida; não precisa repetir a aplicação/restauração. Não há alteração nos mecanismos ou no código da interface nessa correção de pacote.
