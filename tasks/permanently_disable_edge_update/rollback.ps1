<#
.SYNOPSIS
    Rollback Procedure for Microsoft Edge Update Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Removes IFEO execution blocks and re-enables Edge update tasks.
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

Write-RollbackLog "Initiating rollback sequence for Edge Update task. Reason: $Reason" "WARN"

try {
    # 1. Remove IFEO blocks
    $ifeoBase = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options"
    $binaries = @("MicrosoftEdgeUpdate.exe", "msedge.exe")
    foreach ($bin in $binaries) {
        $key = Join-Path $ifeoBase $bin
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-RollbackLog "Removed IFEO block for $bin" "INFO"
        }
    }

    # 2. Re-enable tasks
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*MicrosoftEdgeUpdateTaskMachine*" } | ForEach-Object {
        Enable-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue | Out-Null
        Write-RollbackLog "Re-enabled task: $($_.TaskName)" "INFO"
    }

    Write-RollbackLog "Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
