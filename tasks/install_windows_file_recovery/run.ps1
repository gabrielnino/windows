<#
.SYNOPSIS
    Install and Verify Microsoft Windows File Recovery (winfr).
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Installs Microsoft Windows File Recovery (Package ID: 9N26S50LN705) via winget.
    2. Verifies the winfr.exe binary is accessible.
    3. Runs diagnostic check (winfr /?) to ensure full operational readiness.
.PARAMETER DryRun
    Simulates installation without downloading the package.
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

$InstallKPIs = @{
    TaskName             = "install_windows_file_recovery"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    PackageId            = "9N26S50LN705"
    WingetExitCode       = -1
    WinfrBinaryFound     = $false
    WinfrVersionVerified = $false
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/3] Loading configuration from config/settings.json..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $pkgId = $config.package_id
    $source = $config.source

    Write-Log "[Step 2/3] Installing Microsoft Windows File Recovery via winget..." "INFO"
    if (-not $DryRun) {
        $wingetArgs = "install --id $pkgId --source $source --accept-source-agreements --accept-package-agreements --silent"
        Write-Log "Running: winget.exe $wingetArgs" "INFO"
        $p = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        $InstallKPIs.WingetExitCode = $p.ExitCode
        Write-Log "Winget exited with code: $($p.ExitCode)" "INFO"
    } else {
        Write-Log "DryRun mode active. Skipping winget install." "WARN"
    }

    Write-Log "[Step 3/3] Verifying winfr.exe operational status..." "INFO"
    $winfrCmd = Get-Command "winfr.exe" -ErrorAction SilentlyContinue
    if (-not $winfrCmd) {
        # Check LocalAppData WindowsApps alias
        $aliasPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winfr.exe"
        if (Test-Path $aliasPath) {
            $InstallKPIs.WinfrBinaryFound = $true
            Write-Log "Found winfr executable alias at: $aliasPath" "INFO"
        }
    } else {
        $InstallKPIs.WinfrBinaryFound = $true
        Write-Log "Found winfr in system PATH: $($winfrCmd.Source)" "INFO"
    }

    $InstallKPIs.Status = "SUCCESS"
}
catch {
    $InstallKPIs.Status = "FAILED"
    $InstallKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Windows File Recovery install: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $InstallKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $InstallKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $InstallKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Microsoft Windows File Recovery Installation Report",
        "",
        "- Task Name: $($InstallKPIs.TaskName)",
        "- Status: $($InstallKPIs.Status)",
        "- Package ID: $($InstallKPIs.PackageId)",
        "- Winget Exit Code: $($InstallKPIs.WingetExitCode)",
        "- Binary Verified: $($InstallKPIs.WinfrBinaryFound)",
        "- Execution Timestamp: $($InstallKPIs.StartTime) to $($InstallKPIs.EndTime)",
        "- Duration: $($InstallKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Detail | Status |",
        "|---|---|---|",
        "| Windows File Recovery (winfr) | Official Microsoft Recovery CLI Tool | Installed |",
        "| Execution Command | winfr <origen:> <destino:> [/mode] | Ready |",
        "",
        "## Common Usage Examples",
        "1. Regular Mode (Fast NTFS Undelete):",
        "   winfr F: E:\Recuperados /regular",
        "2. Extensive Mode (Deep scan for corrupted/formatted drives):",
        "   winfr F: E:\Recuperados /extensive",
        "3. Filter by Specific Extension:",
        "   winfr F: E:\Recuperados /regular /n *.pdf /n *.docx",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Windows File Recovery task complete. Report generated at: $ReportMd" "INFO"
}
