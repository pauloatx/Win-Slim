# Win-Slim Suite — R3.2.9 — Ajustes visuais do Dashboard

## Testar

1. Feche o Win-Slim e extraia o pacote em uma nova pasta.
2. Execute `Validar-Dashboard-R3.2.9.bat` primeiro.
3. Se o gate passar, abra `Executar-WinSlim-R3.2.9.bat`.
4. Confira se Início abre em 1040 × 680, se os nomes do menu aparecem completos e se CPU/GPU/RAM/Disco atualizam.
5. Navegue até Presets: enquanto a janela não tiver sido redimensionada manualmente, essa tela usa 1180 × 760. Voltando a Início, o tamanho compacto é restaurado. Se você redimensionar ou maximizar manualmente, as próximas navegações conservam sua escolha.
6. Feche a janela e execute `Capturar-Dashboard-R3.2.9.bat`.
7. Envie `capturas/Dashboard-R3.2.9.png` e `logs/gate-native-r3.2.9.log`.

Se houver falha, envie também `logs/build-native-r3.2.9.log`.

## Evidência recebida

A R3.2.8 passou no Windows: 244 verificações OK e nenhuma falha; compilação com código 0 e executável publicado, self-test WPF, bridge, baseline e preservação do log por `-IfNeeded` aprovados.
A captura fornecida confirma abertura e leitura dos dados do sistema: Windows 11 Home/build 26200, Ryzen 5 5600, 16 GB RAM, Radeon RX 480 e NVMe de 1863 GB.
A composição visual da R3.2.8 não foi declarada aprovada. Foram observados menu cortado, espaço vazio na parte inferior e bordas de controles que destoam da referência.

## Ajustes desta revisão

- Dashboard abre em 1040 × 680, mantendo a janela dentro das dimensões mínimas anteriores.
- Ajustes de margens, título e alturas dos cards/indicadores para uma composição mais compacta.
- Sidebar preserva a largura de 164; fonte de 11,5, padding de 8 e coluna de ícones de 22 evitam o corte de legendas longas.
- Links do Dashboard recebem template leve próprio; o foco por teclado usa sublinhado no link e contorno laranja no menu.
- Rodapé comunica disponibilidade do catálogo e revisão do aplicativo, sem expor a cadeia interna de implementação.
- Presets mantém a página anterior. Alterações no menu e rodapé são compartilhadas pelas telas.
- Campos de backup, histórico e contagens aplicadas continuam “não informado”: o bridge desta fase não disponibiliza esses dados.

## Preservação

Todos os arquivos da R3.2.8 e anteriores permanecem intactos. Backend: 230 IDs, presets Balanceado 105/Gamer 129/Extremo 168.
O build mantém as correções de diagnóstico, logs separados e interrupção do gate após falha.

## Validação

As verificações locais são estáticas, feitas em Linux. O gate da R3.2.9 inclui self-test WPF com validação das legendas longas do menu no viewport mínimo.
O gate verde da R3.2.8 não substitui a validação da R3.2.9. Compilação, abertura, redimensionamento e comparação visual precisam ser confirmados no Windows.
Próxima etapa: revisar a nova captura do Dashboard; somente após sua aprovação visual reconstruir Presets conforme a referência.
