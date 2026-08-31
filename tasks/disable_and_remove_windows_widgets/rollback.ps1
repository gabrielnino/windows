<#
.SYNOPSIS
    Rollback Procedure for Windows Widgets Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores Widgets registry policies and taskbar visibility.
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

Write-RollbackLog "Initiating rollback for Widgets task. Reason: $Reason" "WARN"

try {
    # 1. Restore Taskbar Button
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 1 -Force -ErrorAction SilentlyContinue

    # 2. Remove Dsh Disable Policy
    $dshKey = "HKCU:\Software\Policies\Microsoft\Dsh"
    if (Test-Path $dshKey) {
        Remove-ItemProperty -Path $dshKey -Name "AllowNewsAndInterests" -Force -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "Widgets rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during Widgets rollback: $_" "ERROR"
    exit 1
}
