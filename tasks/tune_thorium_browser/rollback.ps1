<#
.SYNOPSIS
    Rollback Procedure for Thorium Browser Tuning Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores original Preferences and Local State configuration files.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback"
)

$ErrorActionPreference = 'Stop'
$TaskDir = $PSScriptRoot
$LogDir  = Join-Path $TaskDir "logs"
$BackupDir = Join-Path $TaskDir "backups"
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

Write-RollbackLog "Initiating rollback for Thorium Browser tuning task. Reason: $Reason" "WARN"

try {
    $thoriumDir = "$env:LOCALAPPDATA\Thorium\User Data"
    $prefBackup = Join-Path $BackupDir "Preferences_backup.json"
    $localStateBackup = Join-Path $BackupDir "Local_State_backup.json"

    if (Test-Path $prefBackup) {
        Copy-Item -Path $prefBackup -Destination "$thoriumDir\Default\Preferences" -Force
        Write-RollbackLog "Restored Preferences from backup." "INFO"
    }

    if (Test-Path $localStateBackup) {
        Copy-Item -Path $localStateBackup -Destination "$thoriumDir\Local State" -Force
        Write-RollbackLog "Restored Local State from backup." "INFO"
    }

    Write-RollbackLog "Thorium rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
