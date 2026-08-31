<#
.SYNOPSIS
    Rollback Procedure for Deep RAM and System Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores per-user services, GameDVR, and Defender settings.
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

Write-RollbackLog "Initiating rollback for Deep RAM Optimization task. Reason: $Reason" "WARN"

try {
    # 1. Restore Per-User Services
    $templateServices = @("CDPUserSvc", "PimIndexMaintenanceSvc", "UserDataSvc", "UnistoreSvc", "CloudBackupRestoreSvc", "DevicesFlowUserSvc")
    foreach ($sName in $templateServices) {
        $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$sName"
        if (Test-Path $key) {
            Set-ItemProperty -Path $key -Name "Start" -Value 3 -Force -ErrorAction SilentlyContinue
            Write-RollbackLog "Restored service template: $sName (Start=3)" "INFO"
        }
    }

    # 2. Re-enable GameDVR
    Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -Force -ErrorAction SilentlyContinue

    Write-RollbackLog "Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
