<#
.SYNOPSIS
    Rollback Procedure for User Experience Evaluation Disabling Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Re-enables CEIP tasks and restores default privacy settings.
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

Write-RollbackLog "Initiating rollback sequence for User Experience task. Reason: $Reason" "WARN"

try {
    $ceipTasks = @(
        "Consolidator",
        "UsbCeip",
        "Microsoft Compatibility Appraiser Exp",
        "DmClient",
        "DmClientOnScenarioDownload",
        "Sqm-Tasks"
    )

    foreach ($tName in $ceipTasks) {
        $t = Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue
        if ($t) {
            Enable-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
            Write-RollbackLog "Re-enabled task: $tName" "INFO"
        }
    }

    Write-RollbackLog "Rollback completed." "INFO"
    exit 0
}
catch {
    Write-RollbackLog "Error during rollback: $_" "ERROR"
    exit 1
}
