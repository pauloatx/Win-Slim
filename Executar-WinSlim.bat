@echo off
REM Executa o WinSlimSuite.ps1 ignorando a politica de execucao.
REM O proprio script pede elevacao (UAC) sozinho, entao so clique em "Sim" quando aparecer.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WinSlimSuite.ps1"
pause
