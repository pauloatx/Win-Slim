# R3.2.84 — Comparação de frame time, revisão 4

1. Extraia em pasta nova e execute **Iniciar-Validacao.bat**.
2. Em **Análise do Sistema → Medir desempenho**, faça a primeira medição e clique em **Guardar referência**.
3. Meça novamente o mesmo jogo, com a mesma duração, cena e configurações.
4. No gráfico, **laranja contínuo = atual**; **azul tracejado = referência**. As duas curvas usam a mesma escala vertical.
5. Passe o mouse para ver os valores e a diferença em ms (atual menos referência). Valor negativo significa menos tempo naquela amostra.

O eixo horizontal é a posição relativa das amostras, de 0% a 100%; não sincroniza eventos nem instantes das duas capturas. A dica informa essa limitação. A duração escolhida igual não garante a mesma cobertura real de dados. Não conclua ganho de desempenho por um único ponto ou por capturas incompletas.

Para diagnóstico, use **Coletar-Diagnostico.bat**. A revisão 2 passou nas 16 suítes conforme os logs recebidos. A revisão 4 ainda precisa de validação Windows; não exige reaplicar ajustes já aprovados.

A revisão 4 compacta o cabeçalho e os espaçamentos para recuperar a altura do gráfico no tamanho menor de janela. As curvas e o hover são preservados.
