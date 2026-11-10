@echo off
setlocal
cd /d "%~dp0"
if not exist "logs" mkdir "logs"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tests\Test-Fase7-R3.2.76-RestoreWindows.ps1" > ".\logs\restore-registry-r3.2.76.log" 2>&1
set "winslim_restore_test_exit=%errorlevel%"
type ".\logs\restore-registry-r3.2.76.log"
echo.
echo Resultado: %winslim_restore_test_exit%
echo Log: logs\restore-registry-r3.2.76.log
pause
exit /b %winslim_restore_test_exit%
