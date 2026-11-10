@echo off
setlocal
cd /d "%~dp0"

rem Win-Slim Suite - FASE 7 R3 / Presets + overlays condicionais
rem Executa o launcher R3 em Windows PowerShell 5.1.

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Windows PowerShell nao encontrado.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinSlimSuite.Fase7R3.ps1"
if errorlevel 1 (
  echo.
  echo [ERRO] O Win-Slim Suite R3 encerrou com erro.
  pause
)
endlocal
