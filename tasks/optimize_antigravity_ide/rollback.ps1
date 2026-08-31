<#
.SYNOPSIS
    Rollback Procedure for Antigravity IDE Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores default scheduled task launch configuration.
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

Write-RollbackLog "Initiating rollback for Antigravity IDE optimization. Reason: $Reason" "WARN"

try {
    $antigravityExe = "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
    $action = New-ScheduledTaskAction -Execute $antigravityExe
    Set-ScheduledTask -TaskName "Launch_Antigravity_Elevated" -Action $action -ErrorAction SilentlyContinue
    Write-RollbackLog "Restored default action for Launch_Antigravity_Elevated." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
