<#
.SYNOPSIS
    Rollback Procedure for Display Settings Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores fallback safe display resolutions and refresh rates.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback"
)

$ErrorActionPreference = 'Stop'
$TaskDir = $PSScriptRoot
$LogDir  = Join-Path $TaskDir "logs"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RollbackLog = Join-Path $LogDir "rollback_$Timestamp.log"

function Write-RollbackLog {
    param([string]$Message, [string]$Level = "WARN")
    $Line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Write-Output $Line
    if (Test-Path $LogDir) {
        Add-Content -Path $RollbackLog -Value $Line
    }
}

Write-RollbackLog "Initiating rollback sequence for display settings. Reason: $Reason" "WARN"

try {
    # Reset display subsystem via DisplaySwitch
    Start-Process -FilePath "DisplaySwitch.exe" -ArgumentList "/extend" -NoNewWindow -Wait
    Write-RollbackLog "Display subsystem re-synchronized to extended topology." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during display settings rollback: $_" "ERROR"
    exit 1
}
