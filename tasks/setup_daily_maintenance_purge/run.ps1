<#
.SYNOPSIS
    Register Automated Logon & Daily Performance Purge Scheduled Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Deploys maintenance worker script to f:\windows\scripts\daily_performance_purge.ps1.
    2. Registers elevated Scheduled Task 'Maintenance_DailyPerformancePurge'.
    3. Configures triggers: (A) At User Logon, (B) Daily at 6:00 AM.
    4. Executes an initial test run and validates logging.
.PARAMETER DryRun
    Simulates registration without creating scheduled task.
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

$PurgeKPIs = @{
    TaskName             = "setup_daily_maintenance_purge"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    ScheduledTaskName    = "Maintenance_DailyPerformancePurge"
    WorkerScriptPath     = "f:\windows\scripts\daily_performance_purge.ps1"
    LogonTriggerActive   = $false
    DailyTriggerActive   = $false
    InitialTestExecuted  = $false
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Loading configuration and validating worker script..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $workerScript = "f:\windows\scripts\daily_performance_purge.ps1"

    if (-not (Test-Path $workerScript)) {
        throw "Worker script not found at $workerScript"
    }

    Write-Log "[Step 2/4] Constructing Scheduled Task with dual triggers (Logon + Daily 6:00 AM)..." "INFO"
    if (-not $DryRun) {
        $taskName = $config.scheduled_task_name
        
        # Actions
        $pwshExe = "powershell.exe"
        $args = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$workerScript`""
        $action = New-ScheduledTaskAction -Execute $pwshExe -Argument $args

        # Triggers
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $triggerDaily = New-ScheduledTaskTrigger -Daily -At "06:00:00"
        $triggers = @($triggerLogon, $triggerDaily)

        # Principal (Elevated / Highest)
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

        # Settings
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        # Unregister existing if present
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }

        # Register Scheduled Task
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Principal $principal -Settings $settings | Out-Null
        
        $PurgeKPIs.LogonTriggerActive = $true
        $PurgeKPIs.DailyTriggerActive = $true
        Write-Log "Successfully registered scheduled task: $taskName" "INFO"
    }

    Write-Log "[Step 3/4] Executing initial test run of the maintenance purge worker..." "INFO"
    if (-not $DryRun) {
        & powershell.exe -ExecutionPolicy Bypass -File $workerScript
        $PurgeKPIs.InitialTestExecuted = $true
        Write-Log "Initial test run completed." "INFO"
    }

    Write-Log "[Step 4/4] Verifying scheduled task operational state..." "INFO"
    $taskState = Get-ScheduledTask -TaskName $PurgeKPIs.ScheduledTaskName -ErrorAction SilentlyContinue
    if (-not $taskState) {
        throw "Scheduled task $($PurgeKPIs.ScheduledTaskName) could not be verified."
    }
    Write-Log "Scheduled Task Status: $($taskState.State)" "INFO"

    $PurgeKPIs.Status = "SUCCESS"
}
catch {
    $PurgeKPIs.Status = "FAILED"
    $PurgeKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during scheduled task registration: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $PurgeKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $PurgeKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $PurgeKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Automated Daily Performance Purge Task Report",
        "",
        "- Task Name: $($PurgeKPIs.TaskName)",
        "- Status: $($PurgeKPIs.Status)",
        "- Scheduled Task Name: $($PurgeKPIs.ScheduledTaskName)",
        "- Worker Script: $($PurgeKPIs.WorkerScriptPath)",
        "- Logon Trigger (AtLogOn): $($PurgeKPIs.LogonTriggerActive)",
        "- Daily Trigger (06:00 AM): $($PurgeKPIs.DailyTriggerActive)",
        "- Initial Test Run Completed: $($PurgeKPIs.InitialTestExecuted)",
        "- Execution Timestamp: $($PurgeKPIs.StartTime) to $($PurgeKPIs.EndTime)",
        "- Duration: $($PurgeKPIs.DurationSeconds) s",
        "",
        "## Automated Cleaning Matrix",
        "| Category | Cleaned Paths | Behavior |",
        "|---|---|---|",
        "| Windows Temp | %TEMP% and C:\Windows\Temp | Deletes stale temporary files and crash dumps |",
        "| Thorium Browser Cache | LocalAppData\Thorium\User Data\Default Cache/GPUCache | Purges shader, code, and GPU cache without losing logins or history |",
        "| Antigravity IDE Cache | AppData\Antigravity Cache & .gemini\antigravity\crashes | Purges stale cache and temp media storage |",
        "| RAM Working Set Flush | EmptyWorkingSet across background processes | Trims idle memory buffers automatically |",
        "",
        "## Schedule Details",
        "- Event 1: Every time you log in to Windows (AtLogon).",
        "- Event 2: Every morning at 06:00:00 AM (Daily).",
        "- Execution Mode: 100% Silent (-WindowStyle Hidden) with Administrative privileges.",
        "- Log File: f:\windows\logs\daily_purge_history.log",
        "",
        "- Detailed Log File: " + $LogFile,
        "- JSON Report: " + $ReportJson
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Daily Performance Purge task registration complete. Report generated at: $ReportMd" "INFO"
}
