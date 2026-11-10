@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.42.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Build falhou. Consulte logs\build-native-r3.2.42.log
  pause
  exit /b 1
)
if not exist "capturas" mkdir "capturas"
start "" /wait ".\bin\WinSlim.UI.Native.R3.2.42.exe" --root "." --capture-apply "%~dp0capturas\Aplicacao-R3.2.42.png"
if errorlevel 1 (
  echo [ERRO] Captura falhou. Consulte logs\ui-native-r3.2.42.log
  pause
  exit /b 1
)
if not exist "capturas\Aplicacao-R3.2.42.png" (
  echo [ERRO] PNG nao foi gerado. Consulte logs\ui-native-r3.2.42.log
  pause
  exit /b 1
)
echo Captura salva em capturas\Aplicacao-R3.2.42.png
pause
endlocal
