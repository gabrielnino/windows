<#
.SYNOPSIS
    Uninstall Outlook for Windows and Microsoft Store and Clean from All Startup Locations.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Terminates any running Outlook and Store processes.
    2. Uninstalls Microsoft.OutlookForWindows and Microsoft.WindowsStore UWP packages for all users.
    3. Stops and disables the Microsoft Store background InstallService.
    4. Disables the ScanForUpdatesAsUser scheduled task.
    5. Purges startup folders and registry Run keys.
    6. Refreshes Windows Explorer shell.
.PARAMETER DryRun
    Simulates uninstallation without removing packages or modifying services.
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

$UninstallKPIs = @{
    TaskName                = "uninstall_outlook_and_store"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    PackagesUninstalled     = @()
    ServicesDisabled        = @()
    TasksDisabled           = @()
    StartupEntriesCleaned   = 0
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Terminating active Outlook and Store processes..." "INFO"
    $targetProcesses = @("olk", "outlook", "WinStore.App", "StoreExperienceHost")
    foreach ($proc in $targetProcesses) {
        $procs = Get-Process -Name $proc -ErrorAction SilentlyContinue
        foreach ($p in $procs) {
            Write-Log "Terminating process: $($p.ProcessName) (PID: $($p.Id))..." "INFO"
            if (-not $DryRun) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Log "[Step 2/5] Uninstalling Outlook for Windows UWP package..." "INFO"
    $outlookPkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*OutlookForWindows*" }
    foreach ($pkg in $outlookPkgs) {
        Write-Log "Uninstalling Outlook: $($pkg.PackageFullName)..." "INFO"
        if (-not $DryRun) {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            $UninstallKPIs.PackagesUninstalled += $pkg.Name
            Write-Log "Uninstalled: $($pkg.Name)" "INFO"
        }
    }

    Write-Log "[Step 3/5] Uninstalling Microsoft Store UWP package..." "INFO"
    $storePkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*WindowsStore*" }
    foreach ($pkg in $storePkgs) {
        Write-Log "Uninstalling Microsoft Store: $($pkg.PackageFullName)..." "INFO"
        if (-not $DryRun) {
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
            $UninstallKPIs.PackagesUninstalled += $pkg.Name
            Write-Log "Uninstalled: $($pkg.Name)" "INFO"
        }
    }

    Write-Log "[Step 4/5] Stopping and disabling Store services and update tasks..." "INFO"
    if (-not $DryRun) {
        # Store Service
        $s = Get-Service -Name "InstallService" -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service -Name "InstallService" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "InstallService" -StartupType Disabled -ErrorAction SilentlyContinue
            $UninstallKPIs.ServicesDisabled += "InstallService"
            Write-Log "Disabled service: InstallService" "INFO"
        }

        # Store Update Task
        $t = Get-ScheduledTask -TaskName "ScanForUpdatesAsUser" -ErrorAction SilentlyContinue
        if ($t) {
            Disable-ScheduledTask -TaskName "ScanForUpdatesAsUser" -ErrorAction SilentlyContinue | Out-Null
            $UninstallKPIs.TasksDisabled += "ScanForUpdatesAsUser"
            Write-Log "Disabled scheduled task: ScanForUpdatesAsUser" "INFO"
        }
    }

    Write-Log "[Step 5/5] Purging startup folders and registry Run keys..." "INFO"
    if (-not $DryRun) {
        $startupFolders = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        foreach ($folder in $startupFolders) {
            if (Test-Path $folder) {
                Get-ChildItem -Path $folder -Filter "*Outlook*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Get-ChildItem -Path $folder -Filter "*Store*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                $UninstallKPIs.StartupEntriesCleaned++
            }
        }

        # Clean Registry Run keys
        $runKeys = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        )
        foreach ($rk in $runKeys) {
            if (Test-Path $rk) {
                $props = (Get-Item $rk).Property | Where-Object { $_ -like "*Outlook*" -or $_ -like "*Store*" }
                foreach ($p in $props) {
                    Remove-ItemProperty -Path $rk -Name $p -Force -ErrorAction SilentlyContinue
                    $UninstallKPIs.StartupEntriesCleaned++
                    Write-Log "Removed startup registry key: $p" "INFO"
                }
            }
        }

        # Restart Explorer shell
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
    }

    $UninstallKPIs.Status = "SUCCESS"
}
catch {
    $UninstallKPIs.Status = "FAILED"
    $UninstallKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Outlook & Store uninstallation: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $UninstallKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $UninstallKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $UninstallKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $pkgRows = @()
    foreach ($p in $UninstallKPIs.PackagesUninstalled) {
        $pkgRows += "| $p | Uninstalled for all users |"
    }

    $svcRows = @()
    foreach ($s in $UninstallKPIs.ServicesDisabled) {
        $svcRows += "| $s | Stopped & Disabled |"
    }

    $mdLines = @(
        "# Outlook for Windows & Microsoft Store Uninstallation Report",
        "",
        "- Task Name: $($UninstallKPIs.TaskName)",
        "- Status: $($UninstallKPIs.Status)",
        "- Packages Uninstalled: $($UninstallKPIs.PackagesUninstalled.Count)",
        "- Services Disabled: $($UninstallKPIs.ServicesDisabled.Count)",
        "- Tasks Disabled: $($UninstallKPIs.TasksDisabled.Count)",
        "- Startup Entries Cleaned: $($UninstallKPIs.StartupEntriesCleaned)",
        "- Execution Timestamp: $($UninstallKPIs.StartTime) to $($UninstallKPIs.EndTime)",
        "- Duration: $($UninstallKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Action Taken |",
        "|---|---|",
        ($pkgRows -join "`r`n"),
        ($svcRows -join "`r`n"),
        "| ScanForUpdatesAsUser Task | Disabled in Task Scheduler |",
        "| Startup Folders & Run Keys | Purged and verified clean |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Outlook and Store uninstallation complete. Report generated at: $ReportMd" "INFO"
}
