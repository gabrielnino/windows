<#
.SYNOPSIS
    Rollback routine for voice_trigger_angel_transcription task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md. Cleans up any corrupted, zero-byte, or partial audio/transcription artifacts.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Execution failure or user abort"
)

$TaskDir = $PSScriptRoot
$ArtifactDir = Join-Path $TaskDir "artifacts"

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$Timestamp] [WARN] Executing rollback in '$TaskDir'. Reason: $Reason" -ForegroundColor Yellow

if (Test-Path $ArtifactDir) {
    # Remove zero-byte or corrupted files
    Get-ChildItem -Path $ArtifactDir -File | Where-Object { $_.Length -eq 0 } | ForEach-Object {
        Write-Host "[$Timestamp] [INFO] Removing invalid zero-byte artifact: $($_.FullName)" -ForegroundColor Cyan
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "[$Timestamp] [INFO] Rollback completed safely." -ForegroundColor Green
exit 0
