@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Executar-Regressoes.ps1" -Root "%CD%"
set "winslim_regression_exit=%errorlevel%"
echo.
echo Resultado: %winslim_regression_exit%
echo Os relatorios estao na pasta logs, subpasta regressao-...
pause
exit /b %winslim_regression_exit%
