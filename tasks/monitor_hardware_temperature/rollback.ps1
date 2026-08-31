<#
.SYNOPSIS
    Rollback & Cleanup Procedure for Hardware Temperature Monitor Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Cleans up any temporary state, locks, or restored backup configurations.
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

Write-RollbackLog "Initiating rollback sequence. Reason: $Reason" "WARN"

try {
    # 1. Clear any lock files or temporary cache
    $TempLocks = Get-ChildItem -Path $TaskDir -Filter "*.lock" -ErrorAction SilentlyContinue
    if ($TempLocks) {
        foreach ($lock in $TempLocks) {
            Write-RollbackLog "Removing lock file: $($lock.FullName)" "INFO"
            Remove-Item -Path $lock.FullName -Force
        }
    }

    # 2. Restore settings from backups if modified
    $BackupSettings = Join-Path $BackupDir "settings.json.bak"
    $CurrentSettings = Join-Path $TaskDir "config\settings.json"
    if (Test-Path $BackupSettings) {
        Write-RollbackLog "Restoring settings from backup..." "INFO"
        Copy-Item -Path $BackupSettings -Destination $CurrentSettings -Force
    }

    Write-RollbackLog "Rollback and cleanup finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
