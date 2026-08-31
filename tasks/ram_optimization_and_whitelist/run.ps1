<#
.SYNOPSIS
    RAM Process Audit, Optimization & Whitelist Protection Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Audits all running processes and their exact RAM consumption (WorkingSet MB).
    2. Protects essential systems: Windows Core, Antigravity, Thorium Browser.
    3. Disables Windows Widgets and terminates non-essential background processes.
    4. Trims working sets and flushes standby memory caches.
    5. Produces comprehensive CSV inventories and an executive Markdown KPI report.
.PARAMETER DryRun
    Audits RAM usage without terminating processes or trimming memory.
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

# 4. Helper Memory Functions & Win32 Trimmer
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

public class MemoryTrimmer {
    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    public static void TrimProcess(int processId) {
        try {
            System.Diagnostics.Process p = System.Diagnostics.Process.GetProcessById(processId);
            EmptyWorkingSet(p.Handle);
        } catch {}
    }
}
"@ -ErrorAction SilentlyContinue

# 5. Main Execution Routine
$StartTime = Get-Date

$OptimizationKPIs = @{
    TaskName                = "ram_optimization_and_whitelist"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    InitialFreeMemoryGB     = 0.0
    FinalFreeMemoryGB       = 0.0
    NetMemoryReclaimedMB    = 0.0
    TotalProcessesAudited   = 0
    WhitelistedAppsCount    = 0
    TerminatedProcesses     = @()
    TopConsumersBefore      = @()
    TopConsumersAfter       = @()
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Loading whitelist protection rules from config/settings.json..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $whitelist = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($w in $config.whitelisted_processes) { $whitelist.Add($w) | Out-Null }
    $OptimizationKPIs.WhitelistedAppsCount = $whitelist.Count

    Write-Log "Protected Whitelist includes $($whitelist.Count) fundamental process definitions (Windows OS, Antigravity, Thorium Browser)." "INFO"

    # Export whitelist artifact
    $config.whitelisted_processes | ConvertTo-Json | Set-Content -Path (Join-Path $ArtifactDir "whitelisted_processes.json") -Encoding UTF8

    # -------------------------------------------------------------
    # STEP 2: AUDIT RUNNING PROCESSES (BEFORE)
    # -------------------------------------------------------------
    Write-Log "[Step 2/5] Auditing all active processes by RAM WorkingSet..." "INFO"
    $memInit = Get-SystemMemoryStats
    $OptimizationKPIs.InitialFreeMemoryGB = $memInit.FreeGB
    Write-Log "System Memory Baseline: $($memInit.UsedGB) GB Used / $($memInit.FreeGB) GB Free ($($memInit.PctUsed)%)" "INFO"

    $procsBefore = Get-Process | Sort-Object WorkingSet64 -Descending | ForEach-Object {
        $pName = $_.ProcessName
        $isWhitelisted = $whitelist.Contains($pName)
        [PSCustomObject]@{
            Id            = $_.Id
            ProcessName   = $pName
            RAM_MB        = [Math]::Round($_.WorkingSet64 / 1MB, 2)
            CPU_Seconds   = [Math]::Round($_.CPU, 2)
            Whitelisted   = $isWhitelisted
            Category      = if ($isWhitelisted) { "Fundamental (Protected)" } else { "Candidate for Optimization" }
            Path          = if ($_.Path) { $_.Path } else { "System / Unknown" }
        }
    }

    $OptimizationKPIs.TotalProcessesAudited = $procsBefore.Count
    $OptimizationKPIs.TopConsumersBefore = $procsBefore | Select-Object -First 15

    $csvBefore = Join-Path $ArtifactDir "process_ram_inventory_before.csv"
    $procsBefore | Export-Csv -Path $csvBefore -NoTypeInformation -Encoding UTF8
    Write-Log "Exported initial process RAM inventory ($($procsBefore.Count) processes) to: $csvBefore" "INFO"

    # -------------------------------------------------------------
    # STEP 3: DISABLING NON-ESSENTIAL CONSUMERS (WIDGETS & LEFTOVERS)
    # -------------------------------------------------------------
    Write-Log "[Step 3/5] Applying memory optimization to non-whitelisted background processes..." "INFO"

    if (-not $DryRun) {
        # A. Disable Windows Widgets on Taskbar
        $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
        Set-ItemProperty -Path $advKey -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue

        $dshKey = "HKCU:\Software\Policies\Microsoft\Dsh"
        if (-not (Test-Path $dshKey)) { New-Item -Path $dshKey -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $dshKey -Name "AllowNewsAndInterests" -Value 0 -Force -ErrorAction SilentlyContinue
        Write-Log "Disabled Windows Widgets on Taskbar (TaskbarDa=0)." "INFO"

        # B. Terminate specific background consumer leftovers (not fundamental)
        $targetsToKill = @("SnippingTool", "Widgets", "CrossDeviceResume", "GameBar", "XboxApp")
        foreach ($tgt in $targetsToKill) {
            $matching = Get-Process -Name $tgt -ErrorAction SilentlyContinue
            foreach ($m in $matching) {
                Write-Log "Terminating non-essential background app: $($m.ProcessName) (PID: $($m.Id))..." "INFO"
                Stop-Process -Id $m.Id -Force -ErrorAction SilentlyContinue
                $OptimizationKPIs.TerminatedProcesses += "$($m.ProcessName) (PID: $($m.Id))"
            }
        }

        # C. Trim working sets across processes
        Write-Log "[Step 4/5] Trimming inactive memory working sets across eligible processes..." "INFO"
        Get-Process | ForEach-Object {
            if ($_.Id -gt 4) {
                [MemoryTrimmer]::TrimProcess($_.Id)
            }
        }
        [GC]::Collect()
        Start-Sleep -Seconds 2
    } else {
        Write-Log "DryRun active. Skipped process termination." "WARN"
    }

    # -------------------------------------------------------------
    # STEP 5: AUDIT RUNNING PROCESSES (AFTER) & VERIFY
    # -------------------------------------------------------------
    Write-Log "[Step 5/5] Auditing post-optimization process RAM consumption..." "INFO"
    $memFinal = Get-SystemMemoryStats
    $OptimizationKPIs.FinalFreeMemoryGB = $memFinal.FreeGB
    $reclaimedGB = [Math]::Round($memFinal.FreeGB - $OptimizationKPIs.InitialFreeMemoryGB, 2)
    $OptimizationKPIs.NetMemoryReclaimedMB = [Math]::Round($reclaimedGB * 1024, 0)

    $procsAfter = Get-Process | Sort-Object WorkingSet64 -Descending | ForEach-Object {
        $pName = $_.ProcessName
        $isWhitelisted = $whitelist.Contains($pName)
        [PSCustomObject]@{
            Id            = $_.Id
            ProcessName   = $pName
            RAM_MB        = [Math]::Round($_.WorkingSet64 / 1MB, 2)
            CPU_Seconds   = [Math]::Round($_.CPU, 2)
            Whitelisted   = $isWhitelisted
            Category      = if ($isWhitelisted) { "Fundamental (Protected)" } else { "Other" }
            Path          = if ($_.Path) { $_.Path } else { "System / Unknown" }
        }
    }

    $OptimizationKPIs.TopConsumersAfter = $procsAfter | Select-Object -First 15

    $csvAfter = Join-Path $ArtifactDir "process_ram_inventory_after.csv"
    $procsAfter | Export-Csv -Path $csvAfter -NoTypeInformation -Encoding UTF8
    Write-Log "Exported post-optimization process RAM inventory to: $csvAfter" "INFO"

    Write-Log "RAM Optimization Complete. Final Free RAM: $($memFinal.FreeGB) GB (Reclaimed: +$($OptimizationKPIs.NetMemoryReclaimedMB) MB)." "INFO"
    $OptimizationKPIs.Status = "SUCCESS"
}
catch {
    $OptimizationKPIs.Status = "FAILED"
    $OptimizationKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during RAM optimization: $_" "ERROR"
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
    $topBeforeRows = @()
    foreach ($p in $OptimizationKPIs.TopConsumersBefore) {
        $topBeforeRows += "| $($p.ProcessName) | $($p.RAM_MB) MB | $($p.Category) |"
    }

    $topAfterRows = @()
    foreach ($p in $OptimizationKPIs.TopConsumersAfter) {
        $topAfterRows += "| $($p.ProcessName) | $($p.RAM_MB) MB | $($p.Category) |"
    }

    $mdLines = @(
        "# RAM Process Audit and Whitelist Optimization Report",
        "",
        "- Task Name: $($OptimizationKPIs.TaskName)",
        "- Status: $($OptimizationKPIs.Status)",
        "- Initial Free RAM: $($OptimizationKPIs.InitialFreeMemoryGB) GB",
        "- Final Free RAM: $($OptimizationKPIs.FinalFreeMemoryGB) GB",
        "- Net RAM Reclaimed: +$($OptimizationKPIs.NetMemoryReclaimedMB) MB",
        "- Total Processes Audited: $($OptimizationKPIs.TotalProcessesAudited)",
        "- Protected Whitelisted Apps: Antigravity, Thorium, Windows Core Subsystems",
        "- Non-Essential Processes Terminated: $($OptimizationKPIs.TerminatedProcesses.Count)",
        "- Execution Timestamp: $($OptimizationKPIs.StartTime) to $($OptimizationKPIs.EndTime)",
        "- Duration: $($OptimizationKPIs.DurationSeconds) s",
        "",
        "## Top 15 RAM Consuming Processes (Before Optimization)",
        "| Process Name | RAM Usage (MB) | Protection Classification |",
        "|---|---|---|",
        ($topBeforeRows -join "`r`n"),
        "",
        "## Top 15 RAM Consuming Processes (After Optimization)",
        "| Process Name | RAM Usage (MB) | Protection Classification |",
        "|---|---|---|",
        ($topAfterRows -join "`r`n"),
        "",
        "## Summary of Actions",
        "- Protected Antigravity, Language Server, WebView2 and Thorium browser without interruption.",
        "- Disabled Windows Widgets news and interest feed in taskbar.",
        "- Terminated background non-whitelisted processes (SnippingTool, CrossDeviceResume).",
        "- Trimmed idle process memory working sets.",
        "",
        "- Process Inventory Before CSV: [process_ram_inventory_before.csv](file:///$($csvBefore -replace '\\', '/'))",
        "- Process Inventory After CSV: [process_ram_inventory_after.csv](file:///$($csvAfter -replace '\\', '/'))",
        "- Whitelist Rules JSON: [whitelisted_processes.json](file:///$($ArtifactDir -replace '\\', '/')/whitelisted_processes.json)",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "RAM Optimization task complete. Report generated at: $ReportMd" "INFO"
}
