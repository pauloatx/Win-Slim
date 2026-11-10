@echo off
setlocal
cd /d "%~dp0"
title Win-Slim Suite - FASE 7 R3.2.24 Native UI
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.24.ps1" -IfNeeded
if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel preparar a Native UI R3.2.24.
  echo Consulte .\logs\build-native-r3.2.24.log
  pause
  exit /b 1
)
start "" ".\bin\WinSlim.UI.Native.R3.2.24.exe" --root "."
endlocal
