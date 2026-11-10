# 1. LOG (definido antes da carga dos catálogos para registrar falhas de carga)
# ============================================================================
$script:LogBox = $null
$script:LogMaxBytes = 2MB
$script:LogWritesSinceCheck = 0

# Rotação: quando o arquivo passa do limite, mantém só a metade mais recente das linhas.
function Limit-LogSize {
    try {
        if (-not (Test-Path -LiteralPath $LogPath)) { return }
        $fi = Get-Item -LiteralPath $LogPath -ErrorAction Stop
        if ($fi.Length -le $script:LogMaxBytes) { return }
        $lines = [System.IO.File]::ReadAllLines($LogPath, [System.Text.Encoding]::UTF8)
        $keep = [int][Math]::Floor($lines.Count / 2)
        if ($keep -lt 1) { $keep = 1 }
        $tail = $lines[($lines.Count - $keep)..($lines.Count - 1)]
        $header = "[{0}] [INFO] Log rotacionado: {1} linhas antigas removidas (limite {2} MB)." -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), ($lines.Count - $keep), [int]($script:LogMaxBytes / 1MB)
        [System.IO.File]::WriteAllLines($LogPath, [string[]](@($header) + $tail), (New-Object System.Text.UTF8Encoding($true)))
    } catch { }
}
Limit-LogSize

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try { Add-Content -Path $LogPath -Value $line -Encoding UTF8 } catch { }
    $script:LogWritesSinceCheck++
    if ($script:LogWritesSinceCheck -ge 50) { $script:LogWritesSinceCheck = 0; Limit-LogSize }
    if ($script:LogBox) {
        try { $script:LogBox.Dispatcher.Invoke([Action]{ $script:LogBox.AppendText("$line`r`n"); $script:LogBox.ScrollToEnd() }) } catch { }
    }
}

# ============================================================================
# 1a. ERROS AMIGÁVEIS
#     Resumo em português simples para quem não é técnico + expander "Ver detalhes
#     técnicos" com a mensagem original, tipo da exceção e stack trace.
# ============================================================================
$script:Window = $null

function Get-FriendlyErrorSummary {
    param($Exception, [string]$Context)
    $ex = $Exception
    # Chamadas .NET que falham chegam embrulhadas em MethodInvocationException; a causa real é a interna.
    while ($ex -is [System.Management.Automation.MethodInvocationException] -and $ex.InnerException) { $ex = $ex.InnerException }
    $onde = if ($Context) { " ao tentar $Context" } else { '' }
    switch ($ex) {
        { $_ -is [System.UnauthorizedAccessException] -or $_ -is [System.Security.SecurityException] } {
            return "O Windows não deixou o programa alterar uma configuração protegida$onde. Feche o programa e abra de novo como Administrador."
        }
        { $_ -is [System.IO.FileNotFoundException] -or $_ -is [System.IO.DirectoryNotFoundException] -or $_ -is [System.Management.Automation.ItemNotFoundException] } {
            return "Um arquivo ou pasta que o programa precisava não foi encontrado$onde. Se você moveu ou apagou arquivos da pasta do programa, baixe-o novamente."
        }
        { $_ -is [System.Net.WebException] -or $_ -is [System.Net.Sockets.SocketException] } {
            return "Não foi possível se conectar à internet$onde. Verifique sua conexão e tente de novo."
        }
        { $_ -is [System.IO.IOException] } {
            return "Houve um problema ao ler ou gravar um arquivo$onde. Verifique se há espaço em disco e se o arquivo não está aberto em outro programa."
        }
        { $_ -is [System.ArgumentException] -and $_.Message -match 'JSON|Json' } {
            return "Um arquivo de configuração está com o conteúdo inválido$onde. Baixe o programa novamente para substituí-lo."
        }
        { $_ -is [System.Management.Automation.CommandNotFoundException] } {
            return "Um comando do Windows necessário não foi encontrado$onde. Sua versão do Windows pode não ter este recurso."
        }
        { $_ -is [System.TimeoutException] } {
            return "A operação demorou demais e foi interrompida$onde. Tente novamente."
        }
    }
    return "Algo deu errado$onde. Nada grave: o programa continua funcionando e você pode tentar de novo."
}

