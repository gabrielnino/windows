# Loaded only by the dedicated Aurora Terminal profile.
$posh = Join-Path $PSScriptRoot '../artifacts/bin/oh-my-posh.exe'
$theme = Join-Path $PSScriptRoot 'aurora.omp.json'
if (Test-Path -LiteralPath $posh) {
    & $posh init pwsh --config $theme | Invoke-Expression
}
if ($Host.Name -eq 'ConsoleHost') {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    if (-not [Console]::IsOutputRedirected) {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle InlineView
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
    Set-PSReadLineOption -Colors @{
        Command='#39FF14'; Parameter='#00FFFF'; String='#FFFF00'
        Number='#FF5FFF'; Comment='#B0B0B0'; Error='#FF5050'
        InlinePrediction='#A0A0A0'
    }
}
$ErrorView = 'ConciseView'
$PSStyle.FileInfo.Directory = "$([char]27)[38;2;0;255;255m"
. (Join-Path $PSScriptRoot 'file-icons.ps1')
Update-FormatData -PrependPath (Join-Path $PSScriptRoot 'files.format.ps1xml')
function global:aurora-help {
    Write-Host 'Aurora: Tab completa; flechas buscan por prefijo; Ctrl+R busca historial; Alt+Shift+D divide panel.'
    Write-Host 'PowerShell: Get-Error explica el ultimo error; Get-Content archivo.log -Tail 50 -Wait sigue un log.'
}
