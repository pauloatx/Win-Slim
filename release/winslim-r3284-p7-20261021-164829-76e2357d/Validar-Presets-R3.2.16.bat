@echo off
setlocal
cd /d "%~dp0"
if not exist "logs" mkdir "logs"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-Fase7-R3.2.16-NativeUI.ps1" > ".\logs\gate-native-r3.2.16.log" 2>&1
set "winslim_gate_exit=%errorlevel%"
type ".\logs\gate-native-r3.2.16.log"
echo.
echo Resultado do gate: %winslim_gate_exit%
echo Log: logs\gate-native-r3.2.16.log
pause
exit /b %winslim_gate_exit%
