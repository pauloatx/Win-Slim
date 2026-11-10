<#
    Win-Slim Suite - MMCSS Games Provider (Fase 5 R1)

    Perfil recuperado do backend Seal:
      GPU Priority        = DWORD 8
      Priority            = DWORD 6
      Scheduling Category = String "High"
      SFIO Priority       = String "High"

    O snapshot/rollback é delegado ao RegistryProvider para restaurar o
    estado EXATO anterior de cada valor, inclusive ausência original.
#>

function Get-WinSlimMmcssGamesRegistryOps {
    param(
        [string]$GamesPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    )

    return @(
        [PSCustomObject]@{ Path=$GamesPath; Name='GPU Priority';        Value=8;      Type='DWord'  }
        [PSCustomObject]@{ Path=$GamesPath; Name='Priority';            Value=6;      Type='DWord'  }
        [PSCustomObject]@{ Path=$GamesPath; Name='Scheduling Category'; Value='High'; Type='String' }
        [PSCustomObject]@{ Path=$GamesPath; Name='SFIO Priority';       Value='High'; Type='String' }
    )
}

function Invoke-MmcssGamesProvider {
    param(
        [Parameter(Mandatory)][string]$Id,
        [ValidateSet('Apply','Undo')][string]$Action = 'Apply',
        $BackupData = $null,
        [string]$GamesPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    )

    $ops = @(Get-WinSlimMmcssGamesRegistryOps -GamesPath $GamesPath)
    return Invoke-RegistryProvider -Id $Id -RegistryOps $ops -Action $Action -BackupData $BackupData
}
