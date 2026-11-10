# Win-Slim R3.2.84 — FrameTime Corrigido 4: validação técnica

## Atualização: coletor corrigido e candidata para aceite manual

Candidata atual: `winslim-r3284-p4-20261021-040645-05adeefc`, em `C:\WinSlim-Integracao\Builds\winslim-r3284-p4-20261021-040645-05adeefc`.

**Aprovada tecnicamente após a correção: 16/16 suítes Windows, self-test do binário do host e restauração nativa adicional. Nenhuma falha; stderr vazio nas 16 suítes.**

- Controlador: [resultado.json](C:/WinSlim-Integracao/Logs/20261021-010654/resultado.json), ExitCode 0.
- Resultado completo: [resultado.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-040645-05adeefc/logs/regressao-20261021-040808-660-b2f754a6/resultado.json).
- Aceite técnico: [summary.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-040645-05adeefc/logs/candidato-r3284-20261021-040808-271-816bb279/summary.json), `TechnicalPassed=true`, `ProductionApproved=false`.
- Conferência do ZIP: [summary.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-040645-05adeefc/logs/integration/summary.json), `DiagnosticBuildLogsPassed=true`, sete entradas com SHA-256 idêntico aos arquivos gerados.
- ZIP corrigido: [WinSlim-Diagnostico-R3.2.84.zip](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-040645-05adeefc/WinSlim-Diagnostico-R3.2.84.zip).
- [Roteiro de aceite manual](ACEITE-MANUAL-R3.2.84-P4.md), com abertura do executável, permissões e resultado esperado de cada item.

O coletor agora obtém a revisão do `summary.json` da própria execução e inclui os arquivos `.log`/`.json` correspondentes. Não há filtro fixo R3.2.83. Metadados inválidos e logs indisponíveis bloqueiam a publicação; logs opcionais ausentes não são reutilizados de um ZIP antigo.

Bug `diagnostic-current-revision-build-logs` registrado no caso estável `REG-PIPELINE-001`, sem remover testes antigos. A regressão comportamental reproduziu a falha antes da correção (exit 1 em [before-corrected-fixture.stderr.log](../logs/diagnostic-fix-20261021/before-corrected-fixture.stderr.log)) e passou depois (exit 0 em [after.stdout.log](../logs/diagnostic-fix-20261021/after.stdout.log)). Cobertura: R3.2.84, outra revisão, exclusão de versões semelhantes, conteúdo arquivado, ausência opcional, log bloqueado, metadado inválido e preservação do ZIP anterior/logs/resumo. A suíte completa REG-PIPELINE-001 voltou a passar na VM em 13,986 segundos.

Testes adicionais executados: seis testes Python do empacotador aprovados; `package_release.py` validou 16 IDs únicos e 125 hashes. Somente os hashes dos três arquivos corrigidos foram atualizados; três auxiliares de integração foram acrescentados ao baseline. O executável C#/WPF e o coletor PresentMon não mudaram. `Build-NativeUI-R3.2.84.ps1 -IfNeeded` confirmou a compilação do host atualizada, com o mesmo SHA-256 aprovado anteriormente.

O ZIP agora inclui, sob `build/`:

```text
build-inputs-r3.2.84.json
build-native-r3.2.84.log
build-native-r3.2.84-ifneeded.log
gate-build-r3.2.84-forced.stdout.log
gate-build-r3.2.84-forced.stderr.log
gate-build-r3.2.84-ifneeded.stdout.log
gate-build-r3.2.84-ifneeded.stderr.log
```

O controlador terminou com exit 0 após coleta e restauração de `WINSLIM_BASELINE`. A VM ficou desligada com o estado da baseline preservado. O ZIP da execução inicial mantém SHA-256 `7EE80654DEE25F6CE9A6D8D28494277AA6EE75018DE2B0E72EDCEB9042F7F0A3`; a pasta inicial de evidências não foi substituída.

**Aceite manual continua pendente:** FrameTime (comparação, cores e hover); captura/cancelamento reais do PresentMon no computador principal; Apply/Verify/Undo de EDGE-019/020/024/025 somente na VM. O auxiliar `Abrir-Aceite-Edge-VM.ps1` foi preparado e teve sintaxe verificada; a interação UAC e os efeitos reais dessas políticas não foram executados automaticamente. CI hospedada e aprovação de produção continuam pendentes. Não foi publicado ZIP de release.

## Histórico da execução inicial aprovada

