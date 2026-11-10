# Investigação AV-20261021-001 — PresentMonHarness.exe

**Atualização 22/10/2026:** o responsável pelo projeto registrou avaliação de falso positivo e autorizou validação local controlada, sem laudo atribuído ao Kaspersky. Na tentativa autorizada houve **nova detecção às 06:58:39**, com SHA-256 pré-execução conhecido, e o gate foi interrompido. Autorização suspensa; família/gate/publicação/produção retidos. [Decisão](DECISAO-RESPONSAVEL-AV-20261021-001.md), [recorrência](AV-RECORRENCIA-20261022-R3.2.84.md). O relato abaixo é histórico de 21/10, preservando a ausência de hash daquela primeira amostra.

**Conclusão técnica histórica de 21/10: origem de teste identificada; detecção confirmada nos relatórios do Kaspersky; classificação de falso positivo NÃO estabelecida.** A geração/execução da família e novos pacotes ficam retidos enquanto a investigação estiver pendente. A aparência apresentada foi aceita pelo usuário e permanece inalterada.

Continuação: [revisão estática aprofundada](REVISAO-ESTATICA-HARNESS-R3.2.84.md), com fluxo e limites dos argumentos locais, dependências atuais, fatos/hipóteses e duas verificações independentes adicionais. Para eventual envio, usar a [orientação manual v2](../logs/kaspersky-investigation-20261021/static-review-02/ENVIO-MANUAL.md): o pedido anterior foi preservado, mas continha uma afirmação não comprovada sobre backup do primeiro objeto. A v2 corrige isso; nada foi enviado. A falta de binário/hash exatos impede um veredito específico e não impede solicitar orientação de triagem, sujeita ao canal disponível.

## Objeto e evidências

- Detecção: `VHO:Trojan-PSW.Win32.Disco.gen`.
- Produto local: Kaspersky Free **21.26.4.406**.
- Caminho exato informado pelo usuário e confirmado no relatório exportado:
  `C:\Users\Administrator\AppData\Local\Temp\winslim-pm-regression-cc4b47d828ae4072bf20a60ac85ffd67\PresentMonHarness.exe`.
