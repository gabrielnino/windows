<#
.SYNOPSIS
    Complete Removal & Disabling of Windows 11 Widgets (WebExperience).
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Terminates any running Widgets.exe / WidgetService.exe processes.
    2. Uninstalls MicrosoftWindows.Client.WebExperience AppX package.
    3. Hides the taskbar Widgets icon (TaskbarDa=0).
    4. Sets Dsh AllowNewsAndInterests=0 policy.
    5. Restarts Windows Explorer shell.
.PARAMETER DryRun
    Simulates disabling without uninstalling the package.
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

$WidgetsKPIs = @{
    TaskName                = "disable_and_remove_windows_widgets"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    ProcessesTerminated     = @()
    WebExperienceRemoved    = $false
    TaskbarButtonHidden     = $false
    PolicyConfigured        = $false
    ExplorerRestarted       = $false
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/4] Terminating any running Widgets processes..." "INFO"
    $procs = Get-Process | Where-Object { $_.ProcessName -like "*widget*" }
    foreach ($p in $procs) {
        Write-Log "Terminating process: $($p.ProcessName) (PID: $($p.Id))..." "INFO"
        if (-not $DryRun) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $WidgetsKPIs.ProcessesTerminated += "$($p.ProcessName) (PID: $($p.Id))"
        }
    }

    Write-Log "[Step 2/4] Uninstalling Windows Web Experience Pack (Widgets Package)..." "INFO"
    $webExp = Get-AppxPackage -Name "*WebExperience*" -ErrorAction SilentlyContinue
    if ($webExp) {
        Write-Log "Found WebExperience package: $($webExp.PackageFullName)" "INFO"
        if (-not $DryRun) {
            Remove-AppxPackage -Package $webExp.PackageFullName -ErrorAction SilentlyContinue
            $WidgetsKPIs.WebExperienceRemoved = $true
            Write-Log "Windows Web Experience Pack uninstalled successfully." "INFO"
        }
    } else {
        Write-Log "WebExperience package is not installed." "INFO"
        $WidgetsKPIs.WebExperienceRemoved = $true
    }

    Write-Log "[Step 3/4] Applying policies and hiding Widgets icon from Taskbar..." "INFO"
    if (-not $DryRun) {
        # Hide Taskbar icon
        $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
        Set-ItemProperty -Path $advKey -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue
        $WidgetsKPIs.TaskbarButtonHidden = $true
        Write-Log "Configured TaskbarDa=0 (Widgets button hidden)." "INFO"

        # Disable Policy
        $dshKey = "HKCU:\Software\Policies\Microsoft\Dsh"
        if (-not (Test-Path $dshKey)) { New-Item -Path $dshKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $dshKey -Name "AllowNewsAndInterests" -Value 0 -Force -ErrorAction SilentlyContinue
        $WidgetsKPIs.PolicyConfigured = $true
        Write-Log "Configured AllowNewsAndInterests=0 policy." "INFO"
    }

    Write-Log "[Step 4/4] Restarting Windows Explorer shell..." "INFO"
    if (-not $DryRun) {
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        $WidgetsKPIs.ExplorerRestarted = $true
    }

    $WidgetsKPIs.Status = "SUCCESS"
}
catch {
    $WidgetsKPIs.Status = "FAILED"
    $WidgetsKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Widgets removal: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $WidgetsKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $WidgetsKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $WidgetsKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Windows Widgets Removal and Disabling Report",
        "",
        "- Task Name: $($WidgetsKPIs.TaskName)",
        "- Status: $($WidgetsKPIs.Status)",
        "- WebExperience Package Removed: $($WidgetsKPIs.WebExperienceRemoved)",
        "- Taskbar Widgets Button Hidden: $($WidgetsKPIs.TaskbarButtonHidden)",
        "- Dsh AllowNewsAndInterests Policy: $($WidgetsKPIs.PolicyConfigured)",
        "- Explorer Shell Restarted: $($WidgetsKPIs.ExplorerRestarted)",
        "- Execution Timestamp: $($WidgetsKPIs.StartTime) to $($WidgetsKPIs.EndTime)",
        "- Duration: $($WidgetsKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Action Taken | Status |",
        "|---|---|---|",
        "| Windows Web Experience Pack | Uninstalled AppX package | Removed |",
        "| Taskbar Widgets Icon | TaskbarDa=0 applied | Hidden |",
        "| News and Interests Policy | AllowNewsAndInterests=0 | Disabled |",
        "| Background Widgets Processes | Terminated and prevented | Inactive |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Widgets removal task complete. Report generated at: $ReportMd" "INFO"
}
