#requires -Version 5.1
param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
trap {Write-Host ('[ERRO] Report: '+$_.Exception.ToString());Write-Host $_.InvocationInfo.PositionMessage;exit 1}
Add-Type -AssemblyName System.Web.Extensions
Add-Type -Path (Join-Path $Root 'src/UI/Native/R3_2_84/ApplicationReport.cs')
$serializer=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:checks=0
function Check([bool]$Ok,[string]$Message){if(-not $Ok){throw $Message};$script:checks++;Write-Host ('[OK] Report: '+$Message)}
function New-Source {
 $serializer.DeserializeObject('{"verified":true,"changed":1,"unchanged":2,"items":[{"Id":"UI-001","Name":"Tema","Status":"AlreadyConfigured"},{"Id":"UI-001","Name":"Tema","Status":"AlreadyConfigured"},{"Id":"UI-010","Name":"Relogio","Status":"AppliedVerified"}],"excluded":[{"Id":"UI-023","Name":"Destaques","Reason":"Edicao fora da cobertura"}],"errors":[],"backupId":"fixture","profile":"Fixture","utc":"2026-10-17T20:11:12Z","reportPath":"C:\\Fixture\\outcome.json"}')
}
$source=New-Source;$original=$serializer.Serialize($source);$report=[WinSlim.NativeUI.ApplicationReport]::Create($source)
Check ($report.Verified -and $report.Rows.Count -eq 3 -and $report.Values -eq 3 -and $report.Applied -eq 1 -and $report.Unchanged -eq 2 -and $report.Excluded -eq 1) 'contagem de valores e ajustes distintos preservada'
Check ($report.Rows[0].Id -ceq 'UI-001' -and $report.Rows[0].Unchanged -eq 2 -and $report.Rows[0].Details.Count -eq 2) 'dois valores de um ajuste agrupados'
Check ($report.ToText().Contains('Edicao fora da cobertura') -and $report.ToText().Contains('C:\Fixture\outcome.json')) 'texto informa exclusao e origem'
Check ($serializer.Serialize($source) -ceq $original) 'geracao nao modifica o resultado original'
$source=New-Source;$source['changed']=9;$bad=[WinSlim.NativeUI.ApplicationReport]::Create($source)
Check (-not $bad.Verified -and $bad.ToText().Contains('não correspondem')) 'divergencia de contadores exige revisao'
$source=New-Source;$source['verified']=$false;Check (-not ([WinSlim.NativeUI.ApplicationReport]::Create($source)).Verified) 'resultado nao verificado nunca aprovado'
$source=New-Source;$source['errors']=@('fixture disk failure');Check (-not ([WinSlim.NativeUI.ApplicationReport]::Create($source)).Verified) 'erro explicito impede status verificado'
foreach($status in @('UnknownStatus','RecoveryIncomplete','RolledBack','NotApplied','Failed','Error')){
 $source=New-Source;$source['items'][2]['Status']=$status;$source['changed']=0
 $bad=[WinSlim.NativeUI.ApplicationReport]::Create($source)
 Check (-not $bad.Verified -and $bad.Rows[1].Other -eq 1 -and $bad.ToText().Contains([WinSlim.NativeUI.ApplicationReport]::StatusLabel($status))) ('status conservador '+$status)
}
$source=New-Source;$source['profile']='<script>alert("x")</script>';$source['items'][0]['Name']='<img src=x onerror=alert(1)>';$source['excluded'][0]['Reason']='<svg onload=alert(1)>'
$html=([WinSlim.NativeUI.ApplicationReport]::Create($source)).ToHtml()
Check (-not $html.Contains('<script>') -and -not $html.Contains('<img ') -and -not $html.Contains('<svg ') -and $html.Contains('&lt;script&gt;')) 'HTML trata conteudo como texto e escapa marcacao'
Check ($html.Contains('<details>') -and $html.Contains('prefers-color-scheme:light')) 'HTML possui detalhes e suporte ao tema claro'
$source=New-Source;$source['items']=@();$source['changed']=0;$source['unchanged']=0
Check (-not ([WinSlim.NativeUI.ApplicationReport]::Create($source)).Verified) 'resultado vazio nao vira sucesso'
$source=New-Source;$source['items'][0]['Id']=''
Check (-not ([WinSlim.NativeUI.ApplicationReport]::Create($source)).Verified) 'item sem ID requer revisao'
# A real-outcome-shaped fixture matches the eight-value Home result without claiming policy acceptance.
$source=New-Source;$source['changed']=2;$source['unchanged']=6
$source['items']=$serializer.DeserializeObject('[{"Id":"UI-001","Name":"Tema","Status":"AlreadyConfigured"},{"Id":"UI-001","Name":"Tema","Status":"AlreadyConfigured"},{"Id":"UI-010","Name":"Relogio","Status":"AppliedVerified"},{"Id":"UI-017","Name":"Mouse","Status":"AlreadyConfigured"},{"Id":"UI-017","Name":"Mouse","Status":"AlreadyConfigured"},{"Id":"UI-017","Name":"Mouse","Status":"AlreadyConfigured"},{"Id":"UI-021","Name":"Pesquisa","Status":"AppliedVerified"},{"Id":"UI-021","Name":"Pesquisa","Status":"AlreadyConfigured"}]')
$source['excluded']=$serializer.DeserializeObject('[{"Id":"UI-023","Name":"Destaques","Reason":"Nao confirmado"},{"Id":"UI-024","Name":"Sites","Reason":"Nao confirmado"}]')
$report=[WinSlim.NativeUI.ApplicationReport]::Create($source)
Check ($report.Verified -and $report.Rows.Count -eq 6 -and $report.Values -eq 8 -and $report.Applied -eq 2 -and $report.Unchanged -eq 6 -and $report.Excluded -eq 2) 'oito valores quatro ajustes cobertos e dois excluidos sem duplicacao'
. (Join-Path $Root 'src/UI/Native/R3_2_84/WinSlim.UiBridge.ps1') -LibraryOnly -RootPath $Root
$items=@([pscustomobject]@{Category='UI / QoL';Risk='Baixo';RequiresRestart=$false},[pscustomobject]@{Category='UI/QoL';Risk='Alto';RequiresRestart=$true},[pscustomobject]@{Category='Rede';Risk='Médio';RequiresRestart=$false})
$before=ConvertTo-Json -InputObject $items -Depth 8
$categories=@(Get-WinSlimPreviewCategories $items)
$ui=@($categories | Where-Object {$_.name -ceq 'UI / QoL'})
Check ($categories.Count -eq 2 -and $ui.Count -eq 1 -and $ui[0].count -eq 2 -and $ui[0].risk -ceq 'Alto' -and $ui[0].restartCount -eq 1) 'aliases de categoria agrupam quantidades maior risco e reinicio'
Check ((ConvertTo-Json -InputObject $items -Depth 8) -ceq $before) 'normalizacao visual nao muda itens nem catalogo'
Check (@(Get-WinSlimPreviewCategories @()).Count -eq 0) 'lista vazia nao inventa categoria'
$real=@($script:AllTweaks | Where-Object {$_.id -in @('UI-001','UI-010','UI-017','UI-021','UI-023','UI-024')} | ForEach-Object {[pscustomobject]@{Category=$_.category;Risk=$_.risk;RequiresRestart=$_.requiresRestart}})
$categories=@(Get-WinSlimPreviewCategories $real)
Check ($categories.Count -eq 1 -and $categories[0].count -eq 6 -and $categories[0].name -ceq 'UI / QoL') 'lote real de seis ajustes ocupa uma unica linha de categoria'
Write-Host ('Report: '+$script:checks+' verificacoes. Apresentacao pura; nenhum acesso de escrita ao Registro ou backup.')
