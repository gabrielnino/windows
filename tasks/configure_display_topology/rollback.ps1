<#
.SYNOPSIS
    Rollback Procedure for Display Topology Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Reverts display topology back to internal screen or duplicate.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback",
    [ValidateSet("internal", "clone", "extend")][string]$TargetMode = "internal"
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

Write-RollbackLog "Initiating rollback sequence for display topology. Target: $TargetMode. Reason: $Reason" "WARN"

try {
    Start-Process -FilePath "DisplaySwitch.exe" -ArgumentList "/$TargetMode" -NoNewWindow -Wait
    Write-RollbackLog "Display topology reverted to /$TargetMode successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during display rollback: $_" "ERROR"
    exit 1
}
