# Versioned corrections are applied to the in-memory catalog before planner creation.
# Frozen catalog files and older releases remain unchanged.
function Set-WinSlimReviewedCatalog {
 param([object[]]$Tweaks)
 $tips=@($Tweaks | Where-Object {$_.id -ceq 'QOL-008'})
 if($tips.Count -ne 1){throw 'Contrato QOL-008 ausente ou duplicado.'}
 $t=$tips[0];$ops=@($t.registry)
 $old='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer'
 $correct='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
 if($t.type -cne 'registry' -or $ops.Count -ne 1 -or $ops[0].Path -notin @($old,$correct) -or $ops[0].Name -cne 'AllowOnlineTips' -or $ops[0].Type -cne 'DWord' -or [string]$ops[0].Value -cne '0'){
  throw 'Contrato QOL-008 inesperado; correcao automatica bloqueada.'
 }
 $ops[0].Path=$correct
 $t | Add-Member NoteProperty requiresAdmin $true -Force
 $t.description='Desativa a busca de dicas e ajuda online do aplicativo Configurações. Política de máquina para edições compatíveis; afeta todos os usuários. Não controla todas as sugestões do Windows ou da Store.'
 foreach($item in $Tweaks){
  switch -Exact ($item.id){
   'QOL-003' {$item.description='Mostra arquivos ocultos e protegidos do sistema no Explorer. Não concede permissões adicionais nem altera arquivos. A verificação confirma as preferências no Registro.'}
   'QOL-012' {$item.name='Acesso Rápido - Ocultar recentes e frequentes';$item.plainName='Ocultar recentes e frequentes no Explorador';$item.description='Oculta arquivos recentes e pastas frequentes do Acesso Rápido. Mantém pastas fixadas e arquivos; não apaga o histórico existente. Reabra o Explorer para conferir.'}
  }
 }
}
