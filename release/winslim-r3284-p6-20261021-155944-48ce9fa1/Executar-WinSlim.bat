@echo off
setlocal
cd /d "%~dp0"
title Win-Slim Suite - FASE 7 R1

echo ============================================================
echo  Win-Slim Suite - FASE 7 R1 / Nova UI
echo ============================================================
echo.

if not exist "WinSlimSuite.Fase7.ps1" (
    echo [ERRO] Nao encontrei WinSlimSuite.Fase7.ps1 nesta pasta.
    echo.
    pause
    exit /b 1
)

echo Iniciando nova interface...
echo O Windows pode solicitar permissao de Administrador.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%cd%\WinSlimSuite.Fase7.ps1"

if errorlevel 1 (
    echo.
    echo [ERRO] O Win-Slim terminou com codigo %errorlevel%.
    echo Rode tests\Test-Fase7-R1-UI.ps1 para diagnostico.
    pause
)
