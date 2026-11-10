# Retomada — R3.2.84 P8: acabamento e configurações do overlay

Registro: 21/10/2026 — America/Sao_Paulo.

- **O usuário confirmou o funcionamento observado do overlay no teste real apresentado.** Essa confirmação preserva a evidência observada da P7; não aprova o lote novo de configurações nem testes físicos ainda não realizados. Aceites P4 de comparação FrameTime e cancelar/capturar novamente preservados.
- Candidata isolada: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p8-20261021-173106-6473405d`.
- Executável: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p8-20261021-173106-6473405d\bin\WinSlim.UI.Native.R3.2.84.exe`. SHA-256: `144FA10345AAD4B93302889B91B181CBF72A291981C81C34162811B81CE8747A`.
- ZIP: `D:\Desktop\winslim_fase7_r3_2_84\release\winslim-r3284-p8-20261021-173106-6473405d.zip`. SHA-256 final registrado fora do ZIP, em `release/candidate-p8-artifacts.json` do workspace.
- Configurar overlay: moldura temática e subtítulo por jogo; Aparência, Informações e Atalhos. Prévia ilustrativa imediata, seletores Pequeno/Médio e FPS, percentuais de escala/fundo, CPU/GPU/VRAM/RAM individuais e captura de teclas com erros junto ao campo.
- Salvar grava por jogo e confirma na página. Cancelar/fechar recuperam o estado anterior. Restaurar padrão altera somente o rascunho desse jogo; mantém posição/trava e precisa de Salvar. Falha de armazenamento preserva perfil anterior e restaura atalhos.
- Acabamento: números maiores, unidades menores, rótulos com altura estável, controles com dimensões fixas e modo ativo laranja. Gráfico laranja contínuo/azul tracejado, passagem de cliques e ausência de ativação preservados. Coletor, parser e estatísticas **byte a byte iguais à P7**.
- `Validar-Regressoes.bat`: **19/19 suítes Windows aprovadas**, incluindo compilação e self-test WPF. Relatório desta execução: `logs\regressao-20261021-173120-911-ad234321\resultado.json`. Seis testes Python aprovados; 152 hashes de fontes/cadastro validados pelo empacotador.
- DPI **100%, 125% e 150% verificados por medição/renderização WPF simulada**, com rolagem, último campo acessível e rodapé sem sobreposição. Imagens: `logs/p8-layout/`. Não se alterou o DPI do Windows; aceite físico continua pendente.
- Regressão `REG-OVERLAYSETTINGS-001`: rascunho/Salvar/Cancelar/fechar/restaurar, posição, falha de armazenamento, teclas/duplicatas/conflitos, sensores individuais e DPI. O self-test preserva tarefa pendente, processo, dados e referência durante a configuração. Diagnóstico anterior de gravação prematura: `logs/p8-settings-before.log` (falha esperada antes da correção).
- P7/P6/P5/P4 e evidências preservadas. **Aceite físico do lote P8, cliques/foco no jogo, DPI/múltiplos monitores físicos, atalhos com outros programas e sensores físicos: pendentes. Edge real: pendente, somente na VM. CI Windows hospedada: pendente. Produção: não aprovada.** Nenhum ajuste aplicado; VM não modificada.

Relatório: [IMPLEMENTACAO-R3.2.84-P8.md](docs/IMPLEMENTACAO-R3.2.84-P8.md). Roteiro curto: [ACEITE-MANUAL-R3.2.84-P8.md](docs/ACEITE-MANUAL-R3.2.84-P8.md). Não repetir manualmente lotes antigos aprovados sem regressão relacionada.