# Win-Slim Suite — R3.2.49

Tema automático do Windows e alternância manual em Configurações → Geral → Aparência.

Na primeira abertura, o aplicativo lê AppsUseLightTheme do usuário: modo escuro mantém a paleta aprovada; modo claro usa fundos claros, texto escuro e tons contrastantes para estados, alertas e riscos. O contorno e a pena permanecem laranja. A chave escolhe claro/escuro e salva a preferência. Seguir o Windows reativa o modo automático, inclusive quando o tema do sistema muda com o aplicativo aberto.

O tema usa recursos dinâmicos nas telas, templates, estados dos controles, barras de rolagem e tooltips. As linhas e relatórios criados pelo código compartilham pincéis atualizados, preservando busca, categoria, seleção, navegação e tamanho da janela. Não há polling, transparência nem criação de janelas para mudar o tema.

## Testar no Windows

1. Extraia o pacote completo em uma nova pasta.
2. Execute Executar-WinSlim-R3.2.49.bat.
3. Confira claro/escuro, Seguir o Windows, textos e estados das chaves em todas as telas. Troque o tema do Windows enquanto o modo automático está ativo.
4. Feche e abra para conferir a preferência salva.
5. Execute Validar-Performance-UI-R3.2.49.bat e envie a pasta logs e capturas de ambos os temas.

O teste do ícone aceita também o frame de 16 px escolhido pelo Windows, mantendo exigência de decodificação e congelamento. O pacote ICO completo permanece idêntico.

Verificações locais: XML, estrutura C#, recursos de cores, contraste de texto, preservação das revisões anteriores e integridade do ZIP. Compilação e execução WPF ainda dependem da conferência no Windows.

A integração ao motor real continua pausada. Esta revisão mantém consulta/demonstração e não aplica otimizações no Windows.
