# Win-Slim Suite — R3.2.51

Corrige o branco fixo no texto dos overlays selecionados: o modo claro usa texto escuro sobre o fundo laranja claro; o modo escuro mantém o branco original. A mesma cor dinâmica foi aplicada ao título da janela e aos estados de hover/seleção que usam fundos claros.

Os botões de ação preenchidos mantêm texto branco sobre suas cores contrastantes. IDs, catálogo, seleção, temas automático/manual, idiomas, motor e revisões anteriores permanecem preservados.

O teste de tema agora exige contraste mínimo 4,5:1 do texto selecionado/hover nos fundos relevantes e restaura o branco no modo escuro. A validação Windows da R3.2.50 passou conforme o log enviado; o novo build ainda precisa de teste no Windows.

Extraia em nova pasta. Abra Executar-WinSlim-R3.2.51.bat, marque overlays no modo claro e confira a troca claro/escuro. Execute Validar-Performance-UI-R3.2.51.bat e envie logs e uma captura.

Verificações locais: XML, estrutura C#, recursos de tema, contraste e preservação byte a byte da revisão anterior; ZIP íntegro. Não há execução WPF neste ambiente.
