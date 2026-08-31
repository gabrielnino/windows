<#
.SYNOPSIS
    Rollback Procedure for Outlook & Microsoft Store Uninstallation Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores Store service and triggers Store reinstall.
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

Write-RollbackLog "Initiating rollback sequence for Outlook and Store task. Reason: $Reason" "WARN"

try {
    # 1. Restore InstallService
    Set-Service -Name "InstallService" -StartupType Manual -ErrorAction SilentlyContinue
    
    # 2. Re-enable ScanForUpdatesAsUser task
    Enable-ScheduledTask -TaskName "ScanForUpdatesAsUser" -ErrorAction SilentlyContinue | Out-Null

    # 3. Restore Microsoft Store if available
    Write-RollbackLog "Reinstalling Microsoft Store via wsreset..." "INFO"
    Start-Process -FilePath "wsreset.exe" -ArgumentList "-i" -NoNewWindow -ErrorAction SilentlyContinue

    Write-RollbackLog "Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
