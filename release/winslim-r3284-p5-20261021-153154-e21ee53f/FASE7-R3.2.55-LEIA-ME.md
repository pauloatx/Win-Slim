# Win-Slim Suite — R3.2.55

Corrige os dois casos de leitura não verificada encontrados no relatório da R3.2.54:

- Windows Search: reconhece `AutomaticDelayedStart` e consulta o indicador DWORD `DelayedAutoStart` no registro. Compara o modo automático e o atraso; modo automático sem atraso não aparece como já configurado para esse ajuste.
- Num Lock: reconhece `HKU\.DEFAULT` e `HKU:\.DEFAULT`, lendo diretamente HKEY_USERS pela API .NET. Não depende de criar um drive HKU no PowerShell.

Serviços removidos continuam identificados como ausentes. A leitura não instala serviços nem aplica alterações. Erros de acesso e indicadores inválidos continuam explicitamente não verificados.

Os detalhes mostram o modo de início, indicador atual de atraso e valor desejado. O catálogo, Core, Providers, UI aprovada e arquivos das revisões anteriores foram preservados. Backup e aplicação real permanecem para os próximos incrementos.

## Validação no Windows

1. Extraia o ZIP em nova pasta.
2. Execute `Validar-Performance-UI-R3.2.55.bat`.
3. Abra `Executar-WinSlim-R3.2.55.bat`, selecione Gamer e veja a pré-visualização e `Ver detalhes`.
4. Confira SVC-002 e QOL-011. Eles devem ser já configurados ou precisar de mudança conforme o estado real, salvo falha de acesso. Os três serviços removidos podem continuar não verificados por ausência.
5. Envie a pasta `logs` e os detalhes da pré-visualização em caso de erro.

Foram acrescentados testes isolados para HKU, Num Lock, automático com/sem atraso, ausência do indicador, acesso negado, tipo inválido e serviços removidos. O gate inclui esses testes e a preservação da R3.2.54.

Verificações locais: XML, JSON, preservação byte a byte, hashes e integridade do ZIP. Compilação C#, execução dos testes PowerShell e conferência do estado real dependem do Windows; estão pendentes nesta revisão.
