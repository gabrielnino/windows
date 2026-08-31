<#
.SYNOPSIS
    Rollback & Uninstall Procedure for PowerShell 7 Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Uninstalls PowerShell 7 using winget.
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

Write-RollbackLog "Initiating rollback sequence for PowerShell 7. Reason: $Reason" "WARN"

try {
    Write-RollbackLog "Running winget uninstall Microsoft.PowerShell..." "INFO"
    Start-Process -FilePath "winget.exe" -ArgumentList "uninstall --id Microsoft.PowerShell -e --source winget --silent" -NoNewWindow -Wait
    Write-RollbackLog "PowerShell 7 uninstallation completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
