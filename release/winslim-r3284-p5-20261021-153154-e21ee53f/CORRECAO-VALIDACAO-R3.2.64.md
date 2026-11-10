# R3.2.64 — largura dos botões da prévia

A R3.2.63 concluiu 55 testes do fluxo, 12 de Registro nativo controlado e 50 de restauração. O self-test WPF falhou porque ainda exigia 200 DIPs de largura para Criar backup, que ocupa 149 DIPs no layout desde a R62.

A verificação agora mede texto, padding e bordas e confere altura mínima, visibilidade e desabilitação sem plano válido. O mesmo cálculo verifica os quatro botões do rodapé nos dois temas, idiomas e tamanhos. Os testes de sobreposição continuam ativos, e eventuais falhas informam tamanho atual e necessário.

Motor e layout preservados. Execute `Validar-Aplicacao-Registro-R3.2.64.bat` na VM.
