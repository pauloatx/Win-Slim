@echo off
setlocal
cd /d "%~dp0"
title Win-Slim Suite - FASE 7 R3.2.82 Native UI
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.82.ps1" -IfNeeded
if errorlevel 1 (
  echo.
  echo [ERRO] Nao foi possivel preparar a Native UI R3.2.82.
  echo Consulte .\logs\build-native-r3.2.82.log
  pause
  exit /b 1
)
start "" ".\bin\WinSlim.UI.Native.R3.2.82.exe" --root "."
endlocal
