@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.19.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Build falhou. Consulte logs\build-native-r3.2.19.log
  pause
  exit /b 1
)
if not exist "capturas" mkdir "capturas"
start "" /wait ".\bin\WinSlim.UI.Native.R3.2.19.exe" --root "." --capture-preset-tab About --capture-presets "%~dp0capturas\Presets-Sobre-R3.2.19.png"
if errorlevel 1 (
  echo [ERRO] Captura falhou. Consulte logs\ui-native-r3.2.19.log
  pause
  exit /b 1
)
if not exist "capturas\Presets-Sobre-R3.2.19.png" (
  echo [ERRO] PNG nao foi gerado. Consulte logs\ui-native-r3.2.19.log
  pause
  exit /b 1
)
echo Captura salva em capturas\Presets-Sobre-R3.2.19.png
pause
endlocal
