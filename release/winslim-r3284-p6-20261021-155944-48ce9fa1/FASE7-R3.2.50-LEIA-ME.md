# Win-Slim Suite — R3.2.50

Corrige o teste de eficiência que ainda exigia pincéis congelados nos controles dinâmicos. Desde a R3.2.49, esses pincéis são compartilhados e mudam de cor na thread da interface para acompanhar o tema sem reconstruir as linhas.

O teste agora exige compartilhamento, possibilidade de atualização e acesso na thread correta. A troca claro/escuro verifica contraste, atualização e restauração dos mesmos pincéis; os recursos dos templates continuam congelados. Também verifica preservação da página, tamanho, categoria, busca, seleção e identidade das linhas.

O comportamento do aplicativo aprovado na R3.2.49 permanece: tema automático do Windows, escolha manual salva, idiomas, layout, contorno, animações e catálogo. Não houve mudança no motor nem aplicação real de otimizações.

## Conferir no Windows

1. Extraia em uma nova pasta.
2. Execute Validar-Performance-UI-R3.2.50.bat até o resumo final.
3. Execute Executar-WinSlim-R3.2.50.bat e confira os temas automático/manual e suas seleções.
4. Envie a pasta logs, mesmo se houver falha.

Estrutura XML/C#, preservação da R3.2.49, contraste e integridade do ZIP foram verificados localmente. Compilação e execução WPF do novo teste ainda precisam ser confirmadas no Windows.
