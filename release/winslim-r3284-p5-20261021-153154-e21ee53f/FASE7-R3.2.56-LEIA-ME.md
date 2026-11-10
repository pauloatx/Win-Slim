# Win-Slim Suite — R3.2.56

## Backup real de registro e serviços

A pré-visualização passa a oferecer **Criar backup** após o Planner validar o plano. O botão captura novamente o estado atual dos ajustes de registro e serviços elegíveis e salva uma cópia em `Backups/UI/<id>/`, dentro da pasta do aplicativo. O resultado mostra os ajustes cobertos e os excluídos. A tela Backup/Restauração lista essas cópias e permite consultar os detalhes por backup ou por tweak.

Esta revisão cria arquivos reais. Ainda não aplica ajustes, restaura dados, cria ponto de restauração do Windows nem reinicia o computador. O backup tem cobertura limitada a registro e serviços. Appx, scripts, operações compostas e outros tipos ficam explicitamente fora da cobertura, assim como serviços ausentes e ajustes cuja captura falhou. Não é imagem do sistema nem backup completo de todo o preset.

## O que fica salvo

- Registro: hive, caminho, nome, existência, tipo e valor original, incluindo HKU\.DEFAULT. Ausência de valor difere de string vazia.
- Valores binários usam Base64; MultiString preserva arrays; DWORD/QWORD usam texto decimal com indicação do tipo para preservar precisão e sinal.
- Serviços: nome, modo de início, estado observado e existência/tipo/valor do indicador DelayedAutoStart.
- Perfil, identificação do plano, computador, usuário, visão do registro e horários de início/fim da captura.
- Itens excluídos com os respectivos motivos. Um ajuste só é incluído quando todas as suas operações foram capturadas.

A cópia utiliza um formato de snapshot de dados versionado, separado dos backups de transações do motor. Nenhuma cópia é declarada restaurável nesta revisão. A ligação ao caminho de restauração e sua validação fazem parte do próximo incremento.

## Integridade e comportamento

Os arquivos são gravados em uma pasta temporária, descarregados para disco e relidos. `manifest.json` contém o SHA-256 de `snapshot.json`. A pasta final é publicada por renomeação após a verificação. Cópias anteriores nunca são sobrescritas. Pastas incompletas não aparecem como backups verificados.

A listagem verifica novamente a integridade; os detalhes fazem uma nova leitura verificada. SHA-256 detecta corrupção acidental; não é assinatura de autenticidade. Arquivos inválidos são contabilizados, sem execução de seu conteúdo. A listagem transfere resumos; os valores completos só são carregados ao abrir os detalhes.

A criação usa uma referência temporária da pré-visualização (10 minutos, uso único), recalcula o plano e exige a mesma identificação antes da captura. Valores são relidos no momento do backup. Ao mudar o plano ou após uma falha, abra novamente a pré-visualização. Se houver interrupção ou timeout após a gravação, confira Backup/Restauração antes de criar outra cópia.

## Como validar no Windows

1. Extraia o ZIP em uma nova pasta.
2. Execute `Validar-Backups-R3.2.56.bat` como administrador. O gate compila a UI e executa os testes isolados em pasta temporária, sem modificar registro ou serviços.
3. Abra `Executar-WinSlim-R3.2.56.bat` como administrador.
4. Selecione Gamer ou uma seleção personalizada e abra a pré-visualização.
5. Clique em **Criar backup**. Confira a quantidade salva e os itens fora da cobertura em **Ver detalhes**.
6. Abra **Backup / Restore**, selecione a cópia e consulte **Detalhes**. Reabra o aplicativo e confirme que ela continua listada.
7. Envie a pasta `logs` e o resultado apresentado. Para comparar máquina real e VM, mantenha os arquivos identificados por ambiente.

Os serviços removidos continuam fora da captura, com motivo explícito. As contagens podem diferir entre máquinas e da quantidade indicada como apta pelo Planner, porque o suporte de backup é mais restrito.

Os testes isolados cobrem valores ausentes, string vazia, listas vazias/múltiplas, binários, QWORD máximo, serviço com atraso, plano bloqueado, falha de leitura, falha de gravação, preservação de cópia anterior, arquivo adulterado e verificação em outro processo.

Verificações realizadas neste ambiente: XML/JSON, referências da interface, preservação byte a byte das revisões anteriores, hashes e ZIP. Compilação C#, execução dos testes PowerShell 5.1, criação real e conferência visual no Windows estão pendentes nesta revisão.
