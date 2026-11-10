@echo off
setlocal
cd /d "%~dp0"
title Win-Slim Suite - FASE 7 R3.2.2 Native UI
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.2.ps1" -IfNeeded
if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel compilar a Native UI R3.2.2.
  echo Consulte logs\build-native-r3.2.2.log para o diagnostico completo.
  echo Pressione qualquer tecla para sair.
  pause >nul
  exit /b 1
)
start "" ".\bin\WinSlim.UI.Native.R3.2.2.exe" --root "%~dp0"
exit /b 0
