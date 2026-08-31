<#
.SYNOPSIS
    Rollback Procedure for OneDrive Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Removes OneDrive disabling policies and restores default settings.
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

Write-RollbackLog "Initiating rollback sequence for OneDrive task. Reason: $Reason" "WARN"

try {
    # 1. Remove DisableFileSyncNGSC policies
    $keys = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive",
        "HKCU:\Software\Policies\Microsoft\Windows\OneDrive"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            Remove-ItemProperty -Path $k -Name "DisableFileSyncNGSC" -Force -ErrorAction SilentlyContinue
            Write-RollbackLog "Removed DisableFileSyncNGSC from $k" "INFO"
        }
    }

    # 2. Restore Explorer Sidebar Pinning
    $clsidKey = "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
    if (Test-Path $clsidKey) {
        Set-ItemProperty -Path $clsidKey -Name "System.IsPinnedToNameSpaceTree" -Value 1 -Force -ErrorAction SilentlyContinue
    }

    Write-RollbackLog "OneDrive rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during OneDrive rollback: $_" "ERROR"
    exit 1
}
