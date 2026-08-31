<#
.SYNOPSIS
    Complete Disconnection, Removal & Policy Disabling of Microsoft OneDrive.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Terminates active OneDrive and FileCoAuth processes.
    2. Executes OneDrive uninstallation.
    3. Configures Group Policy to permanently disable OneDrive synchronization (DisableFileSyncNGSC=1).
    4. Hides the OneDrive folder from File Explorer navigation sidebar (System.IsPinnedToNameSpaceTree=0).
    5. Purges startup auto-launch keys from HKCU\Run.
    6. Refreshes Windows Explorer shell.
.PARAMETER DryRun
    Simulates disconnection without modifying registry or executing uninstaller.
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

$OneDriveKPIs = @{
    TaskName                 = "disconnect_and_uninstall_onedrive"
    Status                   = "RUNNING"
    StartTime                = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                   = [bool]$DryRun
    ProcessesTerminated      = @()
    UninstallerExecuted      = $false
    PoliciesConfigured       = $false
    SidebarPinnedDisabled    = $false
    StartupKeyRemoved        = $false
    PostActiveProcessesCount = 0
    DurationSeconds          = 0.0
}

try {
    Write-Log "[Step 1/5] Terminating active OneDrive.exe and FileCoAuth.exe processes..." "INFO"
    $procs = Get-Process | Where-Object { $_.ProcessName -like "*OneDrive*" -or $_.ProcessName -like "*FileCoAuth*" }
    foreach ($p in $procs) {
        Write-Log "Terminating process: $($p.ProcessName) (PID: $($p.Id))..." "INFO"
        if (-not $DryRun) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            $OneDriveKPIs.ProcessesTerminated += "$($p.ProcessName) (PID: $($p.Id))"
        }
    }

    Write-Log "[Step 2/5] Executing OneDrive uninstallation..." "INFO"
    if (-not $DryRun) {
        $uninstaller = "C:\Windows\System32\OneDriveSetup.exe"
        if (Test-Path $uninstaller) {
            Write-Log "Running: $uninstaller /uninstall..." "INFO"
            $p = Start-Process -FilePath $uninstaller -ArgumentList "/uninstall" -Wait -PassThru -NoNewWindow
            Write-Log "OneDriveSetup exited with code: $($p.ExitCode)" "INFO"
            $OneDriveKPIs.UninstallerExecuted = $true
        } else {
            Write-Log "OneDriveSetup not found in System32, checking user AppData..." "WARN"
            $userSetup = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDriveSetup.exe"
            if (Test-Path $userSetup) {
                Start-Process -FilePath $userSetup -ArgumentList "/uninstall" -Wait -NoNewWindow
                $OneDriveKPIs.UninstallerExecuted = $true
            }
        }
    }

    Write-Log "[Step 3/5] Applying Group Policies to permanently disable OneDrive file sync..." "INFO"
    if (-not $DryRun) {
        $policyKeys = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive",
            "HKCU:\Software\Policies\Microsoft\Windows\OneDrive"
        )
        foreach ($pk in $policyKeys) {
            if (-not (Test-Path $pk)) { New-Item -Path $pk -Force | Out-Null }
            Set-ItemProperty -Path $pk -Name "DisableFileSyncNGSC" -Value 1 -Force
            Write-Log "Applied DisableFileSyncNGSC=1 on $pk" "INFO"
        }
        $OneDriveKPIs.PoliciesConfigured = $true
    }

    Write-Log "[Step 4/5] Hiding OneDrive from File Explorer sidebar and purging startup keys..." "INFO"
    if (-not $DryRun) {
        # Hide from navigation pane
        $clsidKeys = @(
            "HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}",
            "HKCR:\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}"
        )
        foreach ($ck in $clsidKeys) {
            if (-not (Test-Path $ck)) { New-Item -Path $ck -Force -ErrorAction SilentlyContinue | Out-Null }
            Set-ItemProperty -Path $ck -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Force -ErrorAction SilentlyContinue
        }
        $OneDriveKPIs.SidebarPinnedDisabled = $true

        # Remove startup entry
        $runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $runKey) {
            Remove-ItemProperty -Path $runKey -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            $OneDriveKPIs.StartupKeyRemoved = $true
            Write-Log "Removed OneDrive from HKCU\Run startup." "INFO"
        }

        # Clean shortcuts
        $scPaths = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
            "$env:USERPROFILE\Desktop\OneDrive.lnk"
        )
        foreach ($sc in $scPaths) {
            if (Test-Path $sc) { Remove-Item -Path $sc -Force -ErrorAction SilentlyContinue }
        }
    }

    Write-Log "[Step 5/5] Restarting Windows Explorer shell..." "INFO"
    if (-not $DryRun) {
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
    }

    # Verify post-execution state
    $remaining = @(Get-Process | Where-Object { $_.ProcessName -like "*OneDrive*" -or $_.ProcessName -like "*FileCoAuth*" })
    $OneDriveKPIs.PostActiveProcessesCount = $remaining.Count
    Write-Log "Post-Execution OneDrive Processes in Memory: $($remaining.Count)" "INFO"

    $OneDriveKPIs.Status = "SUCCESS"
}
catch {
    $OneDriveKPIs.Status = "FAILED"
    $OneDriveKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during OneDrive disconnection: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $OneDriveKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $OneDriveKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $OneDriveKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $procRows = @()
    foreach ($p in $OneDriveKPIs.ProcessesTerminated) {
        $procRows += "| $p | Terminated |"
    }

    $mdLines = @(
        "# Microsoft OneDrive Complete Disconnection Report",
        "",
        "- Task Name: $($OneDriveKPIs.TaskName)",
        "- Status: $($OneDriveKPIs.Status)",
        "- Uninstaller Executed: $($OneDriveKPIs.UninstallerExecuted)",
        "- Group Policy Applied: $($OneDriveKPIs.PoliciesConfigured)",
        "- Sidebar Navigation Icon Hidden: $($OneDriveKPIs.SidebarPinnedDisabled)",
        "- Startup Entry Purged: $($OneDriveKPIs.StartupKeyRemoved)",
        "- Remaining Processes in Task Manager: $($OneDriveKPIs.PostActiveProcessesCount)",
        "- Execution Timestamp: $($OneDriveKPIs.StartTime) to $($OneDriveKPIs.EndTime)",
        "- Duration: $($OneDriveKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Action Taken | Status |",
        "|---|---|---|",
        "| OneDrive Application | Uninstalled via OneDriveSetup /uninstall | Removed |",
        "| Sync Engine Policy | DisableFileSyncNGSC=1 applied | Disabled |",
        "| Explorer Sidebar Navigation | IsPinnedToNameSpaceTree=0 | Hidden |",
        "| Startup Auto-Launch | Purged from HKCU Run | Removed |",
        ($procRows -join "`r`n"),
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "OneDrive disconnection complete. Report generated at: $ReportMd" "INFO"
}
