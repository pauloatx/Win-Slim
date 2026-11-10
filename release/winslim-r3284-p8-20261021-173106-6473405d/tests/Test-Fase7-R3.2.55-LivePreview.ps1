param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src\UI\Native\R3_2_55\WinSlimLivePreview.ps1')
function Require([bool]$condition,[string]$message){if(-not $condition){throw $message}}
$registry=[pscustomobject]@{type='registry';registry=@([pscustomobject]@{Path='HKCU:\Fixture';Name='Value';Type='DWord';Value=1})}
$service=[pscustomobject]@{type='service';service=@([pscustomobject]@{Name='FixtureService';StartupType='Manual'})}
$other=[pscustomobject]@{type='script';script='throw "must never execute"'}
$plan=[pscustomobject]@{Fingerprint='fixture';ExecutionOrder=@([pscustomobject]@{TweakId='R';Tweak=$registry},[pscustomobject]@{TweakId='S';Tweak=$service},[pscustomobject]@{TweakId='X';Tweak=$other})}
$before=ConvertTo-Json -InputObject $plan -Depth 20 -Compress
$script:serviceReads=0
$readServices={ $script:serviceReads++; [pscustomobject]@{Name='FixtureService';StartMode='Manual';State='Running'} }
$equal={param($op) [pscustomobject]@{Exists=$true;Value=1;Kind='DWord'}}
$a=Get-WinSlimLivePreview $plan -RegistryReader $equal -ServiceReader $readServices
Require ($a.Summary.AlreadyConfigured -eq 2 -and $a.Summary.Unsupported -eq 1 -and $script:serviceReads -eq 1) 'Leituras e tipos nao suportados incorretos'
Require ($a.ReadOnly -and -not $a.CanApply -and -not $a.IsBackup -and $a.PlanFingerprint -eq 'fixture') 'Observacao nao pode autorizar aplicacao nem representar backup'
$missing={param($op) [pscustomobject]@{Exists=$false;Value=$null;Kind=$null}}
$b=Get-WinSlimLivePreview $plan -RegistryReader $missing -ServiceReader { @() }
Require ($b.Summary.NeedsChange -eq 1 -and $b.Summary.Unknown -eq 1) 'Valor ausente deve diferir de servico ausente'
$c=Get-WinSlimLivePreview $plan -RegistryReader {param($op) throw 'Access denied'} -ServiceReader {throw 'CIM unavailable'}
Require ($c.Summary.Unknown -eq 2 -and $c.Summary.AlreadyConfigured -eq 0) 'Falhas nao podem virar sucesso ou ausencia presumida'
$registry.registry[0].Type='String'
$d=Get-WinSlimLivePreview $plan -RegistryReader $equal -ServiceReader $readServices
Require ($d.Items[0].Status -eq 'NeedsChange') 'Tipo de registro diferente deve ser reconhecido'
$registry.registry[0].Type='DWord';$registry.registry[0].Value='<Remove>'
$e=Get-WinSlimLivePreview $plan -RegistryReader $missing -ServiceReader $readServices
Require ($e.Items[0].Status -eq 'AlreadyConfigured') 'Remocao de valor ausente ja corresponde ao destino'
$registry.registry[0].Value=1
Require ((ConvertTo-Json -InputObject $plan -Depth 20 -Compress) -ceq $before) 'Observacao nao pode alterar o plano'
$empty=Get-WinSlimLivePreview ([pscustomobject]@{Fingerprint='empty';ExecutionOrder=@()}) -RegistryReader {throw 'unexpected'} -ServiceReader {throw 'unexpected'}
Require ($empty.Items.Count -eq 0 -and $empty.Summary.Unknown -eq 0) 'Plano vazio deve ser preservado'
Write-Host 'Live preview: estados reais, falhas explicitas, tipos, plano preservado e leitura isolada OK'

$blocked=Get-WinSlimLivePreview -Plan $null -RegistryReader {throw 'unexpected'} -ServiceReader {throw 'unexpected'}
Require (-not $blocked.Available -and $blocked.Items.Count -eq 0) 'Plano bloqueado nao pode indicar observacao disponivel'
$registry.registry[0].PSObject.Properties.Remove('Value')
$invalid=Get-WinSlimLivePreview $plan -RegistryReader $equal -ServiceReader $readServices
Require ($invalid.Items[0].Status -eq 'Unknown') 'Operacao incompleta nao pode indicar sucesso'
Write-Host 'Plano bloqueado e operacao incompleta: OK'

# Regression: catalog HKU path must resolve directly to HKEY_USERS.
foreach($path in @('HKU\.DEFAULT\Control Panel\Keyboard','HKU:\.DEFAULT\Control Panel\Keyboard')){
 $resolved=Resolve-WinSlimPreviewRegistryPath $path
 Require ($resolved.Hive -eq [Microsoft.Win32.RegistryHive]::Users -and $resolved.SubPath -ceq '.DEFAULT\Control Panel\Keyboard') 'HKU deve preservar a hive Users e o caminho DEFAULT'
}
foreach($path in @('HKCU:\Software\Fixture','HKLM:\Software\Fixture')){
 $resolved=Resolve-WinSlimPreviewRegistryPath $path
 Require ($resolved.SubPath -ceq 'Software\Fixture') 'HKCU/HKLM devem preservar o caminho'
}
$unsupportedPath=$false
try{Resolve-WinSlimPreviewRegistryPath 'HKINVALID:\Fixture' | Out-Null}catch{$unsupportedPath=$true}
Require $unsupportedPath 'Hive invalida deve falhar explicitamente'

