<#
.SYNOPSIS
    Rollback Procedure for RAM Optimization Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores Widgets policy settings.
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

Write-RollbackLog "Initiating rollback sequence for RAM optimization task. Reason: $Reason" "WARN"

try {
    $dshKey = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (Test-Path $dshKey) {
        Remove-ItemProperty -Path $dshKey -Name "AllowNewsAndInterests" -Force -ErrorAction SilentlyContinue
    }
    Write-RollbackLog "Widgets policy reset to default." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
