<#
    Motor de aplicacao/desfazimento - AINDA monolitico de proposito.
    A separacao real por provider (cada um com seu proprio Apply/Detect,
    nao so Verify) e a Fase 2 do backlog, nao a Fase 1. Mexer nisso agora
    seria pular etapa - o Verify por provider ja esta pronto e vive em
    src/Providers/, e Invoke-TweakEngine abaixo ja delega pra funcoes
    especificas onde faz sentido (Set-RegistryValue etc.).
#>
function Invoke-Payload {
    param($Payload, [switch]$Undo)
    if ($Payload.registry) {
        foreach ($r in $Payload.registry) {
            if ($Undo -and $r.PSObject.Properties.Name -contains 'OriginalValue') {
                Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.OriginalValue -Type $r.Type
            } elseif (-not $Undo) {
                Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type
            }
        }
    }
    if ($Payload.service) {
        foreach ($s in $Payload.service) {
            $target = if ($Undo) { $s.OriginalType } else { $s.StartupType }
            if ($Undo -and -not $target) { continue }
            try {
                Set-Service -Name $s.Name -StartupType $target -ErrorAction SilentlyContinue
                if ($target -eq 'Automatic' -or $target -eq 'AutomaticDelayedStart') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
            } catch { Write-Log "Serviço $($s.Name) não encontrado, ignorado." 'WARN' }
        }
    }
    $scriptBlock = if ($Undo) { $Payload.UndoScript } else { $Payload.InvokeScript }
    if ($scriptBlock) { Invoke-Expression ($scriptBlock -join "`n") }
}

$script:SimulationMode = $false

# Motor de SIMULAÇÃO: espelha a estrutura do Invoke-TweakEngine real, mas em
# nenhum branch chama Set-RegistryValue, Set-Service, Invoke-Expression,
# Remove-AppxPackage ou qualquer outra função que grave algo no sistema.
# É um caminho de código totalmente separado de propósito - mais fácil de
# auditar "isso aqui não escreve nada" do que uma flag $Simulate espalhada
# por dentro do motor real.

