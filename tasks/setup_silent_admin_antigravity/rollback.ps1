<#
.SYNOPSIS
    Rollback Procedure for Silent Admin Antigravity Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Removes the elevated scheduled task, shortcuts, and launcher scripts.
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

Write-RollbackLog "Initiating rollback for Silent Admin Antigravity task. Reason: $Reason" "WARN"

try {
    # 1. Unregister Scheduled Task
    Unregister-ScheduledTask -TaskName "Launch_Antigravity_Elevated" -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Write-RollbackLog "Unregistered Launch_Antigravity_Elevated scheduled task." "INFO"

    # 2. Remove Shortcuts
    $desktopShortcut = "$env:USERPROFILE\Desktop\Antigravity (Admin Silencioso).lnk"
    if (Test-Path $desktopShortcut) {
        Remove-Item -Path $desktopShortcut -Force -ErrorAction SilentlyContinue
    }

    # 3. Remove Launchers
    $launcherDir = "f:\windows\launchers"
    if (Test-Path $launcherDir) {
        Remove-Item -Path "$launcherDir\launch_antigravity.*" -Force -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "Silent Admin Antigravity rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
