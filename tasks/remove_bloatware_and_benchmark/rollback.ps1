<#
.SYNOPSIS
    Rollback Procedure for Bloatware Removal & Benchmark Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores modified services and re-enables scheduled tasks.
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

Write-RollbackLog "Initiating rollback sequence for bloatware task. Reason: $Reason" "WARN"

try {
    # 1. Terminate any active benchmark workers
    Get-Job -Name "BenchWorker*" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    # 2. Restore Services
    $svcBackup = Join-Path $BackupDir "services_backup.json"
    if (Test-Path $svcBackup) {
        $savedServices = Get-Content -Path $svcBackup -Raw | ConvertFrom-Json
        foreach ($svc in $savedServices) {
            $name = $svc.Name
            $startMode = switch ($svc.StartMode) {
                "Auto" { "Automatic" }
                "Manual" { "Manual" }
                "Disabled" { "Disabled" }
                default { "Manual" }
            }
            Write-RollbackLog "Restoring service $name to $startMode..." "INFO"
            Set-Service -Name $name -StartupType $startMode -ErrorAction SilentlyContinue
            if ($svc.State -eq "Running") {
                Start-Service -Name $name -ErrorAction SilentlyContinue
            }
        }
    }

    # 3. Restore Scheduled Tasks
    $taskBackup = Join-Path $BackupDir "tasks_backup.json"
    if (Test-Path $taskBackup) {
        $savedTasks = Get-Content -Path $taskBackup -Raw | ConvertFrom-Json
        foreach ($t in $savedTasks) {
            Write-RollbackLog "Re-enabling scheduled task: $($t.TaskName)..." "INFO"
            Enable-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue
        }
    }

    Write-RollbackLog "Rollback and restoration finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
