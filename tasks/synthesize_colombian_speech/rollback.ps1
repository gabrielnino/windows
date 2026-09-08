<#
.SYNOPSIS
    Rollback routine for synthesize_colombian_speech task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md. Cleans up any corrupted or incomplete audio artifacts.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or automated execution rollback"
)

$TaskDir = $PSScriptRoot
$ArtifactDir = Join-Path $TaskDir "artifacts"
$LogDir = Join-Path $TaskDir "logs"

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$Timestamp] [WARN] Executing rollback in '$TaskDir'. Reason: $Reason" -ForegroundColor Yellow

# Clean up empty or 0-byte mp3 files in artifacts
if (Test-Path $ArtifactDir) {
    Get-ChildItem -Path $ArtifactDir -Filter "*.mp3" | Where-Object { $_.Length -eq 0 } | ForEach-Object {
        Write-Host "[$Timestamp] [INFO] Removing corrupted artifact: $($_.FullName)" -ForegroundColor Cyan
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[$Timestamp] [INFO] Rollback completed safely." -ForegroundColor Green
exit 0
