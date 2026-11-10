<#
    STUB - Fase 5 do backlog (gap 'memory-compression-off', via Enable-MMAgent/
    Disable-MMAgent -MemoryCompression). Cmdlet estruturado (Get-MMAgent
    devolve .MemoryCompression booleano) - verify vai ser direto de
    implementar quando chegar a vez, sem risco de parsing de texto.
    Não implementado ainda de propósito - ver nota no PagefileProvider.ps1.
#>
function Test-MMAgentVerify {
    param($ScriptText)
    Write-Log 'MMAgentProvider ainda não implementado (Fase 5).' 'WARN'
    return @()
}
