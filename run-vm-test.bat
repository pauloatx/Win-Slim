@echo off
"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\WinSlim-Codex-VirtualBox-Pacote-Unico\WinSlim-VirtualBox.ps1" -VM "teste win-slim-win11" -Acao Executar -UsarCredencialSalva -Snapshot WINSLIM_BASELINE -Teste winslim-r3284-p4-20261110-200716-4cf1fa27\Test-WinSlimVmCandidate.ps1 -RestaurarAntes -RestaurarDepois
