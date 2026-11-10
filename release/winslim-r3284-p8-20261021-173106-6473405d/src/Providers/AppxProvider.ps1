function Test-AppxVerify {
    # Remoção de app NÃO é revertida pela engine (log avisa isso desde
    # sempre) - no undo, não finjo verificar um estado que nunca muda de
    # volta; devolvo um check informativo em vez de silêncio.
    param($Packages, [switch]$Undo)
    $checks = @()
    foreach ($pkg in @($Packages)) {
        if ($Undo) {
            $checks += [PSCustomObject]@{ Type = 'AppX'; Target = $pkg; Expected = '<não verificável>'; Actual = 'remoção de apps não é revertida pela engine'; Pass = $true }
        } else {
            $found = Get-AppxPackage -AllUsers -Name $pkg -ErrorAction SilentlyContinue
            $checks += [PSCustomObject]@{ Type = 'AppX'; Target = $pkg; Expected = 'removido'; Actual = $(if ($found) { 'ainda presente' } else { 'removido' }); Pass = (-not $found) }
        }
    }
    return @($checks)
}

# ============================================================================
# API COMPLETA DO PROVIDER (Fase 2) - regra explicita do backlog: o Win-Slim
# NUNCA deve prometer restauracao de AppX sem uma fonte valida pra reinstalar.
# Por isso Invoke-AppxProvider com Action='Undo' SEMPRE devolve Success=false
# com Warning explicando o motivo, em vez de fingir sucesso ou ficar em silencio.
# ============================================================================

function Get-AppxState {
    # Detect: instalado (para o usuario atual) E provisionado (para novos
    # usuarios) sao coisas DIFERENTES - um pacote pode estar desprovisionado
    # mas ainda instalado pro usuario atual, ou vice-versa.
    param([string]$PackageName)
    $installed = Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like "$PackageName*" -or $_.DisplayName -eq $PackageName }
    return [PSCustomObject]@{
        PackageName        = $PackageName
        Installed          = [bool]$installed
        InstalledFullName  = if ($installed) { ($installed | Select-Object -First 1).PackageFullName } else { $null }
        Provisioned        = [bool]$provisioned
        ProvisionedName    = if ($provisioned) { ($provisioned | Select-Object -First 1).PackageName } else { $null }
    }
}

function Remove-AppxPackageFull {
    # Remove tanto a instalacao atual quanto o provisionamento (evita o app
    # voltar pra contas novas criadas depois) - motor legado so fazia a
    # primeira parte.
    param([string]$PackageName)
    Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "$PackageName*" -or $_.DisplayName -eq $PackageName } |
        ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null }
}

function Invoke-AppxProvider {
    param(
        [Parameter(Mandatory)] [string]$Id,
        [Parameter(Mandatory)] [string]$PackageName,
        [ValidateSet('Apply', 'Undo')] [string]$Action = 'Apply'
    )
    $before = Get-AppxState -PackageName $PackageName

    if ($Action -eq 'Undo') {
        # Regra do backlog: nunca fingir que restaura. Devolve resultado
        # honesto, nao um "sucesso" vazio nem silencio.
        $undoCheck = [PSCustomObject]@{ Type = 'AppX'; Target = $PackageName; Expected = 'restauracao exata'; Actual = 'fonte de reinstalacao indisponivel'; Pass = $false }
        return New-ProviderResult -Id $Id -Action 'Undo' -Success $false -Changed $false `
            -StateBefore $before -StateAfter $before `
            -Verification ([PSCustomObject]@{ Success = $false; Checks = @($undoCheck) }) `
            -WarningMessage "Remoção de AppX não é reversível pelo Win-Slim: não existe fonte local válida (.appx/.msix) para reinstalar '$PackageName' com garantia de integridade. Reinstale manualmente pela Microsoft Store, se disponível." `
            -Restart 'Explorer'
    }

    $errorMsg = $null
    $changed = $false
    try {
        if ($before.Installed -or $before.Provisioned) {
            Remove-AppxPackageFull -PackageName $PackageName
            $changed = $true
        }
    } catch {
        $errorMsg = $_.Exception.Message
    }

    $after = Get-AppxState -PackageName $PackageName
    $verifyOk = -not $after.Installed -and -not $after.Provisioned
    $verifyChecks = @(
        [PSCustomObject]@{ Type = 'AppX'; Target = "$PackageName (instalado)"; Expected = 'removido'; Actual = $(if ($after.Installed) { 'presente' } else { 'removido' }); Pass = (-not $after.Installed) }
        [PSCustomObject]@{ Type = 'AppX'; Target = "$PackageName (provisionado)"; Expected = 'removido'; Actual = $(if ($after.Provisioned) { 'presente' } else { 'removido' }); Pass = (-not $after.Provisioned) }
    )

    return New-ProviderResult -Id $Id -Action 'Apply' -Success ([bool](-not $errorMsg -and $verifyOk)) -Changed $changed `
        -StateBefore $before -StateAfter $after `
        -Verification ([PSCustomObject]@{ Success = [bool]$verifyOk; Checks = $verifyChecks }) `
        -WarningMessage $(if ($verifyOk) { $null } else { 'Pacote pode ter sido removido só parcialmente (instalado ou provisionamento).' }) `
        -Restart 'Explorer' -ErrorMessage $errorMsg
}
