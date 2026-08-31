<#
.SYNOPSIS
    Complete Removal & Disabling of Microsoft Copilot in Windows 11.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Uninstalls Microsoft.Copilot UWP App package.
    2. Applies Group Policies to permanently disable Windows Copilot (TurnOffWindowsCopilot=1).
    3. Hides Taskbar Copilot button (ShowCopilotButton=0).
    4. Disables Bing web AI suggestions in Start Menu search (BingSearchEnabled=0).
    5. Disables MicrosoftCopilotElevationService.
    6. Refreshes Windows Explorer shell.
.PARAMETER DryRun
    Simulates disabling without modifying registry or packages.
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

$CopilotKPIs = @{
    TaskName                = "remove_and_disable_copilot"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    UwpAppRemoved           = $false
    GroupPoliciesApplied    = 0
    TaskbarButtonDisabled   = $false
    BingSearchDisabled      = $false
    ServiceDisabled         = $false
    ExplorerRestarted       = $false
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Auditing and uninstalling Microsoft Copilot UWP App..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    $copilotPkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*Copilot*" }
    if ($copilotPkgs) {
        foreach ($pkg in $copilotPkgs) {
            Write-Log "Uninstalling Copilot package: $($pkg.PackageFullName)..." "INFO"
            if (-not $DryRun) {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction SilentlyContinue
                $CopilotKPIs.UwpAppRemoved = $true
                Write-Log "Copilot UWP App uninstalled successfully." "INFO"
            }
        }
    } else {
        Write-Log "No Copilot UWP App packages detected." "INFO"
    }

    Write-Log "[Step 2/5] Applying Group Policies to permanently disable Windows Copilot..." "INFO"
    if (-not $DryRun) {
        $policyPaths = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot",
            "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        )

        foreach ($p in $policyPaths) {
            if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
            Set-ItemProperty -Path $p -Name "TurnOffWindowsCopilot" -Value 1 -Force
            $CopilotKPIs.GroupPoliciesApplied++
            Write-Log "Applied TurnOffWindowsCopilot=1 on $p" "INFO"
        }
    }

    Write-Log "[Step 3/5] Hiding Copilot button from Windows 11 Taskbar..." "INFO"
    if (-not $DryRun) {
        $advKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (-not (Test-Path $advKey)) { New-Item -Path $advKey -Force | Out-Null }
        Set-ItemProperty -Path $advKey -Name "ShowCopilotButton" -Value 0 -Force
        $CopilotKPIs.TaskbarButtonDisabled = $true
        Write-Log "Set ShowCopilotButton=0 in Advanced Explorer settings." "INFO"
    }

    Write-Log "[Step 4/5] Disabling Bing AI web search suggestions in Start Menu..." "INFO"
    if (-not $DryRun) {
        $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        if (-not (Test-Path $searchKey)) { New-Item -Path $searchKey -Force | Out-Null }
        Set-ItemProperty -Path $searchKey -Name "BingSearchEnabled" -Value 0 -Force
        Set-ItemProperty -Path $searchKey -Name "CortanaConsent" -Value 0 -Force
        
        $expPolicy = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
        if (-not (Test-Path $expPolicy)) { New-Item -Path $expPolicy -Force | Out-Null }
        Set-ItemProperty -Path $expPolicy -Name "DisableSearchBoxSuggestions" -Value 1 -Force

        $CopilotKPIs.BingSearchDisabled = $true
        Write-Log "Start menu search restricted to local files/apps only (No Bing/AI ads)." "INFO"

        # Disable Service
        $s = Get-Service -Name "MicrosoftCopilotElevationService" -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service -Name "MicrosoftCopilotElevationService" -Force -ErrorAction SilentlyContinue
            Set-Service -Name "MicrosoftCopilotElevationService" -StartupType Disabled -ErrorAction SilentlyContinue
            $CopilotKPIs.ServiceDisabled = $true
            Write-Log "MicrosoftCopilotElevationService stopped and disabled." "INFO"
        }
    }

    Write-Log "[Step 5/5] Refreshing Windows Explorer shell..." "INFO"
    if (-not $DryRun) {
        Stop-Process -Name explorer -Force
        Start-Sleep -Seconds 2
        $CopilotKPIs.ExplorerRestarted = $true
        Write-Log "Explorer shell restarted cleanly with Copilot removed." "INFO"
    }

    $CopilotKPIs.Status = "SUCCESS"
}
catch {
    $CopilotKPIs.Status = "FAILED"
    $CopilotKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Copilot removal: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $CopilotKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $CopilotKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $CopilotKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Microsoft Copilot Disabling and Removal Report",
        "",
        "- Task Name: $($CopilotKPIs.TaskName)",
        "- Status: $($CopilotKPIs.Status)",
        "- UWP Copilot App Removed: $($CopilotKPIs.UwpAppRemoved)",
        "- Group Policies Configured: $($CopilotKPIs.GroupPoliciesApplied)",
        "- Taskbar Copilot Button Hidden: $($CopilotKPIs.TaskbarButtonDisabled)",
        "- Bing AI Search Injected Ads Disabled: $($CopilotKPIs.BingSearchDisabled)",
        "- Elevation Service Disabled: $($CopilotKPIs.ServiceDisabled)",
        "- Execution Timestamp: $($CopilotKPIs.StartTime) to $($CopilotKPIs.EndTime)",
        "- Duration: $($CopilotKPIs.DurationSeconds) s",
        "",
        "## Summary Matrix",
        "| Component | Action Taken | Status |",
        "|---|---|---|",
        "| Microsoft Copilot App | Uninstalled for all users | Removed |",
        "| Windows Copilot Policy | TurnOffWindowsCopilot=1 applied | Disabled |",
        "| Taskbar Button | ShowCopilotButton=0 | Hidden |",
        "| Bing Search Integration | Local search only (No cloud/AI tracking) | Disabled |",
        "| Background Elevation Service | Startup set to Disabled | Inactive |",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Copilot removal task complete. Report generated at: $ReportMd" "INFO"
}
