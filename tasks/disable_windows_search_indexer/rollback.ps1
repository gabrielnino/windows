<#
.SYNOPSIS
    Rollback Procedure for Windows Search Indexer Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores WSearch service to Automatic and starts it.
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

Write-RollbackLog "Initiating rollback for Windows Search task. Reason: $Reason" "WARN"

try {
    Write-RollbackLog "Restoring WSearch service to Automatic..." "INFO"
    Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
    Write-RollbackLog "WSearch service restored." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during WSearch rollback: $_" "ERROR"
    exit 1
}
