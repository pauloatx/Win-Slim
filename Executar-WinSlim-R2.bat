@echo off
setlocal
cd /d "%~dp0"
title Win-Slim Suite - FASE 7 R2

echo ============================================================
echo  Win-Slim Suite - FASE 7 R2 / Dashboard + Hardware
echo ============================================================
echo.

if not exist "WinSlimSuite.Fase7R2.ps1" (
    echo [ERRO] Nao encontrei WinSlimSuite.Fase7R2.ps1 nesta pasta.
    echo.
    pause
    exit /b 1
)

echo Iniciando FASE 7 R2...
echo O Windows pode solicitar permissao de Administrador.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%cd%\WinSlimSuite.Fase7R2.ps1"

if errorlevel 1 (
    echo.
    echo [ERRO] O Win-Slim terminou com codigo %errorlevel%.
    echo Rode tests\Test-Fase7-R2-UI.ps1 para diagnostico.
    pause
)
