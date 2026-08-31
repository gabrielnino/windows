<#
.SYNOPSIS
    Rollback & Cleanup Procedure for System Audit Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Cleans up any partial export files, locks, or incomplete audit artifacts.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback"
)

$ErrorActionPreference = 'Stop'
$TaskDir = $PSScriptRoot
$LogDir  = Join-Path $TaskDir "logs"
$ArtifactDir = Join-Path $TaskDir "artifacts"
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

Write-RollbackLog "Initiating rollback sequence. Reason: $Reason" "WARN"

try {
    # 1. Clean up partial or lock files
    $tempFiles = Get-ChildItem -Path $ArtifactDir -Filter "*.tmp" -ErrorAction SilentlyContinue
    if ($tempFiles) {
        foreach ($tmp in $tempFiles) {
            Write-RollbackLog "Removing temporary audit artifact: $($tmp.FullName)" "INFO"
            Remove-Item -Path $tmp.FullName -Force
        }
    }

    Write-RollbackLog "Rollback and cleanup finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
