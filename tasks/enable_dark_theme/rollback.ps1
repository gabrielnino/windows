<#
.SYNOPSIS
    Rollback Procedure for Dark Theme Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Restores the previous theme (Light mode) from backup.
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

Write-RollbackLog "Initiating rollback sequence for system theme. Reason: $Reason" "WARN"

try {
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $backupFile = Join-Path $BackupDir "previous_theme.json"

    if (Test-Path $backupFile) {
        $prev = Get-Content -Path $backupFile -Raw | ConvertFrom-Json
        Set-ItemProperty -Path $regPath -Name SystemUsesLightTheme -Value $prev.SystemUsesLightTheme
        Set-ItemProperty -Path $regPath -Name AppsUseLightTheme -Value $prev.AppsUseLightTheme
        Write-RollbackLog "Restored SystemUsesLightTheme=$($prev.SystemUsesLightTheme) and AppsUseLightTheme=$($prev.AppsUseLightTheme)" "INFO"
    } else {
        Set-ItemProperty -Path $regPath -Name SystemUsesLightTheme -Value 1
        Set-ItemProperty -Path $regPath -Name AppsUseLightTheme -Value 1
        Write-RollbackLog "Restored default Light Mode." "INFO"
    }

    # Broadcast change
    rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True
    Write-RollbackLog "Theme rollback completed successfully." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during theme rollback: $_" "ERROR"
    exit 1
}
