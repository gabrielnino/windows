<#
.SYNOPSIS
    Rollback Procedure for SearchHost Prelaunch Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores SearchHost prelaunch and search settings.
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

Write-RollbackLog "Initiating rollback for SearchHost prelaunch task. Reason: $Reason" "WARN"

try {
    $keys = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search",
        "HKCU:\Software\Policies\Microsoft\Windows\Windows Search"
    )
    foreach ($k in $keys) {
        if (Test-Path $k) {
            Remove-ItemProperty -Path $k -Name "AllowPrelaunch" -Force -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $k -Name "EnableDynamicContentInWSB" -Force -ErrorAction SilentlyContinue
        }
    }

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -Name "IsSearchHighlightsEnabled" -Value 1 -Force -ErrorAction SilentlyContinue
    Write-RollbackLog "SearchHost prelaunch rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
