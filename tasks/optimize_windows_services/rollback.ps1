<#
.SYNOPSIS
    Rollback Procedure for Windows Services Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores original service start types and restarts services from backup.
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

Write-RollbackLog "Initiating rollback for Windows Services task. Reason: $Reason" "WARN"

try {
    $backupFile = Join-Path $BackupDir "services_backup.json"
    if (Test-Path $backupFile) {
        $backupList = Get-Content -Path $backupFile -Raw | ConvertFrom-Json
        foreach ($svc in $backupList) {
            $sName = $svc.Name
            $sMode = if ($svc.StartMode -eq "Auto") { "Automatic" } else { $svc.StartMode }
            
            Write-RollbackLog "Restoring service $sName to $sMode..." "INFO"
            Set-Service -Name $sName -StartupType $sMode -ErrorAction SilentlyContinue
            if ($svc.State -eq "Running") {
                Start-Service -Name $sName -ErrorAction SilentlyContinue
            }
        }
    } else {
        # Fallback defaults
        Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction SilentlyContinue
        Set-Service -Name "Spooler" -StartupType Automatic -ErrorAction SilentlyContinue
        Set-Service -Name "DoSvc" -StartupType Automatic -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "Windows Services rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
