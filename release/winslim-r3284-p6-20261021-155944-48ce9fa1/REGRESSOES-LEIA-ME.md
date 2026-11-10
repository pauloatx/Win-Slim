# Regressões automatizadas do Win-Slim

Execute Validar-Regressoes.bat no Windows, dentro da pasta extraída. O comando valida o cadastro, roda cada suíte em um processo isolado, impõe tempo limite e gera logs separados e resultado.json em logs/regressao-<data>-<id>. Código 0 significa que todos os casos cadastrados passaram; qualquer falha retorna 1. A suíte nativa recompila, exige ausência do CS4014 e executa os testes WPF e os contratos já existentes. Pode levar vários minutos. As fixtures de Registro do gate usam chaves descartáveis e não aplicam presets de produção.

Cada correção futura deve registrar um caso com ID, bug, cenário, script e timeout em tests/regression/cases.json. O script recebe -Root e deve terminar com código 0 apenas se todas as verificações passarem; use throw ou exit 1 ao detectar divergência. Não use testes que apenas espelham a implementação. Um teste existente pode receber o cenário novo, com o vínculo registrado no cadastro.

AGENTS.md torna essa rotina parte obrigatória do desenvolvimento e da preparação das próximas entregas. A automação executa e relata; o desenvolvedor escreve o teste comportamental de cada correção. As instruções não garantem que ferramentas externas ou pessoas que não leiam o projeto as sigam.

Casos iniciais: publicação progressiva e indisponibilidade das métricas; seleção e desseleção de categoria com busca, preservação das outras categorias e estado visual das chaves; navegação de Personalizado; build com CS4014 promovido a erro.

Os testes nativos ainda precisam ser executados no Windows. A R3.2.82 permanece pendente de validação; esta entrega não declara aprovação sem execução.

REG-BUILD-001: reproducer do CS4014 do Dispatcher, com teste negativo e positivo no compilador real.

## Correção do iniciador de regressões (16/10/2026)
A pasta raiz agora é resolvida no corpo do script por Get-Item -LiteralPath, com fallback para a pasta do próprio script. O BAT passa -Root explicitamente. Falhas informam a origem. REG-HARNESS-001 testa o harness real com caminho acentuado/com espaços, parâmetro padrão e explícito, e uma suíte que falha para impedir falso positivo.

Esta correção altera apenas a ferramenta de testes. O aplicativo continua na R3.2.82. A compilação da R3.2.82 já foi confirmada no Windows pelo log enviado (código 0, sem avisos). A suíte corrigida ainda precisa de execução no Windows. Execute Validar-Regressoes.bat e envie logs/regressao-....

R3.2.82: regressão de ExitCode rápido e thread da aba Logs.

REG-EDGE-001 cobre o novo lote de politicas de maquina com IO de Registro simulado e backup real em pasta temporaria.

REG-ENDTASK-001: preferencia UI-006, limites locais de build e ciclo completo de aplicacao/restauracao com IO simulado.

REG-SEARCH-001: UI-004, conflitos e restauracao exata de ausencia e DWORD 0/2/3, com IO de Registro simulado.

REG-UIBATCH-001: lote de seis ajustes UI/QoL, dez operacoes, verificacao completa de backup multivalor e recuperacao em cada ponto de escrita.

REG-REPORT-001: agrupamento de resultado, contagens, status conservador e escape HTML; aliases da categoria UI/QoL.


REG-HARNESS-001 também testa a rejeição de ID duplicado antes de iniciar qualquer filho.

R3.2.82: REG-QOLBATCH-001 exige contratos revisados de QOL-003/008/012 e ciclo completo com cinco valores simulados. Onze IDs unicos; usar o gate desta versao.

R3.2.82: REG-EDGEBATCH-001 cobre quatro politicas (EDGE-003/004/005/006), seus limites de versao e o ciclo Apply Verify Undo. Esta build exige doze suites.

R3.2.82: REG-EDGENEXT-001 exige quatro politicas de interface EDGE-008/011/012/016, limites de versao e ciclo completo. Sao treze suites. Fechar o Win-Slim antes da validacao e manter fechado ate terminar.

R3.2.82: REG-EDGEPRIV-001 cobre EDGE-019/020/024/025, limites locais e ciclo individual/lote. Sao 14 suites. Fechar o Win-Slim antes de validar e manter fechado ate terminar.

R3.2.83: 16 suites. Entrada recomendada Iniciar-Validacao.bat. REG-PIPELINE-001 testa delegacao sem duplicar, gate conservador e coleta automatica. REG-PRESENTMON-001 usa coletor falso: nao mede nem altera o Windows de producao. O self-test WPF cobre a nova pagina nos dois idiomas/temas. Compilacao e suites Windows pendentes neste ambiente Linux.

R3.2.84: REG-UI-001 amplia a validacao de dicas, resumo para leigos, detalhes reversiveis e idiomas/temas. As 16 suites continuam obrigatorias. Executar Iniciar-Validacao.bat na pasta nova.

R3.2.84 patch 2: REG-UI-001 cobre superfícies renderizadas do seletor nos dois temas, estado vazio PT/EN, desabilitação sem perder seleção e limites dos pontos do gráfico.

R3.2.84 patch 4: benchmark-comparison-chart-height cobre altura minima do grafico com legenda e hover, mantendo pontos, cores, escala e rejeicao de referencias incompativeis. Falha anterior reproduzida no Windows do usuario; nova execucao Windows pendente.
