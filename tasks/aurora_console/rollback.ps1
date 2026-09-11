[CmdletBinding()]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$start = Get-Date
$stamp = Get-Date -Format yyyyMMdd_HHmmss_fff
$log = Join-Path $PSScriptRoot "logs/rollback_$stamp.log"
$report = @{ TaskName='aurora_console_rollback'; StartTime=$start.ToString('o'); Hostname=$env:COMPUTERNAME; TriggeredBy=$env:USERNAME; Status='RUNNING'; DryRun=[bool]$DryRun }
try {
    $manifest = Get-Content (Join-Path $PSScriptRoot 'backups/manifest.json') -Raw | ConvertFrom-Json
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] [Step 1/2] Restoring Terminal configuration (DryRun=$DryRun)"
    Write-Host $line
    Add-Content $log $line
    if (-not $DryRun) {
        Copy-Item -LiteralPath $manifest.Target -Destination (Join-Path $PSScriptRoot "backups/before_rollback_$stamp.json")
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'backups/settings.original.json') -Destination $manifest.Target -Force
        if ((Get-FileHash -LiteralPath $manifest.Target).Hash -ne $manifest.Hash) { throw 'Restored hash mismatch' }
        & (Join-Path $PSScriptRoot 'font.ps1') -Remove
    }
    $report.Status = if ($DryRun) { 'DRY_RUN' } else { 'ROLLED_BACK' }
} catch { $report.Status='FAILED'; $report.Error=$_.Exception.Message; throw }
finally {
    $report.DurationSeconds=((Get-Date)-$start).TotalSeconds
    $report.EndTime=(Get-Date).ToString('o')
    $report | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot "reports/rollback_$stamp.json")
    $line="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO] [Step 2/2] $($report.Status)"
    Write-Host $line
    Add-Content $log $line
}
