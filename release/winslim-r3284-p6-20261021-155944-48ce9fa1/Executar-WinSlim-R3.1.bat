@echo off
setlocal
cd /d "%~dp0"

rem Win-Slim Suite - FASE 7 R3.1 / Correcao visual de layout
rem Mantem backend R4.1, Dashboard R2 e Presets/overlays R3.

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Windows PowerShell nao encontrado.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinSlimSuite.Fase7R3_1.ps1"
if errorlevel 1 (
  echo.
  echo [ERRO] O Win-Slim Suite R3.1 encerrou com erro.
  pause
)
endlocal
