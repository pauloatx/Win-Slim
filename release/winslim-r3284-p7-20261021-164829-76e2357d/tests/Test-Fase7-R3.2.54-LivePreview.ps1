param([string]$Root=(Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $Root 'src\UI\Native\R3_2_54\WinSlimLivePreview.ps1')
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
