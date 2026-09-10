@echo off
setlocal
title Win-Slim Suite - Launcher

REM Muda para a pasta onde este .bat esta, nao importa de onde foi chamado.
cd /d "%~dp0"

echo Pasta atual: %cd%
echo.

if not exist "WinSlimSuite.ps1" (
    echo [ERRO] Nao encontrei WinSlimSuite.ps1 nesta pasta.
    echo Verifique se o .bat, o WinSlimSuite.ps1 e o catalog.json estao TODOS
    echo na mesma pasta apos extrair o zip.
    echo.
    pause
    exit /b 1
)

if not exist "catalog.json" (
    echo [AVISO] Nao encontrei catalog.json nesta pasta.
    echo O script pode falhar ao carregar os tweaks.
    echo.
)

echo Iniciando Win-Slim Suite...
echo Se aparecer o prompt do Windows pedindo permissao, clique em SIM.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%cd%\WinSlimSuite.ps1"

echo.
echo Script finalizado. Se fechou sem abrir nada, veja a mensagem de erro acima.
pause
