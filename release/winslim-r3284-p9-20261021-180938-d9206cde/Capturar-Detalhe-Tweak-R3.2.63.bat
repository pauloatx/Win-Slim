@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.63.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Nao foi possivel preparar a Native UI. Consulte logs\build-native-r3.2.63.log
  pause
  exit /b 1
)
.\bin\WinSlim.UI.Native.R3.2.63.exe --root "." --capture-tweak-detail ".\reports\Detalhe-Tweak-R3.2.63.png" --tweak-id "PERF-004"
endlocal
