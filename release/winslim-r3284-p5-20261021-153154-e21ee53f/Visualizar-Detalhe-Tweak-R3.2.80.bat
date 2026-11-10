@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.80.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Nao foi possivel preparar a Native UI. Consulte logs\build-native-r3.2.80.log
  pause
  exit /b 1
)
start "" .\bin\WinSlim.UI.Native.R3.2.80.exe --root "." --show-tweak-detail "PERF-004"
endlocal
