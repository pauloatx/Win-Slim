@echo off
setlocal
cd /d "%~dp0"
title Win-Slim R3.2.72 - Validacao com progresso visivel
 echo ============================================================
 echo Win-Slim R3.2.72 - Validacao de Aplicacao, Backup e Restauracao
 echo ============================================================
 echo O progresso aparecera nesta janela e sera salvo em logs.
 echo A verificacao inclui milhares de arquivos e pode levar minutos.
 echo Aguarde o resumo final. Ctrl+C interrompe a verificacao.
 echo.
if not exist ".\tests\Test-Fase7-R3.2.72-NativeUI.ps1" (
 echo [ERRO] Extraia estes arquivos dentro da pasta winslim_fase7_r3_2_70.
 echo O arquivo tests\Test-Fase7-R3.2.72-NativeUI.ps1 nao foi encontrado.
 pause
 exit /b 2
)
if not exist ".\Executar-Validacao-R3.2.72-Visivel.ps1" (
 echo [ERRO] O script de validacao visivel nao foi extraido.
 pause
 exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Executar-Validacao-R3.2.72-Visivel.ps1"
set "winslim_visible_exit=%errorlevel%"
echo.
echo Resultado da validacao: %winslim_visible_exit%
echo Log: logs\gate-native-r3.2.72-visivel.log
echo.
pause
exit /b %winslim_visible_exit%
