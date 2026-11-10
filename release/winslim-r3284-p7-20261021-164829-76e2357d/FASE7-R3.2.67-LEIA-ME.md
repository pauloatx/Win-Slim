# Win-Slim R3.2.67

- Removido o botão Criar backup da página Visualizar alterações e o espaço reservado no rodapé.
- O backup obrigatório continua no fluxo Revisar aplicação real → Criar backup e aplicar.
- Personalizado sincroniza posição e cor das chaves ao renderizar a seleção do preset, inclusive com a tela oculta. Chave selecionada: direita e verde. Desmarcada: esquerda e cinza.
- As animações de interação continuam ativas conforme a preferência do usuário.
- O self-test passa a conferir também a posição ativa das chaves selecionadas na categoria.

## Executar
Extraia em pasta nova. Execute Validar-Aplicacao-Registro-R3.2.67.bat para o gate Windows. Abra Executar-WinSlim-R3.2.67.bat e confira Equilibrado, Gamer e Extremo: entre em Personalizado, alterne categorias e volte para escolher outro preset. As chaves devem corresponder à seleção. Confira também Visualizar alterações, agora sem o botão Criar backup.

Não é necessário repetir a aplicação de ajustes para conferir estas mudanças visuais. Envie o log do gate e uma imagem caso a posição das chaves ainda apresente divergência.

## Validação
Compilação C#5 com referências .NET Framework 4.8, sintaxe PowerShell, XML/XAML e preservação dos arquivos anteriores conferidos localmente. Execução WPF no Windows da R3.2.67 pendente.
O envio R3.2.66 confirmou UI-014 já configurado, UI-015 aplicado e verificado, restauração concluída e duas cópias com SHA-256 válido. O motor transacional foi preservado nesta revisão.
