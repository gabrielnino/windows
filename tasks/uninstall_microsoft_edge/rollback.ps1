<#
.SYNOPSIS
    Rollback Procedure for Microsoft Edge Uninstallation Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Reinstalls Microsoft Edge via winget if rollback is requested.
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

Write-RollbackLog "Initiating rollback sequence for Microsoft Edge. Reason: $Reason" "WARN"

try {
    Write-RollbackLog "Reinstalling Microsoft Edge via winget..." "INFO"
    Start-Process -FilePath "winget.exe" -ArgumentList "install --id Microsoft.Edge -e --source winget --accept-source-agreements --accept-package-agreements --silent" -Wait -NoNewWindow
    Write-RollbackLog "Microsoft Edge rollback/reinstallation completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during Edge rollback: $_" "ERROR"
    exit 1
}
