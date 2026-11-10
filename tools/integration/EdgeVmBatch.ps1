#requires -Version 5.1
# Explicit reviewed batches only. This module does not start any process or write policies.
function Get-WinSlimEdgeVmBatch([string]$Name) {
    switch -CaseSensitive ($Name) {
        'Identity' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-009','EDGE-010','EDGE-017');Fixture='Test-Fase7-R3.2.84-EdgeCompletion.ps1'} }
        'Forms' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-014','EDGE-015','EDGE-028','EDGE-030');Fixture='Test-Fase7-R3.2.84-EdgeCompletion.ps1'} }
        'Services' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-013','EDGE-021','EDGE-022','EDGE-023','EDGE-026','EDGE-027','EDGE-029');Fixture='Test-Fase7-R3.2.84-EdgeCompletion.ps1'} }
        'Diagnostics' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-018','EDGE-031');Fixture='Test-Fase7-R3.2.84-EdgeCompletion.ps1'} }
        'Sleep' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-006','EDGE-007');SelectedIds=@('EDGE-007');Fixture='Test-Fase7-R3.2.84-EdgeCompletion.ps1'} }
        'Next' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-008','EDGE-011','EDGE-012','EDGE-016');Fixture='Test-Fase7-R3.2.84-EdgeNext.ps1'} }
        'Startup' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-001','EDGE-002');Fixture='Test-Fase7-R3.2.84-Edge.ps1'} }
        'Privacy' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-019','EDGE-020','EDGE-024','EDGE-025');Fixture='Test-Fase7-R3.2.84-EdgePrivacy.ps1'} }
        'Core' { return [pscustomobject]@{Name=$Name;Ids=@('EDGE-003','EDGE-004','EDGE-005','EDGE-006');Fixture='Test-Fase7-R3.2.84-EdgeBatch.ps1'} }
        default { throw 'Unknown reviewed Edge VM batch; no default expansion is permitted.' }
    }
}
