#requires -Version 5.1
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$python=Join-Path $Root 'logs/dev-python313/python.exe'
if(-not (Test-Path -LiteralPath $python)){$python=(Get-Command python.exe -ErrorAction Stop).Source}
& $python -m unittest discover -s (Join-Path $Root 'tests') -p test_ci_evidence.py -v
exit $LASTEXITCODE
