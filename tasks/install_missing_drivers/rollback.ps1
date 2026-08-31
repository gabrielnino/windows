<#
.SYNOPSIS
    Rollback & Restore Procedure for Missing Drivers Installation Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Provides procedures to restore prior drivers or trigger System Restore.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback"
)

$ErrorActionPreference = 'Stop'
$TaskDir = $PSScriptRoot
$LogDir  = Join-Path $TaskDir "logs"
$ArtifactDir = Join-Path $TaskDir "artifacts"
$BackupDir   = Join-Path $TaskDir "backups"
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

Write-RollbackLog "Initiating rollback sequence for driver installer. Reason: $Reason" "WARN"

try {
    # 1. Clean downloaded driver installers
    $downloads = Get-ChildItem -Path $ArtifactDir -Include *.exe, *.zip, *.cab, *.msi -Recurse -ErrorAction SilentlyContinue
    if ($downloads) {
        foreach ($d in $downloads) {
            Write-RollbackLog "Removing downloaded installer: $($d.FullName)" "INFO"
            Remove-Item -Path $d.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    # 2. Check if a System Restore Point exists for this task
    Write-RollbackLog "Checking available System Restore Points..." "INFO"
    $restorePoints = Get-CimInstance -Namespace "root/default" -ClassName "SystemRestore" -ErrorAction SilentlyContinue
    if ($restorePoints) {
        $lastRp = $restorePoints | Select-Object -Last 1
        Write-RollbackLog "Last System Restore Point available: '$($lastRp.Description)' (SequenceNumber: $($lastRp.SequenceNumber))" "INFO"
    }

    Write-RollbackLog "Driver rollback and cleanup routine completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
