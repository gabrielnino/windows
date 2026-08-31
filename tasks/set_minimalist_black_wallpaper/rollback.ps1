<#
.SYNOPSIS
    Rollback Procedure for Minimalist Black Wallpaper Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores the previous wallpaper state.
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

Write-RollbackLog "Initiating rollback sequence. Reason: $Reason" "WARN"

try {
    $backupFile = Join-Path $BackupDir "previous_wallpaper.txt"
    if (Test-Path $backupFile) {
        $prev = (Get-Content -Path $backupFile -Raw).Trim()
        if ($prev -and (Test-Path $prev)) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class RollbackWp {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@ -ErrorAction SilentlyContinue

            [RollbackWp]::SystemParametersInfo(20, 0, $prev, 3)
            Write-RollbackLog "Restored previous wallpaper: $prev" "INFO"
        }
    }
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