# Regression: Auto alone does not prove automatic delayed startup.
$delayedTweak=[pscustomobject]@{type='service';service=@([pscustomobject]@{Name='WSearch';StartupType='AutomaticDelayedStart'})}
$delayPlan=[pscustomobject]@{Fingerprint='delayed';ExecutionOrder=@([pscustomobject]@{TweakId='SVC-002';Tweak=$delayedTweak})}
$delayBefore=ConvertTo-Json -InputObject $delayPlan -Depth 20 -Compress
$autoSnapshot=[pscustomobject]@{Name='WSearch';StartMode='Auto';State='Running'}
$autoReader={ $autoSnapshot }
$delayOn={param($op)
 Require ($op.Path -ceq 'HKLM:\SYSTEM\CurrentControlSet\Services\WSearch' -and $op.Name -ceq 'DelayedAutoStart') 'Deve ler o indicador de atraso do servico correto'
 [pscustomobject]@{Exists=$true;Value=1;Kind='DWord'}
}
$f=Get-WinSlimLivePreview $delayPlan -RegistryReader $delayOn -ServiceReader $autoReader
Require ($f.Items[0].Status -eq 'AlreadyConfigured' -and $f.Items[0].Operations[0].Current.DelayedAutoStart -and $f.Items[0].Operations[0].Desired.DelayedAutoStart) 'Auto com atraso ativo deve corresponder ao destino'
$delayOff={param($op) [pscustomobject]@{Exists=$true;Value=0;Kind='DWord'}}
$g=Get-WinSlimLivePreview $delayPlan -RegistryReader $delayOff -ServiceReader $autoReader
Require ($g.Items[0].Status -eq 'NeedsChange') 'Auto sem atraso deve exigir mudanca'
$h=Get-WinSlimLivePreview $delayPlan -RegistryReader $missing -ServiceReader $autoReader
Require ($h.Items[0].Status -eq 'NeedsChange') 'Indicador ausente significa atraso desativado'
$delayedTweak.service[0].StartupType='Automatic'
$i=Get-WinSlimLivePreview $delayPlan -RegistryReader $delayOn -ServiceReader $autoReader
Require ($i.Items[0].Status -eq 'NeedsChange') 'Automatic comum deve diferir de automatico atrasado'
$j=Get-WinSlimLivePreview $delayPlan -RegistryReader $delayOff -ServiceReader $autoReader
Require ($j.Items[0].Status -eq 'AlreadyConfigured') 'Automatic comum sem atraso deve corresponder ao destino'
$delayedTweak.service[0].StartupType='AutomaticDelayedStart'
$k=Get-WinSlimLivePreview $delayPlan -RegistryReader {param($op) throw 'Access denied'} -ServiceReader $autoReader
Require ($k.Items[0].Status -eq 'Unknown') 'Acesso negado ao indicador nao pode virar atraso desativado'
$l=Get-WinSlimLivePreview $delayPlan -RegistryReader {param($op) [pscustomobject]@{Exists=$true;Value='1';Kind='String'}} -ServiceReader $autoReader
Require ($l.Items[0].Status -eq 'Unknown') 'Tipo invalido do indicador nao pode virar sucesso'
$m=Get-WinSlimLivePreview $delayPlan -RegistryReader {throw 'must not read missing service'} -ServiceReader {@()}
Require ($m.Items[0].Status -eq 'Unknown' -and $m.Items[0].Operations[0].Error -eq 'Servico ausente neste computador.') 'Servico removido deve continuar ausente'
Require ($autoSnapshot.PSObject.Properties.Name -notcontains 'DelayedAutoStart') 'Observacao nao pode modificar snapshot compartilhado'
Require ((ConvertTo-Json -InputObject $delayPlan -Depth 20 -Compress) -ceq $delayBefore) 'Observacao do atraso nao pode alterar plano'

# Num Lock contains both HKCU and HKU operations: both must be observed.
$numTweak=[pscustomobject]@{type='registry';registry=@(
 [pscustomobject]@{Path='HKCU:\Control Panel\Keyboard';Name='InitialKeyboardIndicators';Type='String';Value='2'},
 [pscustomobject]@{Path='HKU\.DEFAULT\Control Panel\Keyboard';Name='InitialKeyboardIndicators';Type='String';Value='2'}
)}
$numPlan=[pscustomobject]@{Fingerprint='numlock';ExecutionOrder=@([pscustomobject]@{TweakId='QOL-011';Tweak=$numTweak})}
$num=Get-WinSlimLivePreview $numPlan -RegistryReader {param($op)
 $resolved=Resolve-WinSlimPreviewRegistryPath $op.Path
 [pscustomobject]@{Exists=$true;Value='2';Kind='String'}
} -ServiceReader {throw 'unexpected'}
Require ($num.Items[0].Status -eq 'AlreadyConfigured' -and $num.Items[0].Operations.Count -eq 2) 'Num Lock deve verificar HKCU e HKU'
Write-Host 'R3.2.55: HKU, Num Lock, automatico atrasado, falhas e servicos removidos OK'
