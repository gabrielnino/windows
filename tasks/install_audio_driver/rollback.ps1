<#
.SYNOPSIS
    Rollback & Cleanup Procedure for Audio Driver Installation Task.
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

Write-RollbackLog "Initiating rollback sequence for audio driver task. Reason: $Reason" "WARN"

try {
    # Remove downloaded installers from artifacts
    $files = Get-ChildItem -Path $ArtifactDir -Include *.exe, *.zip -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        Write-RollbackLog "Removing artifact: $($f.FullName)" "INFO"
        Remove-Item -Path $f.FullName -Force -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "Rollback and cleanup finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