Execução inicial analisada: `winslim-r3284-p4-20261021-034856-26b513b8`.
Janela do executor: 21/10/2026, 00:49:27 a 00:53:46, America/Sao_Paulo.
Revisão dos resultados feita pelos arquivos existentes, sem repetir os testes após a solicitação do usuário.

**Resultado: gate técnico aprovado; 16/16 suítes Passed, todas com ExitCode 0. Produção e aceite manual permanecem pendentes.**

## Evidências

- Resultado do controlador: [resultado.json](C:/WinSlim-Integracao/Logs/20261021-004905/resultado.json).
- Execução e verificações adicionais: [execucao.log](C:/WinSlim-Integracao/Logs/20261021-004905/execucao.log).
- Resultado detalhado das 16 suítes: [resultado.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-034856-26b513b8/logs/regressao-20261021-035013-799-493e5e64/resultado.json).
- Aceite técnico: [summary.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-034856-26b513b8/logs/candidato-r3284-20261021-035013-374-99df8946/summary.json).
- Resultado integrado: [summary.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-034856-26b513b8/logs/integration/summary.json).
- Self-test do binário compilado no host: [host-binary-selftest.json](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-034856-26b513b8/logs/integration/host-binary-selftest.json).
- Diagnóstico do aplicativo: [WinSlim-Diagnostico-R3.2.84.zip](C:/WinSlim-Integracao/Logs/winslim-r3284-p4-20261021-034856-26b513b8/WinSlim-Diagnostico-R3.2.84.zip).

## Ambiente e compilação

Compilação primária executada no computador principal com Windows PowerShell 5.1, `csc.exe` do .NET Framework 4.x, C# 5 e referências WPF explícitas. Não há solução MSBuild necessária para esse caminho; `Build-Portable.ps1` é um empacotamento distinto e não foi utilizado.

Binário do host: `bin/WinSlim.UI.Native.R3.2.84.exe`.
SHA-256: `C980CA4B8BBB888FCA3A6D2FA63EC43131F328B57EED56108475C8EC65E12AD5`.
O hash registrado no staging coincide com o registrado pelo executor da VM antes do self-test. Os 122 arquivos do baseline também coincidem no staging.

VM: `teste win-slim-win11`, computador `TESTE`, Windows 11 Home x64, versão 10.0.26300, 4 GB de RAM, modelo VirtualBox. O executor informou `Elevated: false`; testes de permissões administrativas e políticas do catálogo usaram simulação. Nenhuma aplicação real dessas políticas com token administrativo foi aprovada por esta execução.

## Comandos identificados e efetivamente utilizados

```powershell
# Compilação no host
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\Build-NativeUI-R3.2.84.ps1

# Na VM, chamado pelo executor integrado
.\Iniciar-Validacao.bat /ci
# Esse BAT chama Validar-Candidato-R3.2.84.ps1 -NoLaunch,
# que executa Executar-Regressoes.ps1 com tests/regression/cases.json.

# Verificação adicional na VM, fora das 16 suítes cadastradas
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .\tests\Test-Fase7-R3.2.84-RestoreWindows.ps1 -Root <pasta-da-candidata>

# Desenvolvimento/empacotador no host, com Python portátil temporário
python.exe -m unittest discover -s tests -p test_package_release.py -v
python.exe tools\package_release.py . specs/FASE7-R3.2.84-baseline.json
```

`Validar-Regressoes.bat` é a alternativa interativa para o mesmo harness; o BAT isolado não foi executado. A candidata executou o harness completo pela integração, sem duplicar suas dez suítes delegadas. A suíte WPF inclui recompilações e o caminho `-IfNeeded` como verificações do mecanismo de build, dentro da VM.

O controlador existente foi invocado com `-Acao Executar -UsarCredencialSalva -Snapshot WINSLIM_BASELINE -RestaurarAntes -RestaurarDepois`, apontando para o executor relativo da candidata. A credencial permaneceu sob gestão do controlador; nenhuma senha foi gravada no projeto.

## Suítes conferidas

Os IDs correspondem exatamente ao cadastro: nenhum ausente, duplicado ou adicional. Os 16 arquivos stderr estão vazios. Cada suíte tem stdout preservado.

