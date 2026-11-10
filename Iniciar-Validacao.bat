@echo off
setlocal
cd /d "%~dp0"
set "winslim_candidate_options="
if /I "%~1"=="/ci" set "winslim_candidate_options=-NoLaunch"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Validar-Candidato-R3.2.84.ps1" -Root "%~dp0." %winslim_candidate_options%
set "winslim_candidate_exit=%errorlevel%"
echo.
echo Resultado: %winslim_candidate_exit%
if /I not "%~1"=="/ci" pause
exit /b %winslim_candidate_exit%
