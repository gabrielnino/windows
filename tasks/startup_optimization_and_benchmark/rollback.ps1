<#
.SYNOPSIS
    Rollback Procedure for Startup Optimization & Benchmark Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores startup configurations and cancels worker jobs.
#>
[CmdletBinding()]
param (
    [string]$Reason = "Manual or triggered rollback"
)

$ErrorActionPreference = 'Stop'
$TaskDir = $PSScriptRoot
$LogDir  = Join-Path $TaskDir "logs"
$BackupDir = Join-Path $TaskDir "backups"
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
    # 1. Stop any running background worker jobs
    Get-Job -Name "BenchWorker*" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    # 2. Restore startup registry entries from backup
    $backupFile = Join-Path $BackupDir "startup_apps_backup.json"
    if (Test-Path $backupFile) {
        $savedEntries = Get-Content -Path $backupFile -Raw | ConvertFrom-Json
        foreach ($entry in $savedEntries) {
            if ($entry.Location -like "HK*") {
                Set-ItemProperty -Path $entry.Location -Name $entry.Name -Value $entry.Command -Force -ErrorAction SilentlyContinue
                Write-RollbackLog "Restored startup entry: $($entry.Name) in $($entry.Location)" "INFO"
            }
        }
    }

    Write-RollbackLog "Rollback routine finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
