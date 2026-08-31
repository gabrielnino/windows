<#
.SYNOPSIS
    Rollback Procedure for Windows File Recovery Installation Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Uninstalls Windows File Recovery via winget.
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

Write-RollbackLog "Initiating rollback for Windows File Recovery. Reason: $Reason" "WARN"

try {
    Start-Process -FilePath "winget.exe" -ArgumentList "uninstall --id 9N26S50LN705 --accept-source-agreements --silent" -Wait -NoNewWindow
    Write-RollbackLog "Windows File Recovery uninstalled." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
