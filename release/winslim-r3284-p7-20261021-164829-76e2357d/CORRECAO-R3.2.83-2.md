# R3.2.83 — correção 2: self-test e diagnóstico

Os logs recebidos mostram compilação C# concluída com sete fontes e 14 de 16 suítes aprovadas, incluindo REG-PRESENTMON-001. REG-UI-001 falhou ao validar dimensões da página de benchmark; REG-PIPELINE-001 falhou durante a substituição do ZIP. As duas execuções recebidas reproduzem esses bloqueios. A captura ETW real ainda não foi comprovada.

Correções:
- O self-test usa uma janela não exibida. A validação da página agora força Measure/Arrange em um viewport finito, seguindo o padrão já usado nas páginas de revisão/backup. Mantém os limites mínimos e amplia a verificação: dois tamanhos, dois idiomas, dois temas, resultado longo, controles dentro da página e ausência de sobreposição no rodapé. Falhas registram tamanho e contexto.
- A publicação do diagnóstico usava File.Replace com argumento de backup nulo, convertido pelo PowerShell 5.1 para um caminho vazio. Agora usa um caminho real e exclusivo para backup temporário, removido após substituição bem-sucedida.
- A regressão não aceita apenas a existência de um ZIP anterior: abre cada novo ZIP e compara seu resumo ao da execução atual, inclusive nos cenários de falha. Também bloqueia o ZIP para conferir que falha de publicação preserva o arquivo anterior byte a byte.

A falha no teste de Root omitido era consequência do erro ao substituir o ZIP existente. A resolução de pasta e os testes dos dois BATs da correção 1 permanecem.

Extraia o pacote em pasta nova, feche o Win-Slim e execute Iniciar-Validacao.bat. Não repita a aplicação manual dos lotes anteriores já aprovados. Coletar-Diagnostico.bat deve gerar um único ZIP atualizado.

Validação local desta correção: seis testes Python do empacotador aprovados; análise sintática dos arquivos alterados, JSON e hashes conferidos. Compilação e execução das 16 suítes desta correção no Windows continuam PENDENTES; as aprovações anteriores não substituem essa execução.
