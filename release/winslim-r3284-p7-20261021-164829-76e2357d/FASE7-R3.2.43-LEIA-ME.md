# Win-Slim Suite — R3.2.43

R3.2.42 passou no gate Windows enviado pelo usuário: resultado 0.

Primeira leitura de CPU/GPU/RAM/Disco priorizada imediatamente após o handshake, antes da identificação detalhada do hardware e da resolução do preset. Ao voltar ao Dashboard ou restaurar a janela, uma coleta é solicitada imediatamente; sem sobreposição. Frequência continua em 3s apenas no Dashboard visível.

Novo coletor específico desta revisão: CPU e Disco consultam apenas _Total e propriedades necessárias; RAM consulta só os dois campos de memória; GPU só UtilizationPercentage. Definições mantidas: CPU total, RAM física usada, Disco total e maior uso entre motores GPU. Mantidos os tempos de consulta do provedor; não impõe timeout individual menor que o anterior. Indisponibilidade continua indicada como —, nunca como zero fictício. RAM livre igual a zero corretamente produz 100%. O backend e coletor histórico permanecem preservados.

Ainda há tempo de inicialização do processo PowerShell, catálogo e dos provedores CIM do Windows. Esta revisão elimina a espera atrás do inventário e planejamento; não garante leitura instantânea nem percentuais de ganho sem medição. Primeira coleta tem duração registrada no log para diagnóstico. Timeout da resposta de métricas preservado: 8s.

Extraia em pasta nova e execute Validar-Performance-UI-R3.2.43.bat, depois Executar-WinSlim-R3.2.43.bat. Novo teste com consultas simuladas verifica formulas, máximo GPU, filtros, campos, RAM cheia e falhas isoladas. Verificações locais de XML/integridade/ZIP feitas; teste PowerShell 5.1, compilação e latência desta revisão pendentes no Windows. Visual e esmaecimento aprovados preservados.
