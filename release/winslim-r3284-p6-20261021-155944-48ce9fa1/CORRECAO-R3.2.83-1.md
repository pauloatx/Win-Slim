# R3.2.83 — correção 1 do inicializador

Corrige a falha LiteralPath vazio antes do início das regressões. Iniciar-Validacao.bat e Coletar-Diagnostico.bat passam a pasta explicitamente, usando um ponto após a barra final para preservar as aspas. O script resolve a pasta após a vinculação dos parâmetros, reutilizando o resolvedor de caminhos já coberto pelas regressões.

REG-PIPELINE-001 foi ampliada para executar a candidata com Root omitido, vazio e espaços a partir de outro diretório; também executa os dois BATs reais em pasta com espaços/acentos. /ci nos BATs evita pause e, no inicializador, evita abrir a interface durante testes. O uso normal continua por duplo clique.

Extraia o pacote corrigido em pasta nova e execute Iniciar-Validacao.bat. Não precisa repetir os lotes anteriores já aprovados. Esta correção mantém o PresentMon e o código de aplicação/restauração.

Validação local: seis testes Python do empacotador aprovados, cadastro de 16 suítes e hashes conferidos. Execução da regressão ampliada em Windows PowerShell 5.1 e compilação/WPF continuam PENDENTES neste ambiente Linux. A captura recebida demonstra a falha da versão anterior; não constitui aprovação desta correção.
