@echo off
setlocal
cd /d "%~dp0"
if not exist "logs" mkdir "logs"
powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ".\src\UI\Native\R3_2_60\WinSlim.UiBridge.ps1" -Action Gpu -RootPath "%CD%" > ".\logs\diagnostico-gpu-r3.2.60.json" 2> ".\logs\diagnostico-gpu-r3.2.60-error.log"
set "winslim_gpu_exit=%errorlevel%"
echo Resultado: %winslim_gpu_exit%
echo Diagnostico: logs\diagnostico-gpu-r3.2.60.json
if not "%winslim_gpu_exit%"=="0" type ".\logs\diagnostico-gpu-r3.2.60-error.log"
pause
exit /b %winslim_gpu_exit%
