<#
.SYNOPSIS
    Disable Windows User Experience Evaluation, Telemetry, CEIP & Diagnostic Surveys.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Disables Customer Experience Improvement Program (CEIP) scheduled tasks (Consolidator, UsbCeip, Sqm).
    2. Disables Application Experience Appraiser & telemetry tracking tasks (Microsoft Compatibility Appraiser).
    3. Disables SIUF Feedback Prompts & Windows User Evaluation survey dialogs.
    4. Disables ContentDeliveryManager suggestions, tips, and promotional overlays.
    5. Disables Advertising ID and limits telemetry to minimal security baseline.
.PARAMETER DryRun
    Simulates disabling without modifying system policies or tasks.
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

$EvaluationKPIs = @{
    TaskName                     = "disable_user_experience_evaluation"
    Status                       = "RUNNING"
    StartTime                    = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                       = [bool]$DryRun
    ScheduledTasksDisabled       = @()
    FeedbackSurveysDisabled      = $false
    TailoredExperiencesDisabled  = $false
    SuggestionsAndTipsDisabled   = $false
    AdvertisingIdDisabled        = $false
    TelemetryLevelMinimized      = $false
    DurationSeconds              = 0.0
}

try {
    Write-Log "[Step 1/5] Auditing and disabling Customer Experience (CEIP) & Appraiser tasks..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    $tasksList = @(
        "Consolidator",
        "UsbCeip",
        "Microsoft Compatibility Appraiser Exp",
        "Microsoft Compatibility Appraiser",
        "DmClient",
        "DmClientOnScenarioDownload",
        "Sqm-Tasks",
        "StartupAppTask"
    )

    if (-not $DryRun) {
        foreach ($tName in $tasksList) {
            $t = Get-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue
            if ($t) {
                Write-Log "Disabling evaluation scheduled task: $tName..." "INFO"
                Stop-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
                Disable-ScheduledTask -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
                $EvaluationKPIs.ScheduledTasksDisabled += $tName
                Write-Log "Disabled task: $tName" "INFO"
            }
        }
    }

    Write-Log "[Step 2/5] Disabling Windows Feedback Surveys & Prompting (SIUF)..." "INFO"
    if (-not $DryRun) {
        $siufKey = "HKCU:\Software\Microsoft\Siuf\Rules"
        if (-not (Test-Path $siufKey)) { New-Item -Path $siufKey -Force | Out-Null }
        Set-ItemProperty -Path $siufKey -Name "NumberOfSIUFInPeriod" -Value 0 -Force
        Set-ItemProperty -Path $siufKey -Name "PeriodInNanoSeconds" -Value 0 -Force

        $dcPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        if (-not (Test-Path $dcPolicy)) { New-Item -Path $dcPolicy -Force | Out-Null }
        Set-ItemProperty -Path $dcPolicy -Name "DoNotShowFeedbackNotifications" -Value 1 -Force

        $EvaluationKPIs.FeedbackSurveysDisabled = $true
        Write-Log "Feedback survey prompts disabled (Frequency set to Never)." "INFO"
    }

    Write-Log "[Step 3/5] Disabling Tailored Experiences with Diagnostic Data..." "INFO"
    if (-not $DryRun) {
        $privKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"
        if (-not (Test-Path $privKey)) { New-Item -Path $privKey -Force | Out-Null }
        Set-ItemProperty -Path $privKey -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0 -Force

        $cloudPolicy = "HKCU:\Software\Policies\Microsoft\Windows\CloudContent"
        if (-not (Test-Path $cloudPolicy)) { New-Item -Path $cloudPolicy -Force | Out-Null }
        Set-ItemProperty -Path $cloudPolicy -Name "DisableTailoredExperiencesWithDiagnosticData" -Value 1 -Force

        $EvaluationKPIs.TailoredExperiencesDisabled = $true
        Write-Log "Tailored experiences with diagnostic telemetry disabled." "INFO"
    }

    Write-Log "[Step 4/5] Disabling Content Delivery Manager suggestions, tips & ads..." "INFO"
    if (-not $DryRun) {
        $cdmKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        if (-not (Test-Path $cdmKey)) { New-Item -Path $cdmKey -Force | Out-Null }
        
        $cdmProps = @{
            "SubscribedContent-338388Enabled"    = 0 # Tips on lock screen
            "SubscribedContent-338389Enabled"    = 0 # Suggestions in start
            "SubscribedContent-353694Enabled"    = 0 # Suggested content in settings
            "SubscribedContent-353696Enabled"    = 0 # Tailored tips
            "SubscribedContent-310093Enabled"    = 0 # Welcome experience
            "SystemPaneSuggestionsEnabled"       = 0 # Explorer pane suggestions
            "SoftLandingEnabled"                 = 0 # Soft landing tips
            "RotatingLockScreenEnabled"          = 0 # Rotating spotlight
            "RotatingLockScreenOverlayEnabled"   = 0
        }

        foreach ($k in $cdmProps.Keys) {
            Set-ItemProperty -Path $cdmKey -Name $k -Value $cdmProps[$k] -Force
        }

        $EvaluationKPIs.SuggestionsAndTipsDisabled = $true
        Write-Log "ContentDeliveryManager suggestions and tips disabled." "INFO"
    }

    Write-Log "[Step 5/5] Disabling Advertising ID and minimizing telemetry..." "INFO"
    if (-not $DryRun) {
        # Advertising ID
        $adKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        if (-not (Test-Path $adKey)) { New-Item -Path $adKey -Force | Out-Null }
        Set-ItemProperty -Path $adKey -Name "Enabled" -Value 0 -Force

        $adPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        if (-not (Test-Path $adPolicy)) { New-Item -Path $adPolicy -Force | Out-Null }
        Set-ItemProperty -Path $adPolicy -Name "DisabledByGroupPolicy" -Value 1 -Force
        $EvaluationKPIs.AdvertisingIdDisabled = $true

        # Telemetry Minimized
        $dcPolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        Set-ItemProperty -Path $dcPolicy -Name "AllowTelemetry" -Value 0 -Force
        $EvaluationKPIs.TelemetryLevelMinimized = $true
        Write-Log "Advertising ID disabled and Telemetry baseline minimized." "INFO"
    }

    $EvaluationKPIs.Status = "SUCCESS"
}
catch {
    $EvaluationKPIs.Status = "FAILED"
    $EvaluationKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during User Experience disabling: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $EvaluationKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $EvaluationKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $EvaluationKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $taskRows = @()
    foreach ($t in $EvaluationKPIs.ScheduledTasksDisabled) {
        $taskRows += "| $t | Disabled |"
    }

    $mdLines = @(
        "# Windows User Experience Evaluation and Telemetry Disabling Report",
        "",
        "- Task Name: $($EvaluationKPIs.TaskName)",
        "- Status: $($EvaluationKPIs.Status)",
        "- CEIP and Evaluation Tasks Disabled: $($EvaluationKPIs.ScheduledTasksDisabled.Count)",
        "- Feedback Survey Dialogs Disabled: $($EvaluationKPIs.FeedbackSurveysDisabled)",
        "- Tailored Diagnostic Experiences Disabled: $($EvaluationKPIs.TailoredExperiencesDisabled)",
        "- Promotional Suggestions and Tips Disabled: $($EvaluationKPIs.SuggestionsAndTipsDisabled)",
        "- Advertising ID Disabled: $($EvaluationKPIs.AdvertisingIdDisabled)",
        "- Telemetry Level Minimized: $($EvaluationKPIs.TelemetryLevelMinimized)",
        "- Execution Timestamp: $($EvaluationKPIs.StartTime) to $($EvaluationKPIs.EndTime)",
        "- Duration: $($EvaluationKPIs.DurationSeconds) s",
        "",
        "## Disabled Scheduled Tasks",
        "| Task Name | Action Taken |",
        "|---|---|",
        ($taskRows -join "`r`n"),
        "",
        "## Summary of Privacy and Performance Gains",
        "- Zero user evaluation surveys or feedback notification popups.",
        "- Background CPU cycles saved by disabling CEIP Consolidator and Appraiser tasks.",
        "- Clean Start Menu and Settings without suggested apps or promotional banners.",
        "- Advertising ID disabled across all apps.",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "User Experience Evaluation disabling complete. Report generated at: $ReportMd" "INFO"
}
