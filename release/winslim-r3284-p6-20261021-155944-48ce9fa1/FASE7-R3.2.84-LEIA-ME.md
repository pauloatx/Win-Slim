# R3.2.84 — revisão 4

Comparação visual de frame time com escala comum, legenda, atual laranja contínuo e referência azul tracejada (azul adaptado ao tema). Mouse mostra cursor, marcadores, valores e diferença, nos limites das séries. Cada série mantém suas amostras originais; a posição horizontal é relativa, sem inventar timestamps.

Referências incompatíveis pelo contrato existente não são sobrepostas. Não duplica referência idêntica à medição atual. Hover desabilitado durante captura/importação. Área de texto fixa evita redimensionamento do gráfico a cada movimento.

REG-UI-001 ampliado: duas cores e tracejado; escala comum; valores exatos do hover inicial/final; quantidades diferentes de amostras; remoção dos marcadores; referência incompatível e idêntica; dois idiomas e temas. Regressões anteriores mantidas.

Sintaxe C#, XML/JSON, preservação do coletor/motor e testes Python verificados localmente. Compilação e 16 suítes Windows desta revisão pendentes. Fórmulas e coleta PresentMon preservadas. Sem aprovação automática de produção.

## Correção da revisão 4
Logs reais da revisão 3: compilação aprovada, 15 suítes passaram e REG-UI-001 falhou na renderização do gráfico. Cabeçalho redundante removido e espaçamentos verticais reduzidos para acomodar legenda e textos sem espremer a área do gráfico. Regressão benchmark-comparison-chart-height exige área mínima 90x60, conserva todos os testes de curvas e hover e registra dimensões em qualquer nova falha. Verificação Windows desta correção pendente; teste anterior não foi enfraquecido.