function Invoke-TweakEngineSimulated {
    param($Tweak, [switch]$Undo, [int]$Level = -1)
    $mode = if ($Undo) { 'UNDO' } else { 'APPLY' }
    Write-Log "[SIMULAÇÃO/$mode] $($Tweak.id) - $($Tweak.name)" 'SIM'
    try {
        $payload = $Tweak
        if ($Tweak.type -eq 'multilevel') {
            $idx = if ($Level -lt 0) { 0 } else { $Level }
            $payload = $Tweak.levels[$idx]
        }
        foreach ($r in @($payload.registry)) {
            $cur = Get-CurrentRegistryState -Path $r.Path -Name $r.Name
            $curDisplay = if ($cur.Existed) { $cur.Value } else { '<ausente>' }
            $novo = if ($Undo) { $r.OriginalValue } else { $r.Value }
            Write-Log "  registro: $($r.Path)\$($r.Name)  atual=$curDisplay  seria->  $novo" 'SIM'
        }
        foreach ($s in @($payload.service)) {
            $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
            $curType = if ($svc) { $svc.StartType } else { '<serviço não encontrado>' }
            $novo = if ($Undo) { $s.OriginalType } else { $s.StartupType }
            Write-Log "  serviço: $($s.Name)  atual=$curType  seria->  $novo" 'SIM'
        }
        $scriptBlock = if ($Undo) { $payload.UndoScript } else { $payload.InvokeScript }
        if ($scriptBlock) { Write-Log "  script que SERIA executado:`n$($scriptBlock -join "`n")" 'SIM' }
        if ($Tweak.packages -and -not $Undo) { Write-Log "  pacotes que seriam removidos: $($Tweak.packages -join ', ')" 'SIM' }
        if ($Tweak.capabilityName -and -not $Undo) { Write-Log "  capability que seria removida: $($Tweak.capabilityName)*" 'SIM' }
        if ($Tweak.hosts) {
            $acao = if ($Undo) { 'removidas' } else { 'adicionadas' }
            Write-Log "  entradas do hosts file que seriam ${acao}: $($Tweak.hosts -join ', ')" 'SIM'
        }
        Write-Log "[SIMULAÇÃO/$mode] $($Tweak.id) -> nenhuma alteração real foi feita." 'SIM'
        return $true
    } catch {
        Write-Log "[SIMULAÇÃO/$mode] $($Tweak.id) falhou ao simular: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}


function Invoke-TweakEngine {
    param($Tweak, [switch]$Undo, [int]$Level = -1)
    if ($script:SimulationMode) { return Invoke-TweakEngineSimulated -Tweak $Tweak -Undo:$Undo -Level $Level }
    $mode = if ($Undo) { 'UNDO' } else { 'APPLY' }
    Write-Log "[$mode] $($Tweak.id) - $($Tweak.name)"
    try {
        if ($Tweak.type -eq 'multilevel') {
            if ($Undo) {
                if (Restore-FromSnapshot -TweakId $Tweak.id) {
                    Write-Log "[UNDO] $($Tweak.id) -> rollback profissional aplicado (estado real anterior restaurado)." 'OK'
                    return $true
                }
                $levelObj = $Tweak.levels[0]
                Invoke-Payload -Payload $levelObj
                Write-Log "[UNDO] $($Tweak.id) -> sem snapshot; aplicado nível padrão do catálogo." 'WARN'
                return $true
            } else {
                $idx = if ($Level -lt 0) { 0 } else { $Level }
                $levelObj = $Tweak.levels[$idx]
                Backup-BeforeApply -TweakId $Tweak.id -Payload $levelObj
                Invoke-Payload -Payload $levelObj
                Write-Log "[APPLY] $($Tweak.id) -> nível '$($levelObj.name)' aplicado (snapshot de rollback salvo)." 'OK'
                return $true
            }
        }

        if ($Undo) {
            if (Restore-FromSnapshot -TweakId $Tweak.id) {
                Write-Log "[UNDO] $($Tweak.id) -> rollback profissional aplicado (estado real anterior restaurado)." 'OK'
            } else {
                Invoke-Payload -Payload $Tweak -Undo
                Write-Log "[UNDO] $($Tweak.id) -> sem snapshot; usado valor padrão do catálogo." 'WARN'
            }
        } else {
            Backup-BeforeApply -TweakId $Tweak.id -Payload $Tweak
            Invoke-Payload -Payload $Tweak
        }

        if ($Tweak.packages -and -not $Undo) {
            foreach ($pkg in $Tweak.packages) {
                Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pkg } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            }
        } elseif ($Tweak.packages -and $Undo) {
            Write-Log "Apps removidos ($($Tweak.id)) não são reinstalados automaticamente. Use a Microsoft Store se precisar." 'WARN'
        }
        if ($Tweak.capabilityName -and -not $Undo) {
            try {
                $cap = Get-WindowsCapability -Online -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($Tweak.capabilityName)*" }
                if ($cap) { $cap | Remove-WindowsCapability -Online -ErrorAction SilentlyContinue | Out-Null }
            } catch { Write-Log "Capability $($Tweak.capabilityName) ausente, ignorado." 'WARN' }
        }
        if ($Tweak.hosts) {
            $hostsFile = "$Env:SystemRoot\System32\drivers\etc\hosts"
            $marker = "WinSlimSuite-$($Tweak.id)"
            $current = Get-Content $hostsFile -ErrorAction SilentlyContinue
            if ($Undo) {
                $filtered = $current | Where-Object { $_ -notmatch [regex]::Escape($marker) }
                Set-Content -Path $hostsFile -Value $filtered -Encoding ASCII
            } else {
                $existingLines = $current -join "`n"
                $toAdd = $Tweak.hosts | ForEach-Object { "0.0.0.0 $_  # $marker" } | Where-Object { $existingLines -notmatch [regex]::Escape($_) }
                if ($toAdd) { Add-Content -Path $hostsFile -Value $toAdd -Encoding ASCII }
            }
        }

        Write-Log "[$mode] $($Tweak.id) concluído com sucesso." 'OK'
        return $true
    } catch {
        Write-Log "[$mode] $($Tweak.id) FALHOU: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# ============================================================================
