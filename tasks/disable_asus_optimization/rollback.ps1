<#
.SYNOPSIS
    Rollback Procedure for ASUS Optimization Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores ASUS Optimization service and scheduled task.
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

Write-RollbackLog "Initiating rollback for ASUS Optimization task. Reason: $Reason" "WARN"

try {
    # 1. Restore ASUSOptimization Service
    $s = Get-Service -Name "ASUSOptimization" -ErrorAction SilentlyContinue
    if ($s) {
        Write-RollbackLog "Restoring ASUSOptimization service to Automatic..." "INFO"
        Set-Service -Name "ASUSOptimization" -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service -Name "ASUSOptimization" -ErrorAction SilentlyContinue
    }

    # 2. Re-enable Scheduled Task
    $t = Get-ScheduledTask -TaskName "ASUS Optimization 36D18D69AFC3" -ErrorAction SilentlyContinue
    if ($t) {
        Write-RollbackLog "Re-enabling ASUS Optimization scheduled task..." "INFO"
        Enable-ScheduledTask -TaskName "ASUS Optimization 36D18D69AFC3" -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "Rollback finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
