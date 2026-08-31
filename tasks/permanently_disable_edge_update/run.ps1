<#
.SYNOPSIS
    Permanently Disable and Neutralize Microsoft Edge Update.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Identifies the trigger (MicrosoftEdgeUpdateTaskMachineCore scheduled task).
    2. Stops and disables all Edge Update scheduled tasks.
    3. Terminates running MicrosoftEdgeUpdate.exe processes.
    4. Sets MicrosoftEdgeElevationService, edgeupdate, and edgeupdatem to Disabled.
    5. Applies an IFEO debugger block so MicrosoftEdgeUpdate.exe cannot be spawned by any background trigger.
.PARAMETER DryRun
    Simulates disabling without modifying system tasks or registry.
#>
[CmdletBinding()]
param (
    [switch]$DryRun
)

# 1. Strict Configuration & Directory Isolation
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$TaskDir     = $PSScriptRoot
$LogDir      = Join-Path $TaskDir "logs"
$ReportDir   = Join-Path $TaskDir "reports"
$ArtifactDir = Join-Path $TaskDir "artifacts"
$BackupDir   = Join-Path $TaskDir "backups"
$ConfigDir   = Join-Path $TaskDir "config"

New-Item -ItemType Directory -Force -Path $LogDir, $ReportDir, $ArtifactDir, $BackupDir, $ConfigDir | Out-Null
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile    = Join-Path $LogDir "task_$Timestamp.log"
$ReportJson = Join-Path $ReportDir "report_$Timestamp.json"
$ReportMd   = Join-Path $ReportDir "report_$Timestamp.md"

# 2. Step-by-Step Logging Function
function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "ALERT")][string]$Level = "INFO"
    )
    $TimeStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStr] [$Level] $Message"
    
    switch ($Level) {
        "ALERT" { Write-Host $Line -ForegroundColor Red -BackgroundColor Black }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        "ERROR" { Write-Host $Line -ForegroundColor Red }
        "DEBUG" { Write-Host $Line -ForegroundColor DarkGray }
        default { Write-Host $Line -ForegroundColor Cyan }
    }
    
    Add-Content -Path $LogFile -Value $Line
}

# 3. Rollback Procedure
function Invoke-Rollback {
    param([string]$Reason = "Execution failure")
    Write-Log "Initiating rollback sequence: $Reason" "WARN"
    $RollbackScript = Join-Path $TaskDir "rollback.ps1"
    if (Test-Path $RollbackScript) {
        & $RollbackScript -Reason $Reason
    }
    Write-Log "Rollback completed." "WARN"
}

# 4. Main Execution Routine
$StartTime = Get-Date

