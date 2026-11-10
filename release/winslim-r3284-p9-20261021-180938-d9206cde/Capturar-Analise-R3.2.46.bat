@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.46.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Build falhou. Consulte logs\build-native-r3.2.46.log
  pause
  exit /b 1
)
if not exist "capturas" mkdir "capturas"
start "" /wait ".\bin\WinSlim.UI.Native.R3.2.46.exe" --root "." --capture-analysis "%~dp0capturas\Analise-R3.2.46.png"
if errorlevel 1 (
  echo [ERRO] Captura falhou. Consulte logs\ui-native-r3.2.46.log
  pause
  exit /b 1
)
if not exist "capturas\Analise-R3.2.46.png" (
  echo [ERRO] PNG nao foi gerado. Consulte logs\ui-native-r3.2.46.log
  pause
  exit /b 1
)
echo Captura salva em capturas\Analise-R3.2.46.png
pause
endlocal
