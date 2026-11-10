# Win-Slim Suite — R3.2.41

Extraia em pasta nova, execute Validar-Performance-UI-R3.2.41.bat e abra Executar-WinSlim-R3.2.41.bat. Confirme a versão no rodapé.

Otimização da UI preservando o visual e esmaecimento R3.2.40 aprovados:
- Pincéis de cores compartilhados e congelados, cache limitado a 128 entradas.
- Índice do catálogo por categoria: contagens e renderização consultam apenas a categoria ativa.
- Linhas ainda visíveis são reutilizadas. Atualização idêntica não recria nem remove controles. Sem cache de controles de categorias ocultas.
- Busca agrupada após 120ms de pausa na digitação; atualização programática explícita permanece imediata.
- Consultas de presets agrupadas por timer de 90ms, com no máximo uma consulta em execução e uma atualização pendente. Respostas obsoletas continuam descartadas.
- Recursos de estilo e controles nomeados estáveis reutilizados. Texto e logs idênticos não são reatribuídos.
- Leitura de logs não se sobrepõe e lê do fim do arquivo (até 200 linhas, limite de 1 MiB), em vez de percorrer todo o histórico. Exportar logs mantém o arquivo completo. Métricas continuam a cada 3s apenas no Dashboard; respostas após saída da tela são ignoradas.
- Timers param ao fechar. Navegar novamente à mesma página não reinicia a animação.

Self-test acrescenta verificação de pincéis imutáveis, índice com 230 ajustes, zero controles novos na atualização de lista idêntica, reutilização de linha ao filtrar e preservação da seleção. O leitor de logs é testado com 1.000 linhas UTF-8 e comparação exata das 200 últimas. O JSON do self-test registra as contagens reais de controles criados e catálogo indexado. Testes funcionais anteriores permanecem. Compilação, fluidez e consumo real de CPU/RAM ainda precisam de medição no Windows; não se declara percentual de ganho sem medição. Catálogo, provedores e modo de consulta/demonstração preservados.