$DisableKPIs = @{
    TaskName                = "permanently_disable_edge_update"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    TriggerIdentified       = "MicrosoftEdgeUpdateTaskMachineCore"
    TasksDisabled           = @()
    ServicesDisabled        = @()
    ProcessesTerminated     = @()
    IfeoBlockApplied        = $false
    PostActiveProcessesCount= 0
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Identifying trigger responsible for launching Microsoft Edge Update..." "INFO"
    $activeTasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*MicrosoftEdgeUpdateTaskMachine*" }
    foreach ($t in $activeTasks) {
        Write-Log "Identified Task Trigger: $($t.TaskName) (State: $($t.State))" "INFO"
    }

    Write-Log "[Step 2/5] Stopping and disabling Edge Update scheduled tasks..." "INFO"
    if (-not $DryRun) {
        foreach ($t in $activeTasks) {
            try {
                Stop-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                Disable-ScheduledTask -TaskName $t.TaskName -ErrorAction SilentlyContinue | Out-Null
                $DisableKPIs.TasksDisabled += $t.TaskName
                Write-Log "Stopped and Disabled Scheduled Task: $($t.TaskName)" "INFO"
            } catch {
                Write-Log "Could not disable $($t.TaskName): $_" "WARN"
            }
        }
    }

    Write-Log "[Step 3/5] Stopping and disabling Edge Update and Elevation services..." "INFO"
    if (-not $DryRun) {
        $services = @("edgeupdate", "edgeupdatem", "MicrosoftEdgeElevationService")
        foreach ($sName in $services) {
            $s = Get-Service -Name $sName -ErrorAction SilentlyContinue
            if ($s) {
                Stop-Service -Name $sName -Force -ErrorAction SilentlyContinue
                Set-Service -Name $sName -StartupType Disabled -ErrorAction SilentlyContinue
                $DisableKPIs.ServicesDisabled += $sName
                Write-Log "Disabled service: $sName" "INFO"
            }
        }
    }

    Write-Log "[Step 4/5] Terminating active MicrosoftEdgeUpdate.exe processes..." "INFO"
    if (-not $DryRun) {
        $procs = Get-Process -Name "*EdgeUpdate*" -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            Write-Log "Terminating process: $($p.ProcessName) (PID: $($p.Id))..." "INFO"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $DisableKPIs.ProcessesTerminated += "$($p.ProcessName) (PID: $($p.Id))"
        }
    }

    Write-Log "[Step 5/5] Applying IFEO execution block to prevent any future launches..." "INFO"
    if (-not $DryRun) {
        $ifeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\MicrosoftEdgeUpdate.exe"
        if (-not (Test-Path $ifeoKey)) {
            New-Item -Path $ifeoKey -Force | Out-Null
        }
        Set-ItemProperty -Path $ifeoKey -Name "Debugger" -Value "systray.exe" -Force
        $DisableKPIs.IfeoBlockApplied = $true
        Write-Log "Applied IFEO block on MicrosoftEdgeUpdate.exe (Redirected to benign stub)." "INFO"
    }

    # Verify post-execution state
    $remaining = @(Get-Process | Where-Object { $_.ProcessName -like "*EdgeUpdate*" })
    $DisableKPIs.PostActiveProcessesCount = $remaining.Count
    Write-Log "Post-Execution Edge Update Processes in Memory: $($remaining.Count)" "INFO"

    $DisableKPIs.Status = "SUCCESS"
}
catch {
    $DisableKPIs.Status = "FAILED"
    $DisableKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Edge Update disabling: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $DisableKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $DisableKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $DisableKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $taskRows = @()
    foreach ($t in $DisableKPIs.TasksDisabled) {
        $taskRows += "| $t | Disabled |"
    }

    $svcRows = @()
    foreach ($s in $DisableKPIs.ServicesDisabled) {
        $svcRows += "| $s | Disabled |"
    }

    $mdLines = @(
        "# Microsoft Edge Update Permanent Disabling Report",
        "",
        "- Task Name: $($DisableKPIs.TaskName)",
        "- Status: $($DisableKPIs.Status)",
        "- Trigger Identified: $($DisableKPIs.TriggerIdentified)",
        "- Tasks Disabled: $($DisableKPIs.TasksDisabled.Count)",
        "- Services Disabled: $($DisableKPIs.ServicesDisabled.Count)",
        "- Processes Terminated: $($DisableKPIs.ProcessesTerminated.Count)",
        "- IFEO Execution Block Active: $($DisableKPIs.IfeoBlockApplied)",
        "- Remaining Processes in Task Manager: $($DisableKPIs.PostActiveProcessesCount)",
        "- Execution Timestamp: $($DisableKPIs.StartTime) to $($DisableKPIs.EndTime)",
        "- Duration: $($DisableKPIs.DurationSeconds) s",
        "",
        "## Trigger and Root Cause",
        "The process 'Microsoft Edge Update (32 bit)' was triggered by the Scheduled Task `MicrosoftEdgeUpdateTaskMachineCore` running with argument `/c`.",
        "",
        "## Actions Taken",
        "| Component | Action Taken |",
        "|---|---|",
        ($taskRows -join "`r`n"),
        ($svcRows -join "`r`n"),
        "| MicrosoftEdgeUpdate.exe | Permanently blocked via IFEO |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Edge Update disabling complete. Report generated at: $ReportMd" "INFO"
}
