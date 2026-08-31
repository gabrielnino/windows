<#
.SYNOPSIS
    Rollback Procedure for Microsoft Copilot Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores Copilot registry policies and services.
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

Write-RollbackLog "Initiating rollback sequence for Copilot task. Reason: $Reason" "WARN"

try {
    # 1. Remove Copilot Disable Policies
    $keys = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot",
        "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            Remove-ItemProperty -Path $k -Name "TurnOffWindowsCopilot" -Force -ErrorAction SilentlyContinue
            Write-RollbackLog "Removed TurnOffWindowsCopilot from $k" "INFO"
        }
    }

    # 2. Re-enable Taskbar Button
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 1 -Force -ErrorAction SilentlyContinue

    # 3. Restore Copilot Service
    Set-Service -Name "MicrosoftCopilotElevationService" -StartupType Manual -ErrorAction SilentlyContinue

    Write-RollbackLog "Copilot rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during Copilot rollback: $_" "ERROR"
    exit 1
}
