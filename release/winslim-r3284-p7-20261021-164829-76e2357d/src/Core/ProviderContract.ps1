<#
    Contrato único de Provider (Fase 2 / 2.1). Toda função Invoke-<X>Provider
    devolve exatamente este formato, para o Engine/Planner tratarem qualquer
    provider de forma genérica.

    Fase 2.1: os parâmetros de entrada se chamam ErrorMessage/WarningMessage
    (e não Error/Warning) para não colidir com o nome da variável automática
    $Error nem com os prefixos dos parâmetros comuns (-ErrorAction,
    -ErrorVariable, -WarningAction...). As PROPRIEDADES do resultado continuam
    Error e Warning, como o contrato exige.
#>
function New-ProviderResult {
    param(
        [string]$Id,
        [ValidateSet('Detect', 'Backup', 'Apply', 'Verify', 'Undo')] [string]$Action,
        [bool]$Success = $false,
        [bool]$Changed = $false,
        $StateBefore = $null,
        $StateAfter = $null,
        $Verification = $null,
        [string]$Restart = 'None',
        [string]$WarningMessage = $null,
        [string]$ErrorMessage = $null
    )
    return [PSCustomObject]@{
        Id           = $Id
        Action       = $Action
        Success      = $Success
        Changed      = $Changed
        StateBefore  = $StateBefore
        StateAfter   = $StateAfter
        Verification = $Verification
        Restart      = $Restart
        Warning      = $(if ([string]::IsNullOrEmpty($WarningMessage)) { $null } else { $WarningMessage })
        Error        = $(if ([string]::IsNullOrEmpty($ErrorMessage)) { $null } else { $ErrorMessage })
    }
}

function Invoke-NativeCommand {
    <#
        Executa um utilitário nativo (bcdedit, powercfg, fsutil...) e devolve
        ExitCode + Output. Roda com ErrorActionPreference='Continue' LOCAL,
        porque no Windows PowerShell 5.1 um "2>&1" sob preferência 'Stop'
        transforma qualquer linha de stderr em exceção terminante - o
        provider precisa decidir por ExitCode, não depender do humor do
        chamador (o harness usa Stop).
    #>
    param([Parameter(Mandatory)] [string]$FilePath, [string[]]$Arguments = @())
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = ''
    $code = $null
    try {
        $out = (& $FilePath @Arguments 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $out = $_.Exception.Message
        $code = -1
    } finally {
        $ErrorActionPreference = $previous
    }
    return [PSCustomObject]@{ ExitCode = $code; Output = $out }
}

function Assert-NativeCommandSuccess {
    <#
        Fase 2.1B: transforma ExitCode nativo != 0 em erro explicito DO PROVIDER.
        Invoke-NativeCommand deliberadamente nao lanca por stderr; esta funcao
        e usada somente quando o comando representa uma mutacao que precisa
        ter sido aceita pelo Windows antes de seguir para Verify.
    #>
    param(
        [Parameter(Mandatory)] $Result,
        [Parameter(Mandatory)] [string]$Operation
    )
    if ($null -eq $Result.ExitCode -or [int]$Result.ExitCode -ne 0) {
        $detail = if ($Result.Output) { ($Result.Output.ToString().Trim() -replace "`r?`n", ' | ') } else { '<sem saida>' }
        throw "$Operation falhou (ExitCode=$($Result.ExitCode)): $detail"
    }
    return $Result
}

function Join-CompareValue {
    # Formata valor de registro/estado para comparação por texto (arrays -> "1,2,3").
    param($Value)
    if ($null -eq $Value) { return '<nulo>' }
    if ($Value -is [System.Array]) { return (@($Value) -join ',') }
    return [string]$Value
}
