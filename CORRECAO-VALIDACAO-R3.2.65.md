# R3.2.65 — medição do texto com a configuração real da UI

O log da R64 apontou `BtnPreviewBack`: atual 134x36, requerido 137,12x32. A janela configura TextFormattingMode.Display; o TextBlock isolado da verificação usava Ideal. Esse desvio fazia o teste medir o texto de maneira diferente da interface.

O self-test agora usa o mesmo modo de formatação/renderização, idioma, direção e alinhamento a pixels do botão. Nenhuma tolerância foi aumentada. Motor e desenho preservados. Execute `Validar-Aplicacao-Registro-R3.2.65.bat` na VM e envie a pasta logs.
