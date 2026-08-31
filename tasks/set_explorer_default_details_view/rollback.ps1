<#
.SYNOPSIS
    Rollback Procedure for File Explorer Default View Mode Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
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

Write-RollbackLog "Initiating rollback for Explorer Details View task. Reason: $Reason" "WARN"

try {
    $allFoldersKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders"
    if (Test-Path $allFoldersKey) {
        Remove-Item -Path $allFoldersKey -Recurse -Force -ErrorAction SilentlyContinue
        Write-RollbackLog "Removed AllFolders override from Shell Bags." "INFO"
    }

    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process "explorer.exe"

    Write-RollbackLog "Explorer restarted. Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
