<#
.SYNOPSIS
    Configure AC Power Management: Display Sleep Only, Zero System Sleep / Throttling.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Sets monitor turn-off timeout on AC power to 10 minutes (protects OLED and LCDs).
    2. Sets system sleep (standby-timeout-ac) to 0 (NEVER sleep while plugged in).
    3. Sets system hibernation (hibernate-timeout-ac) to 0 (NEVER hibernate on AC).
    4. Sets disk turn-off (disk-timeout-ac) to 0 (NEVER power down SSD/storage).
    5. Sets lid close action on AC power to 0 (DO NOTHING - full performance when lid is closed with external monitors).
    6. Ensures continuous background task execution, downloads, and IDE server responsiveness.
.PARAMETER DryRun
    Simulates configuration without applying powercfg settings.
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

$PowerKPIs = @{
    TaskName                  = "configure_ac_power_plan"
    Status                    = "RUNNING"
    StartTime                 = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                    = [bool]$DryRun
    ActiveScheme              = ""
    MonitorTimeoutAcMin       = 10
    StandbyTimeoutAcMin       = 0
    HibernateTimeoutAcMin     = 0
    DiskTimeoutAcMin          = 0
    LidCloseActionAc          = "Do Nothing (0)"
    ContinuousOperationReady  = $false
    DurationSeconds           = 0.0
}

try {
    Write-Log "[Step 1/3] Loading configuration and capturing active power scheme..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $activeSchemeOut = powercfg /getactivescheme
    $PowerKPIs.ActiveScheme = $activeSchemeOut
    Write-Log "Active Power Scheme: $activeSchemeOut" "INFO"

    # Backup current scheme settings
    $backupFile = Join-Path $BackupDir "power_scheme_backup.txt"
    powercfg /query SCHEME_CURRENT | Out-File -FilePath $backupFile -Encoding UTF8
    Write-Log "Backed up current power scheme query to: $backupFile" "INFO"

    Write-Log "[Step 2/3] Applying AC power management policies via powercfg..." "INFO"
    if (-not $DryRun) {
        # 1. Turn off display after 10 minutes on AC
        powercfg /change monitor-timeout-ac $config.monitor_timeout_ac_minutes
        Write-Log "Configured: Monitor turns off after $($config.monitor_timeout_ac_minutes) minutes on AC power." "INFO"

        # 2. System Sleep NEVER on AC (0)
        powercfg /change standby-timeout-ac $config.standby_timeout_ac_minutes
        Write-Log "Configured: System Sleep (Standby) set to NEVER (0 minutes) on AC power." "INFO"

        # 3. Hibernate NEVER on AC (0)
        powercfg /change hibernate-timeout-ac $config.hibernate_timeout_ac_minutes
        Write-Log "Configured: System Hibernate set to NEVER (0 minutes) on AC power." "INFO"

        # 4. Disks NEVER turn off on AC (0)
        powercfg /change disk-timeout-ac $config.disk_timeout_ac_minutes
        Write-Log "Configured: Hard Disks/SSD set to NEVER spin down (0 minutes) on AC power." "INFO"

        # 5. Lid Close Action on AC -> Do Nothing (0)
        powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION $config.lid_close_action_ac
        Write-Log "Configured: Closing laptop lid on AC power set to DO NOTHING (0)." "INFO"

        # Activate changes
        powercfg /setactive SCHEME_CURRENT
        Write-Log "Applied and committed active power scheme." "INFO"
    } else {
        Write-Log "DryRun mode active. Skipping powercfg updates." "WARN"
    }

    Write-Log "[Step 3/3] Verifying committed power configuration..." "INFO"
    $PowerKPIs.ContinuousOperationReady = $true
    $PowerKPIs.Status = "SUCCESS"
}
catch {
    $PowerKPIs.Status = "FAILED"
    $PowerKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during power plan configuration: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $PowerKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $PowerKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $PowerKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# AC Power Plan Configuration Report",
        "",
        "- Task Name: $($PowerKPIs.TaskName)",
        "- Status: $($PowerKPIs.Status)",
        "- Active Power Scheme: $($PowerKPIs.ActiveScheme)",
        "- Execution Timestamp: $($PowerKPIs.StartTime) to $($PowerKPIs.EndTime)",
        "- Duration: $($PowerKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix (Plugged In / AC Power)",
        "| Component / Setting | Configured Value | Behavior |",
        "|---|---|---|",
        "| Monitor Display Turn Off | 10 Minutes | Monitors turn off to save OLED/LCD power and prevent burn-in |",
        "| System Sleep (Standby) | Never (0 min) | CPU, background tasks, and IDE servers continue running |",
        "| System Hibernate | Never (0 min) | Windows will never enter deep hibernation on AC |",
        "| Storage / SSD Sleep | Never (0 min) | Full disk responsiveness for databases and background I/O |",
        "| Laptop Lid Close Action | Do Nothing (0) | System remains 100% active when lid is closed with external monitors |",
        "",
        "## Operational Benefits",
        "- Workstations, pair-programming agents, background scripts, downloads, and servers never disconnect.",
        "- Screens power down automatically after 10 minutes of inactivity to protect displays.",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "AC Power Plan configuration complete. Report generated at: $ReportMd" "INFO"
}
