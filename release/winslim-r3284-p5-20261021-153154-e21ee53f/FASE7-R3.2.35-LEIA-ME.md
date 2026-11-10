# Win-Slim Suite — R3.2.35

A chave Modo desenvolvedor em Configurações → Avançado usa verde #00C853 quando ativada e permanece cinza quando desativada, com o mesmo padrão das chaves em Personalizado. Formato, rótulos, comportamento e opções são preservados.

O log enviado da R3.2.34 apresentou uma falha no gate: um teste ainda procurava o controle ATIVO do antigo protótipo de Configurações. A R3.2.35 verifica o controle funcional OptDeveloper e seu estilo exclusivo, preservando as verificações independentes dos 16 overlays. A falha era na verificação antiga, não uma evidência de mudança na contagem dos overlays.

Extraia em pasta nova e execute Validar-Configuracoes-R3.2.35.bat. Abra Visualizar-Configuracoes-R3.2.35.bat e alterne Modo desenvolvedor: ligado verde, desligado cinza. As abas Avançado e Logs permanecem em Configurações. Execução continua em modo de consulta/demonstração.

XML, nomes, estrutura C#, revisões anteriores e ZIP foram conferidos localmente. Compilação e teste WPF da nova revisão precisam ser executados no Windows.
