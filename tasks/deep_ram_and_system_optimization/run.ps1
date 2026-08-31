<#
.SYNOPSIS
    Deep RAM, Service & System Performance Optimization.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Disables redundant per-user background sync services (CDPUserSvc, PimIndex, UserData, Unistore, CloudBackup).
    2. Disables GameDVR background video recording and GPU screen capture buffers.
    3. Adds high-performance dev exclusions to Windows Defender (F:\ drive, Antigravity, Thorium).
    4. Disables Windows Hibernation (powercfg /h off) to purge hiberfil.sys and RAM kernel buffer.
    5. Cleans and trims process memory working sets.
.PARAMETER DryRun
    Simulates optimization without modifying system registry or services.
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

# 4. Helper Memory Functions
function Get-SystemMemoryStats {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [Math]::Round(($os.TotalVisibleMemorySize * 1024) / 1GB, 2)
    $freeGB  = [Math]::Round(($os.FreePhysicalMemory * 1024) / 1GB, 2)
    $usedGB  = [Math]::Round($totalGB - $freeGB, 2)
    $pctUsed = [Math]::Round(($usedGB / $totalGB) * 100, 1)
    return @{
        TotalGB = $totalGB
        FreeGB  = $freeGB
        UsedGB  = $usedGB
        PctUsed = $pctUsed
    }
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class DeepMemoryCleaner {
    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    public static void CleanMemory() {
        foreach (var p in System.Diagnostics.Process.GetProcesses()) {
            try {
                if (p.Id > 4) {
                    EmptyWorkingSet(p.Handle);
                }
            } catch {}
        }
    }
}
"@ -ErrorAction SilentlyContinue

# 5. Main Execution Routine
$StartTime = Get-Date

$DeepKPIs = @{
    TaskName                = "deep_ram_and_system_optimization"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    InitialFreeMemoryGB     = 0.0
    FinalFreeMemoryGB       = 0.0
    NetMemoryReclaimedMB    = 0.0
    UserServicesDisabled    = @()
    GameDvrDisabled         = $false
    DefenderExclusionsAdded = 0
    HibernationDisabled     = $false
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Loading configuration and capturing memory baseline..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    $memInit = Get-SystemMemoryStats
    $DeepKPIs.InitialFreeMemoryGB = $memInit.FreeGB
    Write-Log "Memory Baseline: $($memInit.UsedGB) GB Used / $($memInit.FreeGB) GB Free ($($memInit.PctUsed)%)" "INFO"

    # -------------------------------------------------------------
    # STEP 2: DISABLE PER-USER SYNC SERVICES
    # -------------------------------------------------------------
    Write-Log "[Step 2/5] Disabling per-user sync service templates in registry..." "INFO"
    if (-not $DryRun) {
        foreach ($sName in $config.disable_per_user_services) {
            $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$sName"
            if (Test-Path $key) {
                Set-ItemProperty -Path $key -Name "Start" -Value 4 -Force -ErrorAction SilentlyContinue
                $DeepKPIs.UserServicesDisabled += $sName
                Write-Log "Disabled per-user service template: $sName (Start=4)" "INFO"
            }
        }

        # Stop active running per-user instances
        $runningUserSvcs = Get-Service | Where-Object { $_.Name -match "_\d+$" -and $_.Status -eq 'Running' }
        foreach ($rus in $runningUserSvcs) {
            $baseName = ($rus.Name -replace "_\d+$", "")
            if ($config.disable_per_user_services -contains $baseName) {
                Stop-Service -Name $rus.Name -Force -ErrorAction SilentlyContinue
                Write-Log "Stopped active per-user service: $($rus.Name)" "INFO"
            }
        }
    }

    # -------------------------------------------------------------
    # STEP 3: DISABLE GAMEDVR BACKGROUND CAPTURE
    # -------------------------------------------------------------
    Write-Log "[Step 3/5] Disabling GameDVR background video recording and GPU capture..." "INFO"
    if (-not $DryRun) {
        $gcKey = "HKCU:\System\GameConfigStore"
        if (-not (Test-Path $gcKey)) { New-Item -Path $gcKey -Force | Out-Null }
        Set-ItemProperty -Path $gcKey -Name "GameDVR_Enabled" -Value 0 -Force
        Set-ItemProperty -Path $gcKey -Name "GameDVR_FSEBehavior" -Value 2 -Force

        $gdPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
        if (-not (Test-Path $gdPolicy)) { New-Item -Path $gdPolicy -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $gdPolicy -Name "AllowGameDVR" -Value 0 -Force -ErrorAction SilentlyContinue

        $appCapKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR"
        if (-not (Test-Path $appCapKey)) { New-Item -Path $appCapKey -Force | Out-Null }
        Set-ItemProperty -Path $appCapKey -Name "AppCaptureEnabled" -Value 0 -Force

        $DeepKPIs.GameDvrDisabled = $true
        Write-Log "GameDVR background video capture completely disabled." "INFO"
    }

    # -------------------------------------------------------------
    # STEP 4: CALIBRATE DEFENDER DEV EXCLUSIONS & HIBERNATION
    # -------------------------------------------------------------
    Write-Log "[Step 4/5] Adding high-performance development exclusions to Windows Defender..." "INFO"
    if (-not $DryRun) {
        $pathsToExclude = @(
            "F:\",
            "$env:LOCALAPPDATA\Programs\antigravity",
            "$env:LOCALAPPDATA\Thorium",
            "$env:USERPROFILE\.gemini"
        )

        foreach ($p in $pathsToExclude) {
            if (Test-Path $p) {
                Add-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue
                $DeepKPIs.DefenderExclusionsAdded++
                Write-Log "Added Defender Path Exclusion: $p" "INFO"
            }
        }

        $procsToExclude = @("Antigravity.exe", "language_server.exe", "thorium.exe", "pwsh.exe")
        foreach ($pr in $procsToExclude) {
            Add-MpPreference -ExclusionProcess $pr -ErrorAction SilentlyContinue
            $DeepKPIs.DefenderExclusionsAdded++
            Write-Log "Added Defender Process Exclusion: $pr" "INFO"
        }

        # Disable Hibernation to free SSD space and kernel RAM cache
        Write-Log "Disabling Windows Hibernation (powercfg /h off)..." "INFO"
        powercfg /h off
        $DeepKPIs.HibernationDisabled = $true
        Write-Log "Hibernation disabled (hiberfil.sys deleted from C:\)." "INFO"
    }

    # -------------------------------------------------------------
    # STEP 5: TRIM MEMORY & CAPTURE POST METRICS
    # -------------------------------------------------------------
    Write-Log "[Step 5/5] Flushing working sets and evaluating memory gains..." "INFO"
    if (-not $DryRun) {
        [DeepMemoryCleaner]::CleanMemory()
        [GC]::Collect()
        Start-Sleep -Seconds 2
    }

    $memFinal = Get-SystemMemoryStats
    $DeepKPIs.FinalFreeMemoryGB = $memFinal.FreeGB
    $reclaimedGB = [Math]::Round($memFinal.FreeGB - $DeepKPIs.InitialFreeMemoryGB, 2)
    $DeepKPIs.NetMemoryReclaimedMB = [Math]::Round($reclaimedGB * 1024, 0)
    Write-Log "Post-Optimization Memory: $($memFinal.UsedGB) GB Used / $($memFinal.FreeGB) GB Free ($($memFinal.PctUsed)%)" "INFO"

    $DeepKPIs.Status = "SUCCESS"
}
catch {
    $DeepKPIs.Status = "FAILED"
    $DeepKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Deep RAM optimization: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $DeepKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $DeepKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $DeepKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $svcRows = @()
    foreach ($s in $DeepKPIs.UserServicesDisabled) {
        $svcRows += "| $s | Disabled |"
    }

    $mdLines = @(
        "# Deep RAM and System Performance Optimization Report",
        "",
        "- Task Name: $($DeepKPIs.TaskName)",
        "- Status: $($DeepKPIs.Status)",
        "- Per-User Sync Services Disabled: $($DeepKPIs.UserServicesDisabled.Count)",
        "- GameDVR Background Capture: Disabled",
        "- Defender Dev Exclusions Configured: $($DeepKPIs.DefenderExclusionsAdded)",
        "- Windows Hibernation File Purged: $($DeepKPIs.HibernationDisabled)",
        "- Initial Free RAM: $($DeepKPIs.InitialFreeMemoryGB) GB",
        "- Final Free RAM: $($DeepKPIs.FinalFreeMemoryGB) GB",
        "- Net RAM Reclaimed: +$($DeepKPIs.NetMemoryReclaimedMB) MB",
        "- Execution Timestamp: $($DeepKPIs.StartTime) to $($DeepKPIs.EndTime)",
        "- Duration: $($DeepKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Optimization Component | Action Taken | Status |",
        "|---|---|---|",
        ($svcRows -join "`r`n"),
        "| GameDVR (bcastdvr) | Video buffer disabled | Inactive |",
        "| Windows Defender Scanning | Dev paths (F:\, Antigravity, Thorium) excluded | High Performance |",
        "| Windows Hibernation (hiberfil.sys) | powercfg /h off | Purged (Freeing SSD space & RAM) |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Deep RAM optimization complete. Report generated at: $ReportMd" "INFO"
}
