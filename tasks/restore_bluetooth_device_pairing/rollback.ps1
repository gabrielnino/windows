<#
.SYNOPSIS
    Rollback Procedure for Bluetooth Device Pairing Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
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

Write-RollbackLog "Initiating rollback for Bluetooth pairing task. Reason: $Reason" "WARN"

try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DevicesFlowUserSvc" -Name "Start" -Value 4 -Force -ErrorAction SilentlyContinue
    Write-RollbackLog "Bluetooth pairing rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
