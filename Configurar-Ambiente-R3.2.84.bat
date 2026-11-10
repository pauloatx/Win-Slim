@echo off
setlocal
cd /d "%~dp0"

:: Adiciona Git e Python ao PATH da sessao atual (nao requer reiniciar)
set "PATH=%PATH%;C:\Program Files\Git\bin;C:\Program Files\Git\cmd;C:\Program Files\Python311;C:\Program Files\Python311\Scripts"

echo ============================================================
echo  Configuracao do ambiente - Win-Slim Suite R3.2.84
echo ============================================================
echo.

echo --- Executaveis e versoes ---
echo Git:
"C:\Program Files\Git\bin\git.exe" --version 2>&1
echo.
echo Python:
"C:\Program Files\Python311\python.exe" --version 2>&1
echo.
echo PowerShell:
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -Command "$PSVersionTable.PSVersion" 2>&1
echo.
echo csc.exe (compilador C# .NET Framework):
if exist "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
    echo [OK] csc.exe encontrado.
) else (
    echo [FALTA] csc.exe nao encontrado.
)
echo.

echo --- Validacao de arquivos locais ---
for %%f in (Validar-Regressoes.bat Iniciar-Validacao.bat Coletar-Diagnostico.bat Executar-Regressoes.ps1) do (
    if exist "%%f" (echo [OK] %%f) else (echo [FALTA] %%f)
)
echo.

echo --- PresentMon oficial ---
if exist "third_party\PresentMon\PresentMon-2.6.0-x64.exe" (
    echo [OK] PresentMon-2.6.0-x64.exe encontrado.
    powershell -NoLogo -Command "(Get-FileHash 'third_party\PresentMon\PresentMon-2.6.0-x64.exe' -Algorithm SHA256).Hash" 2>&1
) else (
    echo [FALTA] PresentMon-2.6.0-x64.exe nao encontrado.
)
echo.

echo --- Repositorio Git ---
if exist ".git\HEAD" (
    echo [SIM] Pasta e um repositorio Git.
) else (
    echo [NAO] Pasta NAO e um repositorio Git acessível (nao executar init/clone/reset/clean automaticamente).
)
echo.

echo --- Conclusao ---
echo Se todos os itens acima estao [OK], o ambiente esta pronto.
echo Para usar git e python em novos shells, o PATH do sistema ja foi atualizado.
echo Abra um NOVO shell do PowerShell e rode: .\Configurar-Ambiente-R3.2.84.ps1
echo.

pause
exit /b 0
