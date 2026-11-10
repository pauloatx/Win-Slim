# Ambiente preparado - Win-Slim Suite R3.2.84

## Data e plataforma
- Data: 23/10/2026
- Plataforma: Windows 10 Home 2009, 64 bits
- PowerShell: 5.1 (WindowsPowerShell\v1.0\powershell.exe)
- .NET Framework: 4.8 (inclui csc.exe em C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe)
- .NET Core runtimes: 6.0 - 10.0 (presentes, não usados pelo projeto .NET Framework)

## Dependências instaladas nesta sessão

| Componente | Versão | Caminho | Fonte oficial |
|------------|--------|---------|---------------|
| Git para Windows | 2.47.1 | C:\Program Files\Git\bin\git.exe | https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe |
| Python | 3.11.9 | C:\Program Files\Python311\python.exe | https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe |

**PATH atualizado:** `C:\Program Files\Git\bin`, `C:\Program Files\Git\cmd`, `C:\Program Files\Python311`, `C:\Program Files\Python311\Scripts` foram adicionados ao PATH de máquina (nova sessão necessária para entrar em vigor).

**Não instalado (sem necessidade demonstrada):** .NET SDK, Visual Studio Build Tools/MSBuild, drivers gráficos, SDKs opcionais. O projeto é C#/WPF .NET Framework; a compilação da biblioteca de dados usa `csc.exe` do .NET Framework 4.8.

## Estado do repositório
- A pasta `d:\Desktop\winslim_fase7_r3_2_84` NÃO é um repositório Git acessível (não há `.git`).
- Não foram executados `git init`, `clone`, `reset` ou `clean`.
- Nenhum arquivo-fonte do projeto foi modificado.

## Arquivos criados nesta preparação

| Arquivo | Propósito |
|---------|-----------|
| `Configurar-Ambiente-R3.2.84.ps1` | Script PowerShell que adiciona Git/Python ao PATH da sessão e de máquina, verifica executáveis, versões, scripts de validação, hash do PresentMon e estado do repositório. |
| `Configurar-Ambiente-R3.2.84.bat` | Wrapper .bat equivalente para execução rápida. |
| `AMBIENTE-PREPARADO-R3.2.84.md` | Este resumo. |

## Arquivos de instalação baixados (mantidos em C:\WinslimDeps)

- `C:\WinslimDeps\Git-2.47.1-64-bit.exe` (69 MB)
- `C:\WinslimDeps\python-3.11.9-amd64.exe` (26 MB)

## Verificações a executar (abrir um NOVO shell do PowerShell)

```powershell
cd /d "d:\Desktop\winslim_fase7_r3_2_84"
.\Configurar-Ambiente-R3.2.84.ps1
```

Ou equivalente .bat:
```
.\Configurar-Ambiente-R3.2.84.bat
```

## Próximos passos para retomar a tarefa de transporte/preview do PresentMon

1. **Validar o ambiente** com o script acima (versões, executáveis, PATH, scripts de validação, hash do PresentMon).
2. **Executar os testes comportamentais pendentes** (sem recriar `PresentMonHarness`/`MonitorHarness`):
   - `tests/Test-Fase7-R3.2.84-CaptureTransport.ps1` — saída forçada (exit 7), pressão de pipes > 600 KB, callback de prévia com exceção.
   - `tests/Test-Fase7-R3.2.84-PresentMonData.ps1` — dados de captura, leitura CSV, argumentos, live reader.
   - `tests/Test-Fase7-R3.2.84-MonitorData.ps1` — monitor, gravação, cancelamento, stream de frames.
3. **Executar o gate completo:** `Validar-Regressoes.bat` (25 suítes) + self-test WPF (`Iniciar-Validacao.bat`).
4. **Diagnosticar e corrigir** falhas antes de avançar.
5. **Após gate aprovado:** roteiro Edge UI na VM e aceites físicos do PresentMon.
6. **Documentar** resultados em `tests/regression/cases.json` e logs de evidência (`Coletar-Diagnostico.bat`).

## Kaspersky e componentes retidos
- Kaspersky mantido ativo.
- Não foram instalados drivers gráficos, SDKs opcionais ou ferramentas sem uso demonstrado.
- Não foram aplicadas otimizações no computador do desenvolvedor durante regressões.

## Limitação desta sessão
O wrapper de execução de comandos envolve cada comando em colchetes `[]`, tornando impossível executar comandos arbitrários via `run_commands` neste shell. Os scripts `.ps1` e `.bat` acima devem ser executados manualmente em um novo shell do PowerShell.
