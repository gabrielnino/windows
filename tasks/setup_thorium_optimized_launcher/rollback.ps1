<#
.SYNOPSIS
    Rollback Procedure for Thorium Optimize Mode Launcher Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Removes the custom Thorium (Optimize Mode) shortcuts and launcher files.
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

Write-RollbackLog "Initiating rollback for Thorium Optimize Mode launcher. Reason: $Reason" "WARN"

try {
    $scName = "Thorium (Optimize Mode).lnk"
    $paths = @(
        "f:\windows\launchers\$scName",
        "f:\windows\launchers\ThoriumOptimizeMode.cmd",
        "$env:USERPROFILE\Desktop\$scName",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\$scName",
        "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\$scName"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) {
            Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
            Write-RollbackLog "Removed: $p" "INFO"
        }
    }

    Write-RollbackLog "Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
