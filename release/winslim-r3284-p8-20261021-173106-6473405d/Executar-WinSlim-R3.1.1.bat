@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinSlimSuite.Fase7R3_1_1.ps1"
if errorlevel 1 (
  echo.
  echo [ERRO] O Win-Slim Suite R3.1.1 encerrou com erro.
  pause
)
endlocal
