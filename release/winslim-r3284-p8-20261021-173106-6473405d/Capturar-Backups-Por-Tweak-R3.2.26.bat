@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Build-NativeUI-R3.2.26.ps1" -IfNeeded
if errorlevel 1 (
  echo [ERRO] Build falhou. Consulte logs\build-native-r3.2.26.log
  pause
  exit /b 1
)
if not exist "capturas" mkdir "capturas"
start "" /wait ".\bin\WinSlim.UI.Native.R3.2.26.exe" --root "." --backup-tweaks --capture-backups "%~dp0capturas\Backups-Por-Tweak-R3.2.26.png"
if errorlevel 1 (
  echo [ERRO] Captura falhou. Consulte logs\ui-native-r3.2.26.log
  pause
  exit /b 1
)
if not exist "capturas\Backups-Por-Tweak-R3.2.26.png" (
  echo [ERRO] PNG nao foi gerado. Consulte logs\ui-native-r3.2.26.log
  pause
  exit /b 1
)
echo Captura salva em capturas\Backups-Por-Tweak-R3.2.26.png
pause
endlocal
