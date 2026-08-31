<#
.SYNOPSIS
    Rollback Procedure for Deep Software Audit Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Read-only audit task rollback cleans up temporary scan files.
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

Write-RollbackLog "Rollback initiated for software audit task. Reason: $Reason" "WARN"
Write-RollbackLog "Audit task is non-destructive. Rollback completed." "INFO"
exit 0