function Show-FriendlyError {
    param(
        [string]$Summary,
        [string]$Details = '',
        [string]$Title = 'Win-Slim Suite - Ops, algo deu errado',
        [string]$Icon = 'Warning'
    )
    try {
        $dlgXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Win-Slim Suite" SizeToContent="Height" Width="520" MinHeight="180" MaxHeight="640"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False"
        Background="#171A21" FontFamily="Segoe UI" Foreground="#E7E9EE">
    <Grid Margin="22,18,22,16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal">
            <TextBlock x:Name="DlgIcon" Text="!" FontSize="30" FontWeight="Bold" Foreground="#F2C744" Margin="0,0,14,0" VerticalAlignment="Top"/>
            <TextBlock x:Name="DlgTitle" FontSize="16" FontWeight="Bold" TextWrapping="Wrap" MaxWidth="410" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="DlgSummary" Grid.Row="1" FontSize="13" TextWrapping="Wrap" Margin="0,12,0,12" Foreground="#E7E9EE"/>
        <Expander x:Name="DlgExpander" Grid.Row="2" Header="Ver detalhes técnicos" Foreground="#9AA0AC" FontSize="12" Margin="0,0,0,10">
            <TextBox x:Name="DlgDetails" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" MaxHeight="260"
                     FontFamily="Consolas" FontSize="11" Background="#0B0D11" Foreground="#C9CDD6" BorderThickness="0" Padding="8" Margin="0,8,0,0"/>
        </Expander>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="DlgCopy" Content="Copiar detalhes" Padding="12,6" Margin="0,0,8,0" Background="#1E222B" Foreground="#E7E9EE" BorderBrush="#2A2F3A" Cursor="Hand"/>
            <Button x:Name="DlgOk" Content="OK" Padding="22,6" Background="#FF8C42" Foreground="#1A0F08" FontWeight="SemiBold" BorderThickness="0" Cursor="Hand" IsDefault="True" IsCancel="True"/>
        </StackPanel>
    </Grid>
</Window>
'@
        $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$dlgXaml)))
        $dlg.Title = $Title
        $dlg.FindName('DlgTitle').Text = $Title -replace '^Win-Slim Suite\s*-\s*', ''
        $dlg.FindName('DlgSummary').Text = $Summary
        $iconTb = $dlg.FindName('DlgIcon')
        if ($Icon -eq 'Error') { $iconTb.Text = 'x'; $iconTb.Foreground = '#F26D6D' }
        elseif ($Icon -eq 'Information') { $iconTb.Text = 'i'; $iconTb.Foreground = '#3FC97A' }
        $detailsText = if ($Details) { $Details.TrimEnd() + "`r`n`r`nLog completo: $LogPath" } else { "Log completo: $LogPath" }
        $dlg.FindName('DlgDetails').Text = $detailsText
        $dlg.FindName('DlgOk').Add_Click({ $dlg.Close() }.GetNewClosure())
        $dlg.FindName('DlgCopy').Add_Click({
            try { [System.Windows.Clipboard]::SetText("$Summary`r`n`r`n$detailsText") } catch { }
        }.GetNewClosure())
        if ($script:Window -and $script:Window.IsLoaded) { $dlg.Owner = $script:Window; $dlg.WindowStartupLocation = 'CenterOwner' }
        $dlg.ShowDialog() | Out-Null
    } catch {
        # Fallback: se até o diálogo amigável falhar, cai no MessageBox padrão.
        try { [System.Windows.MessageBox]::Show("$Summary`n`n$Details`n`nDetalhes no log:`n$LogPath", $Title, 'OK', $Icon) | Out-Null } catch { }
    }
}

function Format-ExceptionDetails {
    param($ErrorRecord)
    $ex = $ErrorRecord.Exception
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("Tipo: $($ex.GetType().FullName)")
    [void]$sb.AppendLine("Mensagem: $($ex.Message)")
    if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.PositionMessage) { [void]$sb.AppendLine($ErrorRecord.InvocationInfo.PositionMessage) }
    $inner = $ex.InnerException
    while ($inner) { [void]$sb.AppendLine("Causa: $($inner.GetType().Name): $($inner.Message)"); $inner = $inner.InnerException }
    if ($ex.StackTrace) { [void]$sb.AppendLine(); [void]$sb.AppendLine($ex.StackTrace) }
    return $sb.ToString()
}

# Invoke-Safe: reservado para AÇÕES DELIBERADAS. Interações leves usam try/catch
# simples SEM caixa de mensagem — só registram no log.
function Invoke-Safe {
    param([scriptblock]$Action, [string]$Context = 'ação')
    try { & $Action }
    catch {
        Write-Log "Erro em '$Context': $($_.Exception.Message)" 'ERROR'
        Show-FriendlyError -Summary (Get-FriendlyErrorSummary -Exception $_.Exception -Context $Context) -Details (Format-ExceptionDetails -ErrorRecord $_)
    }
}

# ============================================================================