- Evento: **21/10/2026 15:03:27**, horário local; o usuário informou 15:03. Relatório registra análise heurística/proteção na nuvem e PowerShell como iniciador desse primeiro evento.
- **SHA-256 da amostra exata: indisponível.** O arquivo não existe mais nesse caminho e o relatório exportado não informa o hash. Não foi restaurado da quarentena, regenerado ou executado. Não se atribuiu a ele o hash de outra compilação.
- Exportação pela interface oficial de relatórios: `avp.com HELP`, `HELP REPORT`, `REPORT Product`, `REPORT SW2`, `REPORT File_Monitoring`, `REPORT AMSI` e `REPORT HvmMonitorTask`. São consultas/exportações, sem iniciar verificação ou alterar proteção. Os arquivos exportados estão preservados em `logs/kaspersky-investigation-20261021/`.
- Leitura direta dos bancos protegidos e containers `.klq` foi negada; não houve tentativa de contornar a proteção. Metadados dos seis containers foram preservados, sem extração do conteúdo. O relatório exportado permite deduplicar **16 eventos em seis caminhos temporários**. Cinco gerações posteriores têm eventos de exclusão/backup; a primeira amostra tem detecção, sem prova de qual mecanismo removeu o arquivo depois. O script antigo também limpava sua pasta no `finally`.
- Às **15:07:23**, outra geração (`winslim-pm-regression-02435d6118fe4f7192b81971f9573f4c\PresentMonHarness.exe`) registra `csc.exe`, caminho `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, como iniciador. Isso reforça o vínculo com compilação local.

Dados estruturados, caminhos completos de todas as ocorrências e referências de linha: [diagnosis.json](../logs/kaspersky-investigation-20261021/diagnosis.json). Os relatórios integrais podem conter dados locais de outros eventos e ficam fora da pasta preparada para o fabricante.

O relatório Product também contém um evento histórico de pausa da proteção em 21/10/2026 às 18:02:04. A exportação não identifica aqui o autor dessa ação; não é possível atribuí-la a esta investigação. Nenhum comando desta rodada pausou/retomou a proteção, criou exclusão, alterou configuração ou restaurou quarentena. Ausência de alertas posteriores não foi usada como prova de segurança.

## Origem e etapa de geração

É um **auxiliar de desenvolvimento**, diferente do coletor oficial Intel PresentMon. O fluxo técnico era:

`Iniciar-Validacao.bat` → `Validar-Candidato-R3.2.84.ps1` → `Executar-Regressoes.ps1` → `REG-PRESENTMON-001` → `tests/Test-Fase7-R3.2.84-PresentMon.ps1` → compilador C# local → auxiliar em `%TEMP%\winslim-pm-regression-<GUID>\` → execução da regressão e de cópias dele como coletor simulado.

O script legado R3.2.83 também usa esse nome. A build normal da interface usa uma lista explícita de fontes em `src/UI/Native/R3_2_84`; não compila `tests/PresentMonHarness.cs` para o aplicativo. O fluxo normal de monitoramento usa o coletor oficial fixado por hash.

Fontes da geração R3.2.84:

| Arquivo | Papel |
| --- | --- |
| `tests/PresentMonHarness.cs` | Entrada da regressão e simulação do coletor, com dados sintéticos |
| `src/UI/Native/R3_2_84/PresentMonBenchmark.cs` | Parser, estatísticas, processo/cancelamento e adaptador de testes |
| `src/UI/Native/R3_2_84/BenchmarkLive.cs` | Leitura incremental e janela de amostras |
| `src/UI/Native/R3_2_84/PresentMonMonitor.cs` | Monitor e gravação compartilhada, com injeção interna de processo simulado |

Comando reconstituído do script preservado: `csc.exe /nologo /noconfig /target:exe /codepage:65001 /langversion:5 /warnaserror:4014`, referências `System.dll`/`System.Core.dll`, `/out:<pasta temporária>\PresentMonHarness.exe` e os quatro fontes acima. A linha de comando integral não foi fornecida pelo evento AV; essa reconstrução é documentada como tal.

Compilador consultado somente para metadados/hash: versão **4.8.9221.0**, assinatura **Valid / Microsoft Windows**, SHA-256 `46809206887326D2D24DB1EFF1F3064DE972C3451ABE766B49111450A5E08E00`. Hashes de fontes e cópias preservadas estão em `inventory.json` e `vendor-submission/SHA256.json`.

## Comportamento e dependências revisados

Revisão estática dos quatro fontes e do gerador: o harness escreve CSV de quadros artificiais, marcadores de parada e logs em fixtures; cria cópias do próprio processo para simular o coletor; produz stdout/stderr volumosos; retorna falhas controladas e exercita cancelamento. O código compartilhado usa `ProcessStartInfo` com janela oculta e pipes, observa seus processos e encerra somente suas sessões/filhos nos testes. O auxiliar não precisa de ETW real para esses cenários.

Há comportamento que merece atenção além da aparência do nome: compilação temporária não assinada, autoexecução como processo filho e escrita de arquivos. O modo de coletor simulado aceita um caminho de saída fornecido por argumento, portanto não é uma ferramenta para uso geral com argumentos não confiáveis. A revisão não identificou acesso a senhas/credenciais, bases de navegadores, exfiltração, persistência, injeção ou instalação de driver nos fontes examinados. **Isso não comprova identidade nem inocuidade dos bytes da amostra original removida.** A razão específica da assinatura heurística continua a depender da análise do fabricante.

Nos auxiliares relacionados remanescentes, a leitura de metadados em contexto **ReflectionOnly**, sem invocar entrada ou métodos, mostrou assemblies .NET sem assinatura Authenticode e referências a `mscorlib`, `System` e `System.Core`, versão 4.0.0.0. Esses metadados não foram obtidos da amostra removida.

| Arquivo relacionado existente — não é a amostra detectada | SHA-256 |
| --- | --- |
| `D:\Desktop\winslim_fase7_r3_2_84\logs\P9PresentMon.exe` | `79C4A6D0B6655E8772A0EC53EC157E9BA3E19EF5986F984D1CD031C4D66F6774` |
| `D:\Desktop\winslim_fase7_r3_2_84\logs\p9-peaks-before.exe` | `AC080803FFFEF402681A0EA9EE4BB1FE3CE8907828BA45981DDC157AA48F5134` |
| `D:\Desktop\winslim_fase7_r3_2_84\logs\PresentMonReproducer.exe` | `BA0D3803414A3AF5D8A139399310574F8BE241A1082828C339F20D0EA4E9E004` |

Nenhum desses arquivos foi executado nesta investigação. São hashes distintos, de outras gerações, preservados para correlação.

O coletor de produção é `third_party\PresentMon\PresentMon-2.6.0-x64.exe`, 980.320 bytes, assinatura **Valid / Intel Corporation**, SHA-256 `B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF`. Não é `PresentMonHarness.exe`. Assinatura e hash identificam o objeto; não constituem laudo sobre o auxiliar detectado.

## Candidata P9 e falha de distribuição

O ZIP P9 original foi auditado sem executar seu conteúdo. Contém somente dois binários executáveis: o aplicativo e o coletor Intel. **Não contém o harness compilado**, inclusive no ZIP de diagnóstico interno auditado. Contém, porém, **448 arquivos sob `tests/` e 1.242 sob `src/`**, incluindo os geradores e códigos dos testes, além de `Iniciar-Validacao.bat`. Esse caminho de entrada recompila/executa auxiliares no computador que valida a candidata. É um pacote técnico de validação com fontes, misturado à entrega para uso final, e não um pacote somente de runtime.

O empacotador antigo incluía qualquer arquivo extra da árvore. Um teste com arquivo inerte demonstrou que aceitaria até um auxiliar compilado em `logs/`, inclusive renomeado. Também não impedia publicação durante incidente aberto. Três testes novos falharam antes da correção (`packager-before.log`); os testes antigos foram preservados.

Na P9, o bloqueio foi tratado como falha de arquivo e o auxiliar recebeu outro nome. Esse diagnóstico foi insuficiente. O fato de outra geração/nome ter executado não é evidência de falso positivo nem correção da detecção. O contorno por nome foi removido do script atual; o script agora para **antes de compilar** enquanto houver incidente.

## Correções feitas, sem alterar o acabamento

1. Política explícita `release/security-incidents.json`: incidente em investigação, SHA original nulo, sem liberação automática. Bloqueia os geradores PresentMon R3.2.83/R3.2.84, o auxiliar de monitor similar e o gate completo antes de testes/compilação. Política ausente/inválida falha de forma conservadora; liberação futura exige resolução registrada. Não há opção de ignorar o bloqueio ou repetir com outro nome.
2. Rastreabilidade para uma futura execução autorizada após revisão: registrar caminho/hash do artefato, compilador, fontes, resultado da compilação e etapa em `logs/test-artifacts/`, antes do lançamento. Arquivo removido/ilegível resulta em registro explícito, sem execução. Falhas conservam pasta e evidências em vez de apagá-las no `finally`. O registrador foi exercitado com dados inertes; o helper real não foi recompilado.
3. Empacotador com perfis explícitos **validation** e **runtime**, identificados no arquivo gerado. Runtime inclui apenas uma lista revisada de arquivos/hashes e rejeita ferramentas de desenvolvimento. Binários requerem caminho permitido e hash declarado; auxiliares extras/renomeados/MZ sob outra extensão são rejeitados. Arquivos de diagnóstico internos são auditados para impedir ferramentas binárias escondidas em ZIP.
4. Incidente em aberto bloqueia novos pacotes, preservando eventual ZIP anterior. Nenhum novo ZIP de aplicativo foi produzido. A montagem real de um pacote somente de runtime e seus testes de integração ficam pendentes da revisão AV e de um gate completo liberado; os perfis foram verificados com fixtures, não apresentados como uma nova distribuição validada.

O executável principal continua com SHA-256 `22EBCDC4F8CC6538CE8820E2F2F6FA7257BE0962BD75817CEA1BCFCD09E328D2`; **18 arquivos C#/XAML da UI** são byte a byte iguais à P9. ZIP P9 preservado: `EF515E7C5585BB036B68013E95045D3DDD23CC63933324450090BE23528E54C7`.

## Verificações e limites

- **21 testes Python do empacotador aprovados**, com arquivos inertes e sem executar qualquer payload.
- Regressão **REG-SECURITY-001**: bloqueio real dos três pontos de entrada antes de criar auxiliar; política ausente/inválida; resolução de fixture; hashes de dados e fontes inertes; saída removida/fonte ausente; preservação da evidência. Passou sem executar o auxiliar detectado ou equivalente.
- Fixtures afetadas de caminhos e pipeline passaram; não contêm o coletor simulado. Expectativas anteriores de falha/backup/relatório não foram enfraquecidas.
- `Validar-Regressoes.bat` executado: **bloqueado antes de qualquer suíte/compilação**, código 1 esperado pela política; relatório `logs/regressao-20261021-211950-872-3eb9d934/resultado.json`. O empacotador também recusou a publicação com AV-20261021-001, sem criar arquivo de saída. Não é aprovação parcial. Compilação do helper, suítes afetadas reais, novo gate completo e nova distribuição continuam pendentes; os 19/19 da P9 são evidência histórica técnica, não aprovação AV.
- Revisão estática/metadados não substituem laudo do fabricante ou identificação exata da amostra. Sem SHA original, não há comparação byte a byte com fonte compilada. Não houve recuperação da quarentena, upload ou envio de mensagens.

## Dados para o fabricante e aceite visual

Pasta preparada: `D:\Desktop\winslim_fase7_r3_2_84\logs\kaspersky-investigation-20261021\vendor-submission`. Inclui solicitação neutra de análise, eventos selecionados sem conta/nome de computador, fontes como texto e hashes. **Sem executáveis**, sem relatório integral de outros eventos e sem envio automático. Referência de atendimento e laudo: pendentes. Se o fabricante precisar da amostra exata, a obtenção deve ser decidida por fluxo controlado; não se recompila nem se restaura o objeto automaticamente. Orientação oficial: [revisão de detecções Kaspersky](https://support.kaspersky.com/1870), [portal de análise](https://opentip.kaspersky.com/requests?tab=upload).

**Aceite visual P9 registrado nesta rodada:** o usuário confirmou o novo layout e o overlay observado sobre o jogo; preservar acabamento. Não aprova automaticamente Salvar/Cancelar em todos os estados, foco/cliques, atalhos, métricas/sensores físicos, DPI físico 100/125/150 ou múltiplos monitores. Aceites P4 e funcionamento observado anteriores preservados. Edge real continua pendente e restrito à VM; CI hospedada pendente; produção não aprovada.
