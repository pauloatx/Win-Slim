@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.51.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Build falhou. Consulte logs\build-native-r3.2.51.log
  pause
  exit /b 1
)
if not exist "capturas" mkdir "capturas"
start "" /wait ".\bin\WinSlim.UI.Native.R3.2.51.exe" --root "." --capture-preset-tab Advanced --capture-presets "%~dp0capturas\Configuracoes-Avancado-R3.2.51.png"
if errorlevel 1 (
  echo [ERRO] Captura falhou. Consulte logs\ui-native-r3.2.51.log
  pause
  exit /b 1
)
if not exist "capturas\Configuracoes-Avancado-R3.2.51.png" (
  echo [ERRO] PNG nao foi gerado. Consulte logs\ui-native-r3.2.51.log
  pause
  exit /b 1
)
echo Captura salva em capturas\Configuracoes-Avancado-R3.2.51.png
pause
endlocal
