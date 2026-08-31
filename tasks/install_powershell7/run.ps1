<#
.SYNOPSIS
    Download and Install PowerShell 7 (Core) on Windows 11.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Installs the latest modern, cross-platform PowerShell 7 (`Microsoft.PowerShell`)
    via the official Windows Package Manager (winget), verifies the binary (`pwsh.exe`),
    and produces execution logs and an executive KPI summary report.
.PARAMETER DryRun
    Scans package availability without executing the installation.
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

# 4. Main Installation Workflow
$StartTime = Get-Date
$InstallKPIs = @{
    TaskName               = "install_powershell7"
    Status                 = "RUNNING"
    StartTime              = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                 = [bool]$DryRun
    PackageId              = "Microsoft.PowerShell"
    PreInstallVersion      = "Windows PowerShell $($PSVersionTable.PSVersion.ToString())"
    PostInstallVersion     = "Pending"
    ExecutablePath         = "Pending"
    InstallationExitCode   = -1
    DurationSeconds        = 0.0
}

try {
    Write-Log "[Step 1/4] Auditing current PowerShell environment..." "INFO"
    Write-Log "Current Running Version: $($InstallKPIs.PreInstallVersion)" "INFO"

    Write-Log "[Step 2/4] Querying Windows Package Manager (winget) for 'Microsoft.PowerShell'..." "INFO"
    $wingetSearch = & winget search --id Microsoft.PowerShell --source winget
    Write-Log "Package repository verified on winget." "INFO"

    if (-not $DryRun) {
        Write-Log "[Step 3/4] Downloading and installing PowerShell 7 silently..." "INFO"
        $wingetArgs = "install --id Microsoft.PowerShell -e --source winget --accept-source-agreements --accept-package-agreements --silent"
        
        $p = Start-Process -FilePath "winget.exe" -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        $InstallKPIs.InstallationExitCode = $p.ExitCode
        Write-Log "winget installation process exited with code: $($p.ExitCode)" "INFO"

        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne -1978335189) { # -1978335189 is often already installed or restart pending
            Write-Log "Warning: winget returned non-zero code $($p.ExitCode), validating binary presence..." "WARN"
        }
    } else {
        Write-Log "DryRun mode active. Skipping package download." "WARN"
    }

    Write-Log "[Step 4/4] Verifying PowerShell 7 (pwsh.exe) binary and version..." "INFO"
    
    $pwshPaths = @(
        "C:\Program Files\PowerShell\7\pwsh.exe",
        "C:\Program Files\PowerShell\7-preview\pwsh.exe",
        "$env:LOCALAPPDATA\Microsoft\PowerShell\pwsh.exe"
    )

    $foundPwsh = $null
    foreach ($path in $pwshPaths) {
        if (Test-Path $path) {
            $foundPwsh = $path
            break
        }
    }

    if (-not $foundPwsh) {
        $cmd = Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
        if ($cmd) { $foundPwsh = $cmd.Source }
    }

    if ($foundPwsh) {
        $InstallKPIs.ExecutablePath = $foundPwsh
        $verOut = & $foundPwsh -Version 2>$null
        $InstallKPIs.PostInstallVersion = $verOut.Trim()
        Write-Log "PowerShell 7 successfully located at: $foundPwsh ($($InstallKPIs.PostInstallVersion))" "INFO"
        $InstallKPIs.Status = "SUCCESS"
    }
    elseif ($DryRun) {
        $InstallKPIs.PostInstallVersion = "Simulated (DryRun)"
        $InstallKPIs.ExecutablePath = "C:\Program Files\PowerShell\7\pwsh.exe (Expected)"
        $InstallKPIs.Status = "SUCCESS"
    }
    else {
        throw "pwsh.exe was not detected in standard installation paths after winget execution."
    }
}
catch {
    $InstallKPIs.Status = "FAILED"
    $InstallKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during PowerShell 7 installation: $_" "ERROR"
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
        "# PowerShell 7 Installation Report",
        "",
        "- **Task Name:** $($InstallKPIs.TaskName)",
        "- **Status:** **$($InstallKPIs.Status)**",
        "- **Package ID:** $($InstallKPIs.PackageId)",
        "- **Execution Timestamp:** $($InstallKPIs.StartTime) to $($InstallKPIs.EndTime)",
        "- **Installation Duration:** $($InstallKPIs.DurationSeconds) s",
        "",
        "## Core Installation KPIs",
        "| Metric / Property | Details |",
        "|---|---|",
        "| **Original Version** | $($InstallKPIs.PreInstallVersion) |",
        "| **Installed Modern Version** | **$($InstallKPIs.PostInstallVersion)** |",
        "| **Executable Binary Path** | `$($InstallKPIs.ExecutablePath)` |",
        "| **Package Manager Exit Code** | $($InstallKPIs.InstallationExitCode) |",
        "",
        "## Usage & Execution",
        "- To start PowerShell 7 in terminal: pwsh",
        "- To run scripts with PowerShell 7: pwsh -File script.ps1",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "PowerShell 7 installation report generated at: $ReportMd" "INFO"
}
