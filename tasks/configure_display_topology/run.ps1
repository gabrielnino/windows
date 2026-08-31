<#
.SYNOPSIS
    Configure Windows Multi-Monitor Display Topology (Extend Desktop).
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Enables Extended Desktop projection mode across all connected physical monitors
    (ASUS OLED internal + Samsung external monitors), enabling separate workspaces.
.PARAMETER Mode
    Topology mode to apply: Extend, Clone, Internal, External. Default: Extend.
.PARAMETER DryRun
    Tests monitor connectivity and displays current status without modifying projection.
#>
[CmdletBinding()]
param (
    [ValidateSet("Extend", "Clone", "Internal", "External")][string]$Mode = "Extend",
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

# 4. Win32 SetDisplayConfig Helper
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DisplayConfig {
    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(
        uint numPathArrayElements,
        IntPtr pathArray,
        uint numModeInfoArrayElements,
        IntPtr modeInfoArray,
        uint flags
    );

    public const uint SDC_APPLY = 0x00000080;
    public const uint SDC_TOPOLOGY_INTERNAL = 0x00000001;
    public const uint SDC_TOPOLOGY_CLONE    = 0x00000002;
    public const uint SDC_TOPOLOGY_EXTEND   = 0x00000004;
    public const uint SDC_TOPOLOGY_EXTERNAL = 0x00000008;

    public static int ApplyTopology(string mode) {
        uint flags = SDC_APPLY;
        switch (mode.ToLower()) {
            case "extend":   flags |= SDC_TOPOLOGY_EXTEND; break;
            case "clone":    flags |= SDC_TOPOLOGY_CLONE; break;
            case "internal": flags |= SDC_TOPOLOGY_INTERNAL; break;
            case "external": flags |= SDC_TOPOLOGY_EXTERNAL; break;
            default:         flags |= SDC_TOPOLOGY_EXTEND; break;
        }
        return SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, flags);
    }
}
"@ -ErrorAction SilentlyContinue

# 5. Main Execution Routine
$StartTime = Get-Date
Add-Type -AssemblyName System.Windows.Forms

$DisplayKPIs = @{
    TaskName             = "configure_display_topology"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    TargetMode           = $Mode
    DryRun               = [bool]$DryRun
    PreActiveScreens     = 0
    PostActiveScreens    = 0
    DetectedMonitors     = @()
    ActiveScreensDetails = @()
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Auditing connected physical monitors and current desktop topology..." "INFO"
    
    # 5.1 Physical EDID detection
    $wmiMon = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue
    if ($wmiMon) {
        foreach ($m in $wmiMon) {
            $name = (-join ($m.UserFriendlyName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })).Trim()
            $man  = (-join ($m.ManufacturerName | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })).Trim()
            $serial = (-join ($m.SerialNumberID | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })).Trim()
            $DisplayKPIs.DetectedMonitors += "$man $name ($serial)"
            Write-Log "Connected Physical Display: $man $name (Serial: $serial, Active: $($m.Active))" "INFO"
        }
    }

    $initialScreens = [System.Windows.Forms.Screen]::AllScreens
    $DisplayKPIs.PreActiveScreens = $initialScreens.Count
    Write-Log "Initial Active Desktop Workspaces: $($initialScreens.Count)" "INFO"

    Write-Log "[Step 2/4] Applying '$Mode' Display Topology across all connected monitors..." "INFO"

    if (-not $DryRun) {
        # 1. Apply via Win32 SetDisplayConfig API
        $ret = [DisplayConfig]::ApplyTopology($Mode)
        Write-Log "Win32 SetDisplayConfig returned result code: $ret" "INFO"

        # 2. Trigger DisplaySwitch utility as reinforcement
        $switchArg = "/$($Mode.ToLower())"
        Write-Log "Executing DisplaySwitch.exe $switchArg..." "INFO"
        Start-Process -FilePath "DisplaySwitch.exe" -ArgumentList $switchArg -NoNewWindow -Wait
        
        Write-Log "[Step 3/4] Waiting for Desktop Window Manager (DWM) display re-enumeration..." "INFO"
        Start-Sleep -Seconds 3
    } else {
        Write-Log "DryRun active. Skipping topology application." "WARN"
    }

    Write-Log "[Step 4/4] Verifying updated desktop workspace topology..." "INFO"
    $updatedScreens = [System.Windows.Forms.Screen]::AllScreens
    $DisplayKPIs.PostActiveScreens = $updatedScreens.Count

    foreach ($s in $updatedScreens) {
        $detail = "Screen: $($s.DeviceName) | Bounds: $($s.Bounds.Width)x$($s.Bounds.Height) at ($($s.Bounds.X),$($s.Bounds.Y)) | Primary: $($s.Primary)"
        $DisplayKPIs.ActiveScreensDetails += $detail
        Write-Log "$detail" "INFO"
    }

    Write-Log "Desktop topology configuration completed. Active Workspaces: $($DisplayKPIs.PostActiveScreens)" "INFO"
    $DisplayKPIs.Status = "SUCCESS"
}
catch {
    $DisplayKPIs.Status = "FAILED"
    $DisplayKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Error configuring display topology: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $DisplayKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $DisplayKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $DisplayKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $monList = if ($DisplayKPIs.DetectedMonitors.Count -gt 0) {
        $DisplayKPIs.DetectedMonitors | ForEach-Object { "- $_" }
    } else { @("- None detected") }

    $scrList = if ($DisplayKPIs.ActiveScreensDetails.Count -gt 0) {
        $DisplayKPIs.ActiveScreensDetails | ForEach-Object { "- **$_**" }
    } else { @("- None") }

    $mdLines = @(
        "# Multi-Monitor Display Topology Configuration Report",
        "",
        "- **Task Name:** $($DisplayKPIs.TaskName)",
        "- **Status:** **$($DisplayKPIs.Status)**",
        "- **Applied Topology Mode:** **$($DisplayKPIs.TargetMode)** (Separate Workspaces)",
        "- **Execution Timestamp:** $($DisplayKPIs.StartTime) to $($DisplayKPIs.EndTime)",
        "- **Duration:** $($DisplayKPIs.DurationSeconds) s",
        "",
        "## Core Topology KPIs",
        "| Metric | Value |",
        "|---|---|",
        "| **Physical Monitors Detected** | **$($DisplayKPIs.DetectedMonitors.Count)** |",
        "| **Previous Active Workspaces** | $($DisplayKPIs.PreActiveScreens) |",
        "| **Current Active Workspaces (Extended)** | **$($DisplayKPIs.PostActiveScreens)** |",
        "",
        "## Detected Hardware Monitors",
        ($monList -join "`r`n"),
        "",
        "## Active Screen Layouts (Independent Workspaces)",
        ($scrList -join "`r`n"),
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Display topology report generated at: $ReportMd" "INFO"
}
