<#
.SYNOPSIS
    Set Default System Keyboard to English (United States) with Latin American Layout.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Sets en-US with Latin American keyboard layout (0409:0000080A) as primary language.
    2. Overrides default input method to 0409:0000080A across all applications.
    3. Synchronizes international settings to Windows Welcome Screen and System accounts.
.PARAMETER DryRun
    Simulates keyboard reconfiguration without modifying settings.
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

$KeyboardKPIs = @{
    TaskName             = "set_english_latin_america_keyboard"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    TargetLanguage       = "en-US"
    TargetInputTip       = "0409:0000080A"
    ActivePrimaryTip     = ""
    InputOverrideSet     = $false
    SettingsSynchronized = $false
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/3] Loading configuration and assembling language list..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    if (-not $DryRun) {
        # Create Language Object for en-US with Latin America Keyboard
        $enUS = New-WinUserLanguageList "en-US"
        $enUS[0].InputMethodTips.Clear()
        $enUS[0].InputMethodTips.Add("0409:0000080A") # Latin American Spanish Keyboard layout on en-US

        Write-Log "Applying new language list with primary input tip 0409:0000080A..." "INFO"
        Set-WinUserLanguageList -LanguageList $enUS -Force
    }

    Write-Log "[Step 2/3] Setting default input method override..." "INFO"
    if (-not $DryRun) {
        Set-WinDefaultInputMethodOverride -InputTip "0409:0000080A"
        $KeyboardKPIs.InputOverrideSet = $true
        Write-Log "Set-WinDefaultInputMethodOverride applied: 0409:0000080A" "INFO"

        if ($config.sync_welcome_screen) {
            Write-Log "Synchronizing settings to Welcome Screen and System accounts..." "INFO"
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true
            $KeyboardKPIs.SettingsSynchronized = $true
        }
    }

    Write-Log "[Step 3/3] Validating active keyboard configuration..." "INFO"
    if (-not $DryRun) {
        $activeList = Get-WinUserLanguageList
        $activeOverride = Get-WinDefaultInputMethodOverride
        $KeyboardKPIs.ActivePrimaryTip = $activeList[0].InputMethodTips[0]
        
        Write-Log "Verified Primary Language: $($activeList[0].LanguageTag)" "INFO"
        Write-Log "Verified Primary Input Tip: $($KeyboardKPIs.ActivePrimaryTip)" "INFO"
        Write-Log "Verified Input Override: $($activeOverride)" "INFO"
    }

    $KeyboardKPIs.Status = "SUCCESS"
}
catch {
    $KeyboardKPIs.Status = "FAILED"
    $KeyboardKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during keyboard layout setup: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $KeyboardKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $KeyboardKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $KeyboardKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        '# Default Keyboard Layout Configuration Report',
        '',
        "- Task Name: $($KeyboardKPIs.TaskName)",
        "- Status: $($KeyboardKPIs.Status)",
        "- Target Language: $($KeyboardKPIs.TargetLanguage)",
        "- Target Input Method Tip: $($KeyboardKPIs.TargetInputTip) (English US + Latin America Keyboard)",
        "- Active Primary Input Tip: $($KeyboardKPIs.ActivePrimaryTip)",
        "- Default Input Method Override Set: $($KeyboardKPIs.InputOverrideSet)",
        "- System & Welcome Screen Synchronized: $($KeyboardKPIs.SettingsSynchronized)",
        "- Execution Timestamp: $($KeyboardKPIs.StartTime) to $($KeyboardKPIs.EndTime)",
        "- Duration: $($KeyboardKPIs.DurationSeconds) s",
        '',
        '## Keyboard Architecture Details',
        '| Property | Configured Value | Description |',
        '|---|---|---|',
        '| Language | en-US | English (United States) |',
        '| Keyboard Layout | 0000080A | Latin American Spanish Layout (QWERTY, N, @ on AltGr+Q) |',
        '| Override | 0409:0000080A | Fixed default across all apps and windows |',
        '',
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Keyboard configuration complete. Report generated at: $ReportMd" "INFO"
}