| Suíte | Resultado | Duração |
|---|---|---:|
| REG-PROCESS-001 | Passed, exit 0 | 1,219 s |
| REG-HARNESS-001 | Passed, exit 0 | 2,842 s |
| REG-BUILD-001 | Passed, exit 0 | 0,457 s |
| REG-PERF-001 | Passed, exit 0 | 0,478 s |
| REG-UI-001 | Passed, exit 0 | 145,355 s |
| REG-EDGE-001 | Passed, exit 0 | 4,180 s |
| REG-ENDTASK-001 | Passed, exit 0 | 4,349 s |
| REG-SEARCH-001 | Passed, exit 0 | 5,520 s |
| REG-UIBATCH-001 | Passed, exit 0 | 21,273 s |
| REG-REPORT-001 | Passed, exit 0 | 2,537 s |
| REG-QOLBATCH-001 | Passed, exit 0 | 7,999 s |
| REG-EDGEBATCH-001 | Passed, exit 0 | 7,639 s |
| REG-EDGENEXT-001 | Passed, exit 0 | 7,766 s |
| REG-EDGEPRIV-001 | Passed, exit 0 | 7,527 s |
| REG-PIPELINE-001 | Passed, exit 0 | 14,352 s |
| REG-PRESENTMON-001 | Passed, exit 0 | 1,288 s |

WPF: self-test do binário do host aprovado e self-test da suíte nativa aprovado. O teste comportamental de benchmark inclui área mínima do gráfico de 90×60, dois tamanhos de viewport, temas/idiomas, escala comum, curvas distintas, hover e rejeição de referências incompatíveis/iguais. O resultado `benchmarkPageValidated` foi verdadeiro. A execução também aprovou recompilação sobre executável existente, configuração e reutilização por `-IfNeeded`.

Registro real, somente na VM: `RegistryApplyWindows` aprovou 12 verificações em chave HKCU descartável, incluindo escrita String/DWord, Verify, idempotência, recuperação de escrita parcial/Verify divergente e preservação de mudança externa. `RestoreWindows` aprovou outras 27 verificações, incluindo tipos, ausência original, falha controlada, restauração seletiva e preservação de valor não selecionado. Não foram aplicados ajustes reais do catálogo.

Python: seis testes do empacotador aprovados; validação do cadastro e 122 hashes aprovada. Foi usado Python 3.13.9 portátil oficial em pasta temporária, com assinatura Authenticode válida da Python Software Foundation. Não houve instalação do runtime nem publicação de ZIP de release.

## Estado final e restauração

`VBoxManage showvminfo` confirmou `VMState="poweroff"`. O snapshot atual é `WINSLIM_BASELINE`, UUID `4aa21603-c0b4-4139-9630-1e5d0acaef20`.

O arquivo de configuração da VM registra `currentStateModified="false"`, com gravação em 21/10/2026 às 00:53:58. O `VBoxSVC.log` registra `RestoreSnap` após a execução, e o `VBox.log` registra a transição final para `PoweredOff`. Esses dados confirmam a restauração posterior à coleta; a conferência não ligou a VM nem restaurou novamente o snapshot.

## Falhas, limitações e pendências

- **Falhas de teste: nenhuma.** `TechnicalPassed=true`, `Error=null`, `ProductionApproved=false` e `ManualValidation=Pending`.
- Na execução inicial, o ZIP padrão omitia os logs de build R3.2.84 por filtrar `r3.2.83`. Os logs foram preservados separadamente. O defeito foi corrigido e verificado na atualização acima; o ZIP histórico foi mantido intacto.
- O `VBoxSVC.log` tem mensagens COM de gravação, criptografia e encerramento de objetos. Não houve falha correspondente no controlador, no resultado das suítes ou no estado final/restauração. Esses registros não foram tratados como testes aprovados ou apagados.
- Aceite visual manual da comparação/hover da revisão 4, em lote, continua pendente.
- Captura/cancelamento reais do PresentMon/ETW continuam pendentes; a suíte utilizou coletor simulado e verificou o hash do binário oficial, sem captura ETW real.
- Efeitos reais de EDGE-019/020/024/025 e seu Apply/Verify/Undo com permissões adequadas continuam pendentes conforme o escopo registrado; os contratos e falhas passaram com IO simulado.
- CI Windows hospedada não foi executada por esta sessão. Esta execução comprova Windows/WPF local na VM, não uma execução do workflow remoto.
- Não é necessário repetir lotes anteriores já aceitos sem mudança ou regressão relacionada. O gate técnico não constitui aprovação de produção.

## Alterações preparatórias

Na preparação inicial foram adicionados os executores de integração em `tools/integration`, a compilação em `bin`, evidências em `logs` e este relatório. Naquela etapa, o código do aplicativo, os testes cadastrados, as expectativas e os hashes do baseline permaneceram preservados. A correção posterior está discriminada na atualização acima. Ambas as entregas usaram pastas exclusivas; os três logs fixos anteriores do compartilhamento foram arquivados antes de cada execução.
