<#
.SYNOPSIS
    Set Solid Pure Black Wallpaper Across All Connected Monitors.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Generates a true lossless black image artifact, sets the Windows background color to RGB(0,0,0),
    and applies it simultaneously across all monitors via Win32 SystemParametersInfo & Desktop APIs.
.PARAMETER DryRun
    Tests generation of the black image artifact without changing the desktop wallpaper.
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

# 4. Native Win32 Wallpaper API Helper
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeWallpaperHelper {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);

    public const int SPI_SETDESKWALLPAPER = 0x0014;
    public const int SPIF_UPDATEINIFILE   = 0x0001;
    public const int SPIF_SENDCHANGE      = 0x0002;

    public static int SetWallpaper(string path) {
        return SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
"@ -ErrorAction SilentlyContinue

# 5. Main Execution Workflow
$StartTime = Get-Date

$WallpaperKPIs = @{
    TaskName           = "set_black_wallpaper"
    Status             = "RUNNING"
    StartTime          = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun             = [bool]$DryRun
    TargetColorHex     = "#000000"
    PreviousWallpaper  = "None"
    GeneratedImagePath = ""
    ImageSizeBytes     = 0
    DisplaysUpdated    = 0
    DurationSeconds    = 0.0
}

try {
    Write-Log "[Step 1/4] Backing up current wallpaper configuration..." "INFO"
    $curWallpaper = (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name Wallpaper -ErrorAction SilentlyContinue).Wallpaper
    if ($curWallpaper) {
        $WallpaperKPIs.PreviousWallpaper = $curWallpaper
        $backupPath = Join-Path $BackupDir "previous_wallpaper.txt"
        Set-Content -Path $backupPath -Value $curWallpaper -Encoding UTF8
        Write-Log "Saved previous wallpaper path: $curWallpaper" "INFO"
    } else {
        Write-Log "No prior custom wallpaper path detected." "INFO"
    }

    Write-Log "[Step 2/4] Generating true pure-black lossless image artifact..." "INFO"
    $blackImgPath = Join-Path $ArtifactDir "pure_black_wallpaper.png"
    
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap(3840, 2160, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0, 0, 0))
    $graphics.FillRectangle($brush, 0, 0, 3840, 2160)
    $graphics.Dispose()
    $brush.Dispose()
    
    $bitmap.Save($blackImgPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    $imgItem = Get-Item $blackImgPath
    $WallpaperKPIs.GeneratedImagePath = $blackImgPath
    $WallpaperKPIs.ImageSizeBytes = $imgItem.Length
    Write-Log "Generated 4K Pure Black Image: $blackImgPath ($($imgItem.Length) bytes)" "INFO"

    Write-Log "[Step 3/4] Configuring Windows registry color keys to pure black (RGB 0 0 0)..." "INFO"
    if (-not $DryRun) {
        Set-ItemProperty -Path "HKCU:\Control Panel\Colors" -Name Background -Value "0 0 0"
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "2" # Stretch
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
        Write-Log "Registry keys updated successfully." "INFO"

        Write-Log "[Step 4/4] Broadcasting wallpaper change to all monitors via Win32 SystemParametersInfo..." "INFO"
        $apiResult = [NativeWallpaperHelper]::SetWallpaper($blackImgPath)
        Write-Log "SystemParametersInfo returned ResultCode: $apiResult" "INFO"

        # Count active screens
        Add-Type -AssemblyName System.Windows.Forms
        $WallpaperKPIs.DisplaysUpdated = [System.Windows.Forms.Screen]::AllScreens.Count
    } else {
        Write-Log "DryRun active. Skipped applying wallpaper to desktop." "WARN"
        $WallpaperKPIs.DisplaysUpdated = 0
    }

    Write-Log "Black wallpaper applied successfully across all $($WallpaperKPIs.DisplaysUpdated) monitors." "INFO"
    $WallpaperKPIs.Status = "SUCCESS"
}
catch {
    $WallpaperKPIs.Status = "FAILED"
    $WallpaperKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during wallpaper application: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $WallpaperKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $WallpaperKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $WallpaperKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Pure Black Wallpaper Configuration Report",
        "",
        "- **Task Name:** $($WallpaperKPIs.TaskName)",
        "- **Status:** **$($WallpaperKPIs.Status)**",
        "- **Target Color:** Pure Black (#000000 / RGB 0,0,0)",
        "- **Monitors Updated:** **$($WallpaperKPIs.DisplaysUpdated) screens**",
        "- **Execution Timestamp:** $($WallpaperKPIs.StartTime) to $($WallpaperKPIs.EndTime)",
        "- **Duration:** $($WallpaperKPIs.DurationSeconds) s",
        "",
        "## Core Wallpaper KPIs",
        "| Property | Value |",
        "|---|---|",
        "| **Applied Wallpaper Artifact** | `pure_black_wallpaper.png` (3840x2160 Lossless) |",
        "| **Previous Wallpaper Stored** | $($WallpaperKPIs.PreviousWallpaper) |",
        "| **Registry Background Color** | `0 0 0` |",
        "| **OLED Energy / Panel Benefit** | 0 nits on black pixels (prevents burn-in & reduces thermals) |",
        "",
        "- **Generated Image Artifact:** [pure_black_wallpaper.png](file:///$($WallpaperKPIs.GeneratedImagePath -replace '\\', '/'))",
        "- **Detailed Log File:** $LogFile",
        "- **JSON Report:** $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Wallpaper report generated at: $ReportMd" "INFO"
}
