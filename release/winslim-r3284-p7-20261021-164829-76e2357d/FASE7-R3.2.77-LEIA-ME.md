# Win-Slim R3.2.77 — lote UI / QoL

Base R3.2.76: oito suítes e aplicação/restauração UI-004 aprovadas nos arquivos enviados. Esta revisão possui alterações novas e precisa de seu próprio teste Windows.

## Seis ajustes liberados em um pacote
| ID | Função | Critério local desta versão | Valores |
|---|---|---|---|
| UI-001 | Ativar tema escuro do Windows e aplicativos | Windows cliente 10/11, build 10240+ | 2 DWORD |
| UI-010 | Mostrar segundos no relógio | Windows 11, build 22631+ (limite conservador) | 1 DWORD |
| UI-017 | Desativar aceleração do mouse | Windows cliente 10/11, build 10240+ | 3 strings |
| UI-021 | Ocultar Pesquisa e Visão de Tarefas da barra | Windows cliente 10/11, build 10240+ | 2 DWORD |
| UI-023 | Desativar destaques da Pesquisa | Windows 11 build 22621+, Pro/Enterprise/Education/IoT Enterprise e variantes autorizadas | 1 DWORD HKLM |
| UI-024 | Ocultar recomendações de sites no Iniciar | Windows 11 build 22631+, mesmas edições de UI-023 | 1 DWORD HKLM |

UI-023/024 afetam todos os usuários e exigem administrador. Home, edição desconhecida, detecção com falha ou sistema não suportado excluem as políticas com motivo. Para as políticas, os limites desta entrega são conservadores: versões antigas com atualização de suporte não são habilitadas apenas pelo número principal da build. UI-023 fica excluído no Windows 10 neste lote; não se afirma que o recurso inexista nele.

UI-021 e UI-004 representam modos diferentes da mesma pesquisa e são mutuamente exclusivos. Importar a seleção do lote resolve isso ao selecionar somente UI-021. Os presets padrão e o catálogo de 230 ajustes foram preservados.

O tema muda a aparência do Windows e pode mudar a aparência do próprio Win-Slim quando ele segue o sistema. Segundos no relógio são uma preferência visual e podem aumentar atividade/consumo; não são ganho de desempenho. A preferência de mouse deve ser conferida após sair/entrar na conta; jogos com entrada bruta podem ignorar a aceleração do Windows. O lote não realiza atualização de parâmetros da sessão via API. Nenhum Explorer/processo é reiniciado automaticamente.

## Teste em lote
1. Extraia em pasta nova e execute Validar-Regressoes.bat. Aguarde Resultado: 0.
2. Abra Executar-WinSlim-R3.2.77.bat como administrador usando a mesma conta do teste.
3. Em Personalizado → Importar preset, selecione Teste-Lote-UI-R3.2.77-Windows11.json. Para Windows 10 use o arquivo Windows10; ajustes incompatíveis são excluídos pelo backend.
4. Clique Aplicar selecionados → Revisar aplicação real. Confira nomes, exclusões e aviso de políticas de máquina. No Windows 11 Pro compatível são seis ajustes e dez valores; no Home são quatro ajustes e oito valores.
5. Use Criar backup e aplicar. O backup guarda cada ajuste com todos os seus valores. Já configurados não são reescritos.
6. Salve os documentos e saia/entre na conta manualmente para atualizar o efeito de tema, relógio, mouse e barra. Confira os efeitos em conjunto. Win+S e Win+Tab continuam acessíveis mesmo com os botões ocultos. A verificação automática confirma o Registro; a inspeção visual confirma o efeito da superfície do Windows.
7. Em Backup / Restauração, selecione Antes da aplicação desse lote e use Restaurar tudo. Isso restaura os valores cobertos por essa cópia. Confira a volta ao estado anterior após sair/entrar na conta. Se antes já estava configurado, deve permanecer assim.
8. Envie logs/regressao-... e a cópia correspondente de Backups/UI. Não é necessário testar cada tweak separadamente à mão; a suíte cobre cada um e o lote. Não repita manualmente Edge/UI-006/UI-004 já aprovados sem um problema novo.

As políticas da organização podem prevalecer sobre preferências locais. A restauração recupera os valores capturados, sem impor o padrão de fábrica. Backup da aplicação não é uma imagem completa do Windows.

## Implementação e regressão
Contratos independentes e fixos para cada destino/tipo/valor, incluindo cada operação dos ajustes multivalor. O fluxo distingue contagem de ajustes no backup e contagem de valores na aplicação. Antes de escrever, o backup deve cobrir todos os ajustes e operações; identidade, destino e estado capturado são conferidos. A autorização reavalia compatibilidade local antes da escrita. Valores já iguais não são reescritos; falha parcial tenta recuperar todos os valores tocados e verifica o resultado.

REG-UIBATCH-001 usa catálogo e motores reais com IO de Registro simulado e arquivos temporários. Cobre cada novo destino adulterado, operação extra/ausente, conflitos, Windows 10/11, limites de build, edição, Server, falta de administrador, detecção falha/ausente, falha de leitura/disco, Apply/Verify/Undo individual e em lote, idempotência, recuperação após cada uma das dez posições de escrita e backup multivalor incompleto. As suítes anteriores são preservadas; a expectativa de UI-021 foi atualizada porque agora há autorização exata de dois valores. Fontes antigas permanecem congeladas em suas pastas.

A categoria completa foi inventariada em AUDITORIA-UI-QOL-R3.2.77.md. Itens sem suporte uniforme, scripts, binários ou componentes antigos não receberam autorização genérica.

## Estado da validação
XML/XAML, JSON, hashes, referências, preservação e integridade ZIP conferidos localmente. Não há PowerShell 5.1, .NET Framework ou WPF neste ambiente. Compilação e execução das nove suítes desta revisão PENDENTES no Windows; a aprovação da R3.2.76 não é atribuída à R3.2.77.

## Fontes primárias consultadas
- Tema, relógio, pesquisa e Visão de Tarefas: https://github.com/microsoft/winget-dsc/blob/main/resources/Microsoft.Windows.Developer/Microsoft.Windows.Developer.psm1
- Aceleração e limiares do mouse: https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfoa (a entrega altera a preferência persistida; não chama SPI_SETMOUSE)
- Destaques: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowsearchhighlights
- Sites recomendados: https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start#hiderecommendedpersonalizedsites
