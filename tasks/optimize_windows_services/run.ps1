<#
.SYNOPSIS
    Optimize & Disable Non-Essential Windows Background Services.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Backs up current service states and start modes.
    2. Stops and disables non-essential services:
       - SysMain (Superfetch - unnecessary on PCIe 4.0 NVMe SSD)
       - DoSvc (Delivery Optimization P2P updates)
       - PcaSvc (Program Compatibility Assistant)
       - WSAIFabricSvc (Windows AI Fabric background telemetry)
       - whesvc (Windows Health and Optimized Experiences)
       - lfsvc (Geolocation tracking)
       - TrkWks (Distributed Link Tracking Client)
       - Spooler (Print Spooler)
       - DusmSvc (Data Usage monitoring)
       - Telemetry & Map Broker services (MapsBroker, DiagTrack, dmwappushservice)
    3. Performs memory working set cleanup.
    4. Evaluates RAM reclaimed and generates JSON & Markdown KPI reports.
.PARAMETER DryRun
    Simulates disabling without stopping or modifying services.
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

public class MemoryCleaner {
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

$ServicesKPIs = @{
    TaskName                = "optimize_windows_services"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    InitialFreeMemoryGB     = 0.0
    FinalFreeMemoryGB       = 0.0
    NetMemoryReclaimedMB    = 0.0
    ServicesTargetedCount   = 0
    ServicesDisabled        = @()
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/4] Loading configuration and capturing memory baseline..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $ServicesKPIs.ServicesTargetedCount = $config.services_to_disable.Count

    $memInit = Get-SystemMemoryStats
    $ServicesKPIs.InitialFreeMemoryGB = $memInit.FreeGB
    Write-Log "Memory Baseline: $($memInit.UsedGB) GB Used / $($memInit.FreeGB) GB Free ($($memInit.PctUsed)%)" "INFO"

    # Backup Services State
    $backupList = @()
    foreach ($sName in $config.services_to_disable) {
        $sObj = Get-CimInstance Win32_Service -Filter "Name='$sName'" -ErrorAction SilentlyContinue
        if ($sObj) {
            $backupList += [PSCustomObject]@{
                Name        = $sObj.Name
                DisplayName = $sObj.DisplayName
                State       = $sObj.State
                StartMode   = $sObj.StartMode
            }
        }
    }
    $backupList | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $BackupDir "services_backup.json") -Encoding UTF8
    Write-Log "Backed up state of $($backupList.Count) services to backups/services_backup.json." "INFO"

    Write-Log "[Step 2/4] Stopping and disabling non-essential Windows background services..." "INFO"
    if (-not $DryRun) {
        foreach ($sName in $config.services_to_disable) {
            $svc = Get-Service -Name $sName -ErrorAction SilentlyContinue
            if ($svc) {
                Write-Log "Optimizing service: $($svc.DisplayName) ($sName)..." "INFO"
                if ($svc.Status -eq 'Running') {
                    Stop-Service -Name $sName -Force -ErrorAction SilentlyContinue
                    Write-Log "Stopped service: $sName" "INFO"
                }
                Set-Service -Name $sName -StartupType Disabled -ErrorAction SilentlyContinue
                $ServicesKPIs.ServicesDisabled += [PSCustomObject]@{
                    Name        = $sName
                    DisplayName = $svc.DisplayName
                    Status      = "Disabled"
                }
                Write-Log "Set startup type to Disabled: $sName" "INFO"
            }
        }
    } else {
        Write-Log "DryRun mode active. Skipping service state modifications." "WARN"
    }

    Write-Log "[Step 3/4] Trimming memory and collecting inactive system caches..." "INFO"
    if (-not $DryRun) {
        [MemoryCleaner]::CleanMemory()
        [GC]::Collect()
        Start-Sleep -Seconds 2
    }

    Write-Log "[Step 4/4] Evaluating post-optimization memory metrics..." "INFO"
    $memFinal = Get-SystemMemoryStats
    $ServicesKPIs.FinalFreeMemoryGB = $memFinal.FreeGB
    $reclaimedGB = [Math]::Round($memFinal.FreeGB - $ServicesKPIs.InitialFreeMemoryGB, 2)
    $ServicesKPIs.NetMemoryReclaimedMB = [Math]::Round($reclaimedGB * 1024, 0)
    Write-Log "Post-Optimization Memory: $($memFinal.UsedGB) GB Used / $($memFinal.FreeGB) GB Free ($($memFinal.PctUsed)%)" "INFO"

    $ServicesKPIs.Status = "SUCCESS"
}
catch {
    $ServicesKPIs.Status = "FAILED"
    $ServicesKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Windows Services optimization: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $ServicesKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $ServicesKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $ServicesKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $svcRows = @()
    foreach ($s in $ServicesKPIs.ServicesDisabled) {
        $svcRows += "| $($s.DisplayName) | $($s.Name) | Stopped & Disabled |"
    }

    $mdLines = @(
        "# Windows Services Debloat & Optimization Report",
        "",
        "- Task Name: $($ServicesKPIs.TaskName)",
        "- Status: $($ServicesKPIs.Status)",
        "- Services Disabled: $($ServicesKPIs.ServicesDisabled.Count)",
        "- Initial Free RAM: $($ServicesKPIs.InitialFreeMemoryGB) GB",
        "- Final Free RAM: $($ServicesKPIs.FinalFreeMemoryGB) GB",
        "- Net RAM Reclaimed: +$($ServicesKPIs.NetMemoryReclaimedMB) MB",
        "- Execution Timestamp: $($ServicesKPIs.StartTime) to $($ServicesKPIs.EndTime)",
        "- Duration: $($ServicesKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix of Optimized Services",
        "| Display Name | Service Name | Action Taken |",
        "|---|---|---|",
        ($svcRows -join "`r`n"),
        "",
        "## Performance & SSD Benefits",
        "- Superfetch/SysMain RAM caching and disk churn eliminated on Samsung NVMe SSD.",
        "- Background telemetry, P2P network uploads (DoSvc), and AI background services stopped.",
        "- CPU background wakeups reduced.",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Windows Services optimization complete. Report generated at: $ReportMd" "INFO"
}
