<#
.SYNOPSIS
    Rollback & Restoration Procedure for System Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores original service start types and startup configurations from backups.
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

Write-RollbackLog "Initiating rollback sequence for optimization task. Reason: $Reason" "WARN"

try {
    # 1. Kill any lingering benchmark worker jobs
    Get-Job -Name "BenchWorker*" -ErrorAction SilentlyContinue | Stop-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue

    # 2. Restore services from backup
    $backupFile = Join-Path $BackupDir "services_original_state.json"
    if (Test-Path $backupFile) {
        $savedServices = Get-Content -Path $backupFile -Raw | ConvertFrom-Json
        foreach ($svc in $savedServices) {
            $name = $svc.Name
            $startMode = $svc.StartMode
            Write-RollbackLog "Restoring service '$name' to StartMode: $startMode..." "INFO"
            try {
                $serviceObj = Get-Service -Name $name -ErrorAction SilentlyContinue
                if ($serviceObj) {
                    $wmiMode = switch ($startMode) {
                        "Auto" { "Automatic" }
                        "Manual" { "Manual" }
                        "Disabled" { "Disabled" }
                        default { "Manual" }
                    }
                    Set-Service -Name $name -StartupType $wmiMode -ErrorAction SilentlyContinue
                    if ($svc.State -eq "Running") {
                        Start-Service -Name $name -ErrorAction SilentlyContinue
                    }
                }
            } catch {
                Write-RollbackLog "Could not restore service $name: $_" "WARN"
            }
        }
    }

    Write-RollbackLog "Rollback and restoration finished successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback execution: $_" "ERROR"
    exit 1
}
