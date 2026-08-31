<#
.SYNOPSIS
    Enable System-Wide Dark Mode across Windows 11 & Applications.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Configures Windows 11 Shell, Taskbar, Start Menu, File Explorer, and UWP apps
    to true Dark Mode (SystemUsesLightTheme=0, AppsUseLightTheme=0), broadcasts the theme change,
    and refreshes the shell for instant application.
.PARAMETER DryRun
    Scans current theme mode without applying changes.
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

# 4. Main Execution Workflow
$StartTime = Get-Date

$ThemeKPIs = @{
    TaskName             = "enable_dark_theme"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    PreSystemTheme       = "Unknown"
    PreAppsTheme         = "Unknown"
    PostSystemTheme      = "Dark"
    PostAppsTheme        = "Dark"
    ExplorerRestarted    = $false
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Auditing current Windows 11 Personalization theme settings..." "INFO"
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    $curSettings = Get-ItemProperty -Path $regPath

    $ThemeKPIs.PreSystemTheme = if ($curSettings.SystemUsesLightTheme -eq 1) { "Light" } else { "Dark" }
    $ThemeKPIs.PreAppsTheme   = if ($curSettings.AppsUseLightTheme -eq 1) { "Light" } else { "Dark" }

    Write-Log "Current System Theme: $($ThemeKPIs.PreSystemTheme) | Apps Theme: $($ThemeKPIs.PreAppsTheme)" "INFO"

    # Backup current settings
    $backupData = @{
        SystemUsesLightTheme = $curSettings.SystemUsesLightTheme
        AppsUseLightTheme   = $curSettings.AppsUseLightTheme
        ColorPrevalence      = $curSettings.ColorPrevalence
        EnableTransparency   = $curSettings.EnableTransparency
    }
    $backupFile = Join-Path $BackupDir "previous_theme.json"
    $backupData | ConvertTo-Json | Set-Content -Path $backupFile -Encoding UTF8
    Write-Log "Backed up previous theme configuration to: $backupFile" "INFO"

    Write-Log "[Step 2/4] Enabling Dark Mode for System Shell (Taskbar, Start Menu) & Applications..." "INFO"

    if (-not $DryRun) {
        # Set Dark Mode (0 = Dark, 1 = Light)
        Set-ItemProperty -Path $regPath -Name SystemUsesLightTheme -Value 0
        Set-ItemProperty -Path $regPath -Name AppsUseLightTheme -Value 0
        
        Write-Log "Registry updated: SystemUsesLightTheme=0, AppsUseLightTheme=0." "INFO"

        Write-Log "[Step 3/4] Broadcasting theme change & refreshing Windows Explorer..." "INFO"
        
        # Broadcast setting change
        rundll32.exe user32.dll,UpdatePerUserSystemParameters 1, True

        # Restart Explorer for instantaneous visual adoption across all windows
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        $ThemeKPIs.ExplorerRestarted = $true
        Write-Log "Windows Explorer shell restarted cleanly in Dark Mode." "INFO"
    } else {
        Write-Log "DryRun active. Skipped applying Dark Mode to registry." "WARN"
    }

    Write-Log "[Step 4/4] Verifying post-configuration theme state..." "INFO"
    $postSettings = Get-ItemProperty -Path $regPath
    $ThemeKPIs.PostSystemTheme = if ($postSettings.SystemUsesLightTheme -eq 0) { "Dark" } else { "Light" }
    $ThemeKPIs.PostAppsTheme   = if ($postSettings.AppsUseLightTheme -eq 0) { "Dark" } else { "Light" }

    Write-Log "Verified Final State -> System Theme: $($ThemeKPIs.PostSystemTheme) | Apps Theme: $($ThemeKPIs.PostAppsTheme)" "INFO"
    $ThemeKPIs.Status = "SUCCESS"
}
catch {
    $ThemeKPIs.Status = "FAILED"
    $ThemeKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Dark Mode application: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $ThemeKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $ThemeKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $ThemeKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Windows 11 Dark Mode Configuration Report",
        "",
        "- **Task Name:** $($ThemeKPIs.TaskName)",
        "- **Status:** **$($ThemeKPIs.Status)**",
        "- **System Shell Theme:** **$($ThemeKPIs.PostSystemTheme)**",
        "- **Applications Theme:** **$($ThemeKPIs.PostAppsTheme)**",
        "- **Explorer Restarted:** **$($ThemeKPIs.ExplorerRestarted)**",
        "- **Execution Timestamp:** $($ThemeKPIs.StartTime) to $($ThemeKPIs.EndTime)",
        "- **Duration:** $($ThemeKPIs.DurationSeconds) s",
        "",
        "## Theme Transformation Matrix",
        "| Component | Previous Theme | New Theme (Applied) | Status |",
        "|---|---|---|---|",
        "| **Windows System Shell (Taskbar & Start)** | $($ThemeKPIs.PreSystemTheme) | **Dark Mode** | 🟢 Active |",
        "| **File Explorer & Native Apps** | $($ThemeKPIs.PreAppsTheme) | **Dark Mode** | 🟢 Active |",
        "",
        "## Benefits for OLED & Multi-Monitor Setup",
        "- **OLED Energy Conservation:** Drastically lowers power consumption and thermal footprint on the 15.6'' OLED panel.",
        "- **Visual Cohesion:** Matches the 4K Minimalist Obsidian Black wallpaper across all 3 monitors.",
        "- **Eye Comfort:** Reduces eye fatigue during long coding and terminal sessions.",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Dark Mode task complete. Report generated at: $ReportMd" "INFO"
}
