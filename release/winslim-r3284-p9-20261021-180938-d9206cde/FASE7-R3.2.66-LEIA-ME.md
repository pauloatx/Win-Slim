# Win-Slim R3.2.66 — ampliação UI / QoL

Dois novos ajustes liberados para aplicação real, com backup completo anterior à escrita, verificação tipada, restauração e recuperação em caso de falha.

| ID | Ajuste |
| --- | --- |
| UI-014 | Detalhes de operações de arquivo — Sempre mostrar |
| UI-015 | Aero Shake (minimizar ao sacudir janela) — Desativar |

Os cinco já liberados continuam disponíveis: PERF-001, UI-007, UI-008, UI-009 e UI-016. Total: sete ajustes. Os presets mantêm suas seleções; a revisão informa exatamente o subconjunto liberado e os excluídos.

UI-014 usa HKCU Explorer/OperationStatusManager, EnthusiastMode DWORD 1, sem reinício declarado. UI-015 usa HKCU Explorer/Advanced, DisallowShaking DWORD 1, com atualização do Explorer. A verificação confirma o valor do Registro; o efeito visual pode depender de fechar/reabrir o Explorer ou entrar novamente na conta. O aplicativo não reinicia o Explorer automaticamente.

## Teste na VM
1. Extraia esta versão em uma pasta nova.
2. Execute Validar-Aplicacao-Registro-R3.2.66.bat. Envie logs/gate-native-r3.2.66-visivel.log se houver falha.
3. Após aprovação, abra Executar-WinSlim-R3.2.66.bat.
4. Em Personalizado → UI / QoL, selecione os dois novos ajustes. Confira a seleção na revisão; outros itens liberados selecionados também serão aplicados.
5. Aplicar selecionados → Revisar aplicação real → Criar backup e aplicar.
6. Ver backups → selecione a cópia Antes da aplicação → Restaurar tudo.
7. Envie a pasta Backups/UI correspondente e os logs. Um teste em lote é suficiente para esta rodada.

## Validação
R3.2.65 passou no gate Windows e nos ciclos individuais e em lote UI-007/UI-008 enviados pelo usuário. Na R3.2.66: 74 testes locais do motor de aplicação, 50 de restauração, testes de backup, análise sintática PowerShell e compilação C#5/.NET Framework 4.8 aprovados. Os testes locais usam PowerShell 7 no Linux; WPF e Windows PowerShell 5.1 da nova versão ainda precisam do gate da VM.

Contratos fixos por ID verificam destino, nome, tipo, valor, risco, dependências e reinício. Catálogo, presets, motor transacional, backup e restauração anteriores preservados. HAGS, MSI e afinidade permanecem fora desta ampliação.
