<#
    STUB - Fase 8 do backlog (Reboot Manager + Post-Reboot Verify).

    Hoje (v2/Fase1) o app só avisa "reinicie o computador" via MessageBox após
    o lote (ver Run-Batch). O que falta pra virar processo transacional de
    verdade, na ordem que o backlog descreve:

      Apply -> Verify -> requiresRestart? -> salvar ID da transação pendente
      -> Restart -> Windows inicia -> Win-Slim detecta transação pendente
      -> Post-Reboot Verify -> Commit

    Pré-requisito real: rodar isso depois que Transaction Manager (já existe,
    src/Core/Transaction.ps1) e o Reboot Manager conseguirem persistir o ID
    da transação em algum lugar que sobreviva ao reboot (ex.: um arquivo em
    $ScriptRoot, ou uma entrada de Registro em RunOnce apontando de volta pro
    Win-Slim.exe com um parâmetro "--resume-transaction <id>"). Isso também
    precisa da nova arquitetura de launcher (.exe com Engine/Providers como
    pastas) para conseguir se re-executar sozinho sem depender de irm|iex.

    Não implementado ainda de propósito - depende de Fase 2/3 (Providers reais)
    e da Fase 10 (Win-Slim.exe final) estarem prontas primeiro.
#>
function Register-PendingRestart {
    param($TransactionId)
    Write-Log "Restart Manager ainda não implementado (Fase 8). Transação $TransactionId não foi persistida para retomar pós-reboot." 'WARN'
}

function Resume-PendingRestart {
    Write-Log 'Restart Manager ainda não implementado (Fase 8). Nenhuma transação pendente será retomada automaticamente.' 'INFO'
    return $null
}
