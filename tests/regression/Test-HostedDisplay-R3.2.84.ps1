#requires -Version 5.1
<#
  Regression for the hosted display preparation used by the native WPF self-test.

  The native self-test requires the window to keep the contracted 1180x760
  size. A session whose working area is smaller makes the operating system
  constrain the window, so the environment - not the product - decides the
  result. This test proves the preparation tool: it reports the real state,
  refuses impossible requirements, never changes the display when only
  probing, and observes the real window contract with the application XAML.
#>
param([string]$Root=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$ErrorActionPreference='Stop'
$tool=Join-Path $Root 'tools/validation/HostedDisplayPreparation.ps1'
$checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] '+$Message)}
function Reject([scriptblock]$Action,[string]$Message){$failed=$false;try{& $Action | Out-Null}catch{$failed=$true};Check $failed $Message}

function Invoke-Tool {
    param([string[]]$Arguments)
    # The tool reports refusals on stderr; the contract is the exit code, not the stream.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $tool @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode=$code; Output=($output | Out-String) }
}

$fixture = Join-Path $Root ('logs/hosted-display-fixture-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
try {
    $receiptPath = Join-Path $fixture 'receipt.json'
    $before = Invoke-Tool -Arguments @('-ProbeOnly','-MinimumWidth','1200','-MinimumHeight','800','-EvidencePath',$receiptPath)
    Check ($before.ExitCode -eq 0) 'probe do ambiente concludes com sucesso quando a area de trabalho atinge o minimo'
    Check (Test-Path -LiteralPath $receiptPath) 'o recibo de evidencia e escrito'
    $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Check ([int]$receipt.schemaVersion -eq 1) 'o recibo declara a versao de esquema'
    Check ([string]$receipt.ContractedWindow -eq '1180x760') 'o recibo declara a janela contratada que o self-test exige'
    Check ([string]$receipt.Mode -eq 'ProbeOnly') 'o recibo declara que o modo apenas observa'
    Check ([bool]$receipt.SatisfiesRequirement -eq ([int]$receipt.FinalWidth -ge 1200 -and [int]$receipt.FinalHeight -ge 800)) 'o recibo satisfacao corresponde a area de trabalho observada'
    Check ([string]$receipt.Final -eq [string]$receipt.Before) 'o modo ProbeOnly nao altera a area de trabalho'

    $impossible = Join-Path $fixture 'impossible.json'
    $refused = Invoke-Tool -Arguments @('-ProbeOnly','-MinimumWidth','16000','-MinimumHeight','16000','-EvidencePath',$impossible)
    Check ($refused.ExitCode -ne 0) 'requisito impossivel reprova em vez de aprovado'
    Check (Test-Path -LiteralPath $impossible) 'o recibo e escrito mesmo quando o requisito nao e atingido'
    $refusedReceipt = Get-Content -LiteralPath $impossible -Raw -Encoding UTF8 | ConvertFrom-Json
    Check (-not [bool]$refusedReceipt.SatisfiesRequirement) 'o recibo reprovado nao declara satisfacao'
    Check ([string]$refusedReceipt.Final -eq [string]$refusedReceipt.Before) 'a recusa tambem nao altera a area de trabalho'

    $probePath = Join-Path $fixture 'probe.json'
    $probed = Invoke-Tool -Arguments @('-ProbeOnly','-Diagnose','-EvidencePath',$probePath)
    Check ($probed.ExitCode -eq 0) 'o diagnostico do contrato da janela conclui com sucesso'
    $probeReceipt = Get-Content -LiteralPath $probePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Check ($null -ne $probeReceipt.Probe) 'o recibo inclui a medicao real da janela'
    $probe = $probeReceipt.Probe
    Check ([string]$probe.afterXaml -eq '1180x760') 'o XAML da aplicacao declara a janela contratada 1180x760'
    $fits = ([int]$probe.workingAreaWidth -ge 1180 -and [int]$probe.workingAreaHeight -ge 760)
    Check ([bool]$probe.contractFits -eq $fits) 'o diagnostico declara a compatibilidade com a area de trabalho observada'
    if (-not $fits) {
        Check (-not [bool]$probe.contractHeld) 'quando a area de trabalho nao comporta a janela, o contrato nao e declarado como cumprido'
    } else {
        Check ([bool]$probe.contractHeld) 'quando a area de trabalho comporta a janela, o SO preserva 1180x760'
    }
    Check ([string]$probeReceipt.Final -eq [string]$probeReceipt.Before) 'o diagnostico nao altera a area de trabalho'

    $after = Invoke-Tool -Arguments @('-ProbeOnly','-MinimumWidth','1200','-MinimumHeight','800','-EvidencePath',(Join-Path $fixture 'after.json'))
    Check ($after.ExitCode -eq 0) 'o ambiente continua utilizavel apos as execucoes de teste'
    $afterReceipt = Get-Content -LiteralPath (Join-Path $fixture 'after.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Check ([string]$afterReceipt.Final -eq [string]$receipt.Final) 'a area de trabalho do Developer nao foi alterada pela suite'
    Write-Host ('HostedDisplayPreparation: '+$checks+' behavioral checks passed.')
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
