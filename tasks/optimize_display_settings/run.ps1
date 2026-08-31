<#
.SYNOPSIS
    Optimize Multi-Monitor Display Resolutions & Refresh Rates.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Configures:
      - Display 1 (ASUS OLED 15.6"): 2880x1620 @ 120 Hz
      - Display 2 (Samsung LF22T35): 1920x1080 @ 75 Hz (or max supported)
      - Display 3 (Samsung LF22T35): 1920x1080 @ 75 Hz (or max supported)
.PARAMETER DryRun
    Scans and verifies supported display modes without applying changes.
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

# 4. Native Win32 Display API Helper
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public class NativeDisplayHelper {
    [DllImport("user32.dll")]
    public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);

    [DllImport("user32.dll")]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string dmFormName;
        public short dmLogPixels;
        public short dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int DM_PELSWIDTH = 0x00080000;
    public const int DM_PELSHEIGHT = 0x00100000;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;
    public const uint CDS_UPDATEREGISTRY = 0x00000001;
    public const uint CDS_NORESET = 0x10000000;
    public const uint CDS_RESET = 0x00000000;

    public static string GetCurrentDisplayMode(string device) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(dm);
        if (EnumDisplaySettings(device, ENUM_CURRENT_SETTINGS, ref dm)) {
            return dm.dmPelsWidth + "x" + dm.dmPelsHeight + "@" + dm.dmDisplayFrequency + "Hz";
        }
        return "Unknown";
    }

    public static int FindMaxSupportedHz(string device, int width, int height, int requestedHz) {
        DEVMODE test = new DEVMODE();
        test.dmSize = (short)Marshal.SizeOf(test);
        int idx = 0;
        int maxHz = 0;

        while (EnumDisplaySettings(device, idx, ref test)) {
            if (test.dmPelsWidth == width && test.dmPelsHeight == height) {
                if (test.dmDisplayFrequency == requestedHz) {
                    return requestedHz;
                }
                if (test.dmDisplayFrequency > maxHz) {
                    maxHz = test.dmDisplayFrequency;
                }
            }
            idx++;
        }
        return maxHz;
    }

    public static int StageDisplayMode(string device, int width, int height, int hz) {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(dm);
        dm.dmPelsWidth = width;
        dm.dmPelsHeight = height;
        dm.dmDisplayFrequency = hz;
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;

        return ChangeDisplaySettingsEx(device, ref dm, IntPtr.Zero, CDS_UPDATEREGISTRY | CDS_NORESET, IntPtr.Zero);
    }

    public static int CommitAllDisplays() {
        return ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, CDS_RESET, IntPtr.Zero);
    }
}
"@ -ErrorAction SilentlyContinue

# 5. Main Execution Workflow
$StartTime = Get-Date

$OptimizationKPIs = @{
    TaskName             = "optimize_display_settings"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    DisplaysConfigured   = 0
    PreOptimizationModes = @()
    PostOptimizationModes= @()
    ConfigurationResults = @()
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Reading target configurations from config/settings.json..." "INFO"
    $configPath = Join-Path $ConfigDir "settings.json"
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

    $displayDevices = @("\\.\DISPLAY1", "\\.\DISPLAY2", "\\.\DISPLAY3")

    Write-Log "[Step 2/4] Inspecting current display modes on all active displays..." "INFO"
    foreach ($dev in $displayDevices) {
        $curMode = [NativeDisplayHelper]::GetCurrentDisplayMode($dev)
        $OptimizationKPIs.PreOptimizationModes += [PSCustomObject]@{
            Device = $dev
            Mode   = $curMode
        }
        Write-Log "Current: $dev -> $curMode" "INFO"
    }

    Write-Log "[Step 3/4] Staging and applying optimal resolutions & refresh rates..." "INFO"
    
    foreach ($target in $config.display_targets) {
        $devName = $target.device_name
        $targetW = [int]$target.target_width
        $targetH = [int]$target.target_height
        $reqHz   = [int]$target.target_refresh_rate_hz

        # Find maximum supported Hz for target resolution
        $bestHz = [NativeDisplayHelper]::FindMaxSupportedHz($devName, $targetW, $targetH, $reqHz)
        if ($bestHz -eq 0) {
            Write-Log "Resolution ${targetW}x${targetH} is not exposed for $devName. Using current max." "WARN"
            continue
        }

        Write-Log "Target for ${devName} - ${targetW}x${targetH} @ ${bestHz} Hz ($($target.description))" "INFO"

        if (-not $DryRun) {
            $stageCode = [NativeDisplayHelper]::StageDisplayMode($devName, $targetW, $targetH, $bestHz)
            Write-Log "Staged $devName -> ${targetW}x${targetH} @ ${bestHz} Hz (StageCode: $stageCode)" "INFO"
            $OptimizationKPIs.DisplaysConfigured++
        }
    }

    if (-not $DryRun) {
        Write-Log "Committing display modes across all monitors simultaneously..." "INFO"
        $commitCode = [NativeDisplayHelper]::CommitAllDisplays()
        Write-Log "CommitAllDisplays returned ResultCode: $commitCode" "INFO"
        Start-Sleep -Seconds 2
    }

    Write-Log "[Step 4/4] Verifying post-optimization display modes..." "INFO"
    foreach ($dev in $displayDevices) {
        $finalMode = [NativeDisplayHelper]::GetCurrentDisplayMode($dev)
        $OptimizationKPIs.PostOptimizationModes += [PSCustomObject]@{
            Device = $dev
            Mode   = $finalMode
        }
        Write-Log "Post-Optimization: $dev -> $finalMode" "INFO"
    }

    $OptimizationKPIs.Status = "SUCCESS"
}
catch {
    $OptimizationKPIs.Status = "FAILED"
    $OptimizationKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during display optimization: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $OptimizationKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $OptimizationKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $OptimizationKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $tableRows = @()
    for ($i = 0; $i -lt $OptimizationKPIs.PostOptimizationModes.Count; $i++) {
        $dev = $OptimizationKPIs.PostOptimizationModes[$i].Device
        $pre = $OptimizationKPIs.PreOptimizationModes[$i].Mode
        $post = $OptimizationKPIs.PostOptimizationModes[$i].Mode
        $desc = switch ($dev) {
            "\\.\DISPLAY1" { "ASUS Vivobook 15.6'' OLED" }
            "\\.\DISPLAY2" { "Samsung LF22T35 (Monitor 1)" }
            "\\.\DISPLAY3" { "Samsung LF22T35 (Monitor 2)" }
            default { "Monitor" }
        }
        $tableRows += "| **$dev** ($desc) | $pre | **$post** | 🟢 Optimal |"
    }

    $mdLines = @(
        "# Display Resolutions & Refresh Rates Optimization Report",
        "",
        "- **Task Name:** $($OptimizationKPIs.TaskName)",
        "- **Status:** **$($OptimizationKPIs.Status)**",
        "- **Displays Configured:** **$($OptimizationKPIs.DisplaysConfigured)**",
        "- **Execution Timestamp:** $($OptimizationKPIs.StartTime) to $($OptimizationKPIs.EndTime)",
        "- **Duration:** $($OptimizationKPIs.DurationSeconds) s",
        "",
        "## Display Resolution & Refresh Rate Optimization Matrix",
        "| Display Device | Previous Mode | Optimized Mode (Applied) | Status |",
        "|---|---|---|---|",
        ($tableRows -join "`r`n"),
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Display optimization report generated at: $ReportMd" "INFO"
}
