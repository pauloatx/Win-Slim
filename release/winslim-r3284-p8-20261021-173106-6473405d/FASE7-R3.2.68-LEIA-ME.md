# Win-Slim R3.2.68 — registro: teclado e privacidade

Dois novos contratos liberados para aplicação real, com revisão, backup obrigatório, verificação e restauração. Total de nove IDs autorizados; a quantidade disponível depende da compatibilidade e seleção.

| ID | Categoria | Pesquisar por | Alteração |
| --- | --- | --- | --- |
| PILOT-001 | Performance | Repeticao do Teclado | KeyboardDelay, String 0, no usuário atual |
| PRIV-017 | Privacidade | Experiências personalizadas | DisableTailoredExperiencesWithDiagnosticData, DWORD 1, no usuário atual |

PILOT-001 reduz a espera antes de uma tecla mantida pressionada começar a se repetir. Não representa aumento da taxa de comunicação do teclado. A gravação é verificada no Registro; o efeito na sessão pode exigir sair e entrar na conta. A configuração de acessibilidade FilterKeys pode afetar o comportamento percebido.

PRIV-017 impede o uso de dados de diagnóstico para recomendações personalizadas, conforme a política do Windows. Pode continuar havendo dicas e ofertas. O app verifica a edição local e o build: Windows cliente a partir do build 15063, nas edições Pro, Enterprise, Education e IoT Enterprise e variantes reconhecidas. Home, Server, edição desconhecida ou falha de detecção excluem esse ajuste, com motivo na revisão. A checagem é repetida antes da aplicação. Uma gravação verificada não prova um efeito visual imediato nas recomendações.

Os sete contratos anteriores continuam disponíveis: PERF-001, UI-007, UI-008, UI-009, UI-014, UI-015 e UI-016. Não houve alteração das seleções dos presets nem liberação de HAGS, MSI ou afinidade nesta revisão.

## Como validar
1. Extraia em pasta nova e execute Validar-Aplicacao-Registro-R3.2.68.bat na VM.
2. Após o gate aprovado, abra Executar-WinSlim-R3.2.68.bat.
3. Em Personalizado, selecione PILOT-001 e PRIV-017. Confira a revisão: em edição incompatível, somente PILOT-001 será liberado. Para um lote de dois nessa situação, acrescente UI-008, já validado.
4. Use Aplicar selecionados → Revisar aplicação real → Criar backup e aplicar. Revise os IDs antes de confirmar.
5. Abra Ver backups, selecione a cópia Antes da aplicação desta execução e use Restaurar tudo.
6. Envie logs e as pastas dos backups dessa aplicação e restauração, com seus journals. Um teste em lote basta nesta rodada.

## Validação feita
107 verificações locais de aplicação, 50 de restauração e a suíte de backup aprovadas. Casos incluem contratos adulterados, reaplicação sem escrita, falha parcial, recuperação, ausência original, edição/build incompatível e mudança de compatibilidade entre revisão e aplicação. C#5 compilado contra referências .NET Framework 4.8 e sintaxe PowerShell/XAML conferidas. Ambiente local Linux/PowerShell 7.4.6; WPF, Windows PowerShell 5.1 e aplicação real da nova versão dependem da validação Windows.

As correções visuais da R3.2.67 foram preservadas: posição/cor das chaves e remoção do botão Criar backup na prévia. Todos os arquivos de versões anteriores permanecem idênticos.

## Referências da revisão
- Microsoft Learn, Experience Policy CSP, AllowTailoredExperiencesWithDiagnosticData: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata
- Microsoft Learn, SystemParameters.KeyboardDelay: https://learn.microsoft.com/en-us/dotnet/api/system.windows.systemparameters.keyboarddelay
- Contratos do catálogo local: PILOT-001 em catalog.json e PRIV-017 em catalogs/validated/Expansion-R4.json.
