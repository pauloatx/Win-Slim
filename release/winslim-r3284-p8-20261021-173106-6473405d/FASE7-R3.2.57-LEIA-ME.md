# Win-Slim Suite — R3.2.57

## GPU e overlays compatíveis

- Detecção por identificador PCI, estado do dispositivo e presença de driver. NVIDIA e AMD não são inferidos pelo fabricante da CPU. Considera todas as GPUs; aceita sistemas híbridos e rejeita adaptadores virtuais/genéricos ou com erro. Uma GPU física repassada à VM pode ser reconhecida normalmente.
- Overlays indisponíveis ficam desabilitados, com o motivo na dica. Os universais permanecem disponíveis conforme seus requisitos. P-cores exige topologia híbrida confirmada; Core Parking exige consulta válida do plano de energia.
- Presets e prévia usam a mesma seleção filtrada. Os totais efetivos variam por máquina; as bases históricas 105/129/168 continuam preservadas no catálogo original.
- NVIDIA/AMD: somente o serviço opcional realmente instalado e compatível entra na seleção do preset. Marcar um preset não executa o ajuste. O usuário pode editar a seleção em Personalizado.
- Importar um preset com ajustes incompatíveis é recusado com o motivo, preservando a seleção anterior.

## Configurações → Avançado → GPU

Três grupos: NVIDIA (verde), AMD Radeon (vermelho) e Universal (laranja). Cada item exibe risco e disponibilidade.

**Operações reais nesta revisão:** desativar exclusivamente `NvTelemetryContainer` ou `AUEPLauncher`, quando existentes no hardware correspondente. Não altera tarefas agendadas, instalação do driver, AMD External Events, clock, voltagem ou perfis de jogo. Trata-se de controle de serviço opcional, não de promessa de ganho de FPS.

1. **Criar backup:** salva o estado atual do serviço e confere a integridade do arquivo.
2. **Aplicar:** exige backup da mesma máquina/usuário e estado ainda idêntico ao capturado; desativa o início, para o serviço e verifica o resultado.
3. **Verificar:** consulta novamente o estado real, sem alterar configurações.
4. **Desfazer:** restaura início, execução e existência/valor exato de DelayedAutoStart. Recusa alterações externas posteriores. Backups continuam disponíveis na lista após reabrir o aplicativo.

Os comandos de alteração exigem administrador, validam novamente o hardware e usam trava entre instâncias. Falhas de execução tentam restaurar e verificar o estado anterior; falhas de recuperação são informadas. O backup permanece salvo. Não há criação de ponto de restauração nem backup integral do sistema.

## Limites deliberados

HAGS, forçar MSI e afinidade de interrupções **não foram liberados por suposição de fabricante**. A seção Universal os mostra bloqueados com a justificativa; esta revisão ainda não tem um detector confiável de suporte por driver para liberá-los. O antigo `GpuPreference` global também foi retirado da seleção, pois não representa a configuração de preferência por aplicativo do Windows. Use as opções de gráficos do Windows para esses recursos enquanto seus contratos específicos não estiverem validados.

A aplicação em lote e a conclusão gerais continuam demonstrativas. A aplicação/Undo real descrita acima está restrita aos dois serviços opcionais da seção GPU. Todos os arquivos de versões anteriores foram preservados; as alterações são da R3.2.57.

## Como validar

1. Extraia o ZIP em uma nova pasta.
2. Execute `Validar-GPU-R3.2.57.bat`: faz as verificações, compila e executa o autoteste da interface no Windows. Os testes usam dados simulados para alterações de serviço; não aplicam ajustes ao Windows.
3. Abra `Executar-WinSlim-R3.2.57.bat` e confira Presets, Personalizado e Configurações → Avançado → GPU, nos temas claro e escuro.
4. Execute `Diagnosticar-GPU-R3.2.57.bat` nas máquinas real e virtual. Envie `logs/gate-native-r3.2.57.log`, `logs/diagnostico-gpu-r3.2.57.json` e, se houver falha, o arquivo de erro correspondente.

A detecção é mantida em cache para preservar a fluidez. Após trocar GPU/driver, reabra o aplicativo. Aplicar sempre revalida os dispositivos antes da alteração. A disponibilidade pode ser diferente nas duas máquinas; serviços removidos não serão reinstalados.

## Verificação do pacote

Testes de política/presets/planner e transações com adaptadores simulados executados em PowerShell 7.4.6 no Linux. Compilação de referência C# 5 com assemblies .NET Framework 4.8 verificada separadamente. Esses resultados não substituem o gate Windows PowerShell 5.1, o compilador local nem a conferência visual WPF no Windows; esses testes continuam pendentes.

## Referências técnicas para os bloqueios

- Microsoft, MSI deve ser habilitado pelo driver: https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry
- Microsoft, capacidades WDDM 2.7/HAGS: https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/d3dkmdt/ns-d3dkmdt-d3dkmt_wddm_2_7_caps
- AMD, opção oficial do programa de experiência do usuário: https://www.amd.com/en/legal/privacy/user-experience-program.html
