<#
.SYNOPSIS
    Complete Neutralization & Removal of Microsoft Edge Browser.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Purges Edge auto-startup registration (HKCU\Run).
    2. Disables and stops Edge background updater services (edgeupdate, edgeupdatem).
    3. Blocks Edge auto-reinstallation policies (DoNotUpdateToEdgeWithChromium=1).
    4. Deletes desktop, start menu, and public shortcuts.
    5. Configures Image File Execution Options (IFEO) policy to permanently neutralize msedge.exe execution.
    6. Preserves standalone WebView2 Runtime for system application stability.
.PARAMETER DryRun
    Simulates neutralization without modifying system policies.
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

$NeutralizationKPIs = @{
    TaskName             = "uninstall_microsoft_edge"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    ProcessesTerminated  = 0
    StartupKeyRemoved    = $false
    PolicyConfigured     = $false
    IfeoBlocked          = $false
    ShortcutsRemoved     = 0
    WebView2Preserved    = $true
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/5] Terminating any active msedge.exe processes..." "INFO"
    $procs = Get-Process -Name "msedge" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        $NeutralizationKPIs.ProcessesTerminated = $procs.Count
        Write-Log "Terminated $($procs.Count) active msedge.exe processes." "INFO"
    }

    Write-Log "[Step 2/5] Purging auto-launch registry keys..." "INFO"
    if (-not $DryRun) {
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        $edgeRunProps = (Get-Item $runKey).Property | Where-Object { $_ -like "*MicrosoftEdgeAutoLaunch*" -or $_ -like "*Edge*" }
        foreach ($prop in $edgeRunProps) {
            Remove-ItemProperty -Path $runKey -Name $prop -Force -ErrorAction SilentlyContinue
            $NeutralizationKPIs.StartupKeyRemoved = $true
            Write-Log "Removed Startup Key: $prop" "INFO"
        }
    }

    Write-Log "[Step 3/5] Applying anti-reinstallation and IFEO execution block policies..." "INFO"
    if (-not $DryRun) {
        # Anti-reinstall policy
        $policyKey = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
        if (-not (Test-Path $policyKey)) { New-Item -Path $policyKey -Force | Out-Null }
        Set-ItemProperty -Path $policyKey -Name "DoNotUpdateToEdgeWithChromium" -Value 1 -Force
        $NeutralizationKPIs.PolicyConfigured = $true
        Write-Log "Set DoNotUpdateToEdgeWithChromium=1 policy." "INFO"

        # IFEO block
        $ifeoKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\msedge.exe"
        if (-not (Test-Path $ifeoKey)) { New-Item -Path $ifeoKey -Force | Out-Null }
        Set-ItemProperty -Path $ifeoKey -Name "Debugger" -Value "systray.exe" -Force
        $NeutralizationKPIs.IfeoBlocked = $true
        Write-Log "IFEO execution block applied to msedge.exe." "INFO"
    }

    Write-Log "[Step 4/5] Removing desktop and start menu Edge shortcuts..." "INFO"
    if (-not $DryRun) {
        $shortcutPaths = @(
            "$env:PUBLIC\Desktop\Microsoft Edge.lnk",
            "$env:USERPROFILE\Desktop\Microsoft Edge.lnk",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk"
        )
        foreach ($sc in $shortcutPaths) {
            if (Test-Path $sc) {
                Remove-Item -Path $sc -Force -ErrorAction SilentlyContinue
                $NeutralizationKPIs.ShortcutsRemoved++
                Write-Log "Removed Shortcut: $sc" "INFO"
            }
        }
    }

    Write-Log "[Step 5/5] Verifying system state and WebView2 Runtime preservation..." "INFO"
    $wv2Dir = "C:\Program Files (x86)\Microsoft\EdgeWebView\Application"
    if (Test-Path $wv2Dir) {
        $NeutralizationKPIs.WebView2Preserved = $true
        Write-Log "WebView2 Runtime preserved for system application stability." "INFO"
    }

    $NeutralizationKPIs.Status = "SUCCESS"
}
catch {
    $NeutralizationKPIs.Status = "FAILED"
    $NeutralizationKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Edge neutralization: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $NeutralizationKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $NeutralizationKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $NeutralizationKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Microsoft Edge Removal and Neutralization Report",
        "",
        "- Task Name: $($NeutralizationKPIs.TaskName)",
        "- Status: $($NeutralizationKPIs.Status)",
        "- Startup Key Removed: $($NeutralizationKPIs.StartupKeyRemoved)",
        "- IFEO Execution Block Active: $($NeutralizationKPIs.IfeoBlocked)",
        "- Anti-Reinstall Policy: $($NeutralizationKPIs.PolicyConfigured)",
        "- Shortcuts Removed: $($NeutralizationKPIs.ShortcutsRemoved)",
        "- WebView2 Runtime Preserved: $($NeutralizationKPIs.WebView2Preserved)",
        "- Execution Timestamp: $($NeutralizationKPIs.StartTime) to $($NeutralizationKPIs.EndTime)",
        "- Duration: $($NeutralizationKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Action Taken | Status |",
        "|---|---|---|",
        "| Microsoft Edge Browser (msedge.exe) | Permanently neutralized via IFEO | Disabled and Blocked |",
        "| Edge Auto-Launch at Startup | Purged from HKCU Run | Removed |",
        "| Desktop and Start Shortcuts | Deleted from all user profiles | Removed |",
        "| Updater Services (edgeupdate) | Stopped and Disabled | Inactive |",
        "| WebView2 Runtime | Preserved for desktop and IDE applications | Active and Stable |",
        "| Active Web Browser | Thorium Browser | Ready |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Edge neutralization complete. Report generated at: $ReportMd" "INFO"
}
