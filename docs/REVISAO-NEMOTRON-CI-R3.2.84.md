# Revisão textual preparada para Nemotron 3 Ultra — CI Windows

29/10/2026. **Texto preparado; revisão pelo Nemotron ainda não realizada. Produção permanece pendente.**

Você fará uma revisão textual/técnica da implementação de CI Windows do Win-Slim Suite em `D:\Desktop\winslim_fase7_r3_2_84`. Não execute programas, não gere harnesses retidos, não abra VM, não aplique configurações e não publique arquivos. Leia os arquivos e as evidências fornecidas. Aponte defeitos concretos, com arquivo/linha, cenário e impacto; se não puder comprovar algo, registre a limitação.

Leia primeiro `RETOMADA-R3.2.84-AV.md`, `docs/CRONOGRAMA-INDEPENDENTE-R3.2.84.md`, `AGENTS.md`, `docs/CI-WINDOWS-HOSPEDADA-R3.2.84.md`, a extensão de 29/10 em `REVISAO-TECNICA-GATE-R3.2.84.md`, `tests/regression/cases.json`, `release/review.json` e `release/security-incidents.json`.

Revise `.github/workflows/windows-candidate.yml`, `.gitattributes`, `tools/ci_evidence.py`, `tests/test_ci_evidence.py`, os dois runners novos em `tests/regression/`, `tools/validation/NativeBuildIntegrity.ps1` e a alteração em `tests/Test-Fase7-R3.2.84-NativeUI.ps1`. Compare o teste nativo com `logs/ci-hosted-implementation-20261029/before/` e o arquivo anterior identificado em `before-files.json`; a comparação textual também está na pasta da rodada. Consulte `specs/FASE7-R3.2.84-baseline.json` e a cadeia de hashes.

O workflow deve chamar exclusivamente o aceite técnico oficial `Iniciar-Validacao.bat /ci`; nenhuma regra alternativa deve permitir progressão. Confirme que cadastro completo, delegação das dez suítes, build, substituição do EXE, IfNeeded, self-test WPF e rejeição de resultados vazios/parciais/duplicados continuam no fluxo. O token só tem `contents: read`, as ações são fixadas por SHA e o checkout não persiste credenciais. Avalie a origem/versão das dependências e a ausência de serviços/drivers/instalações extras.

Confira a distinção entre baseline recebida e build atual: o primeiro gate falhou após compilar/testar WPF por comparar o hash de um EXE novo ao entregue. A correção deve conferir cada byte esperado antes da compilação e conservar as expectativas de todas as entradas depois dela; somente EXE/config são comparados ao recibo oficial capturado antes do self-test. Recibo obsoleto/incompleto, fonte alterada, arquivo indisponível e binário alterado após teste precisam continuar falhando. Não aceite atualização de hash divergente como substituto da correção. Consulte `official-candidate.log`, `build-identity-focused.log` e os relatórios de integridade antes/depois da execução final.

Avalie o transporte: somente logs textuais novos/alterados, sem resultados antigos usados como sucesso, sem DLL/EXE/ZIP de distribuição, sem credenciais no contexto; logs de falha preservados, caminhos delimitados, identidades SHA-256 e tentativa única. O par novo de relatórios comprova frescor do transporte; a aprovação dos conteúdos continua responsabilidade do pipeline oficial. Falha em coleta/upload não pode produzir job aprovado.

As evidências estão em `logs/ci-hosted-implementation-20261029/`, incluindo actionlint, parser PowerShell, reprodução Git antes/depois, oito testes Python, 13 checks de integridade, falha preservada, resultado local final, conferência de escopo e acesso ao repositório. As versões locais de Python diferem do pin hospedado e não comprovam a execução de setup-python/GitHub Actions.

**Não há execução hospedada nesta rodada:** faltam checkout associado e autenticação de escrita/Actions. A UI/public API apenas identificaram `pauloatx/Win-Slim`; não houve push/dispatch. Logo não há URL/ID hospedado e não se pode aprovar CI por YAML ou pelo gate Windows local. Verifique se essa pendência está explícita em todos os registros.

Aceites Edge reais, temas, jogo real e hotkey anteriores estão preservados; não solicite repetição sem regressão relacionada. Multimonitor físico continua não demonstrado. WPF/fixtures/ABI no runner não são aceites físicos/VM. PresentMonHarness/MonitorHarness permanecem retidos e inalterados; `component-contained` não resolve o incidente histórico do fabricante. `resolution` continua null; publicação e produção seguem pendentes.

Entregue achados por gravidade, verificações efetivamente sustentadas pelos arquivos, limitações e próximo passo elegível. Se não houver defeitos comprovados, diga isso sem transformar pendências em aprovações. A revisão textual do Nemotron será uma etapa separada, a ser registrada quando realmente realizada.
