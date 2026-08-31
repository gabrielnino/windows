<#
.SYNOPSIS
    Deep Audit of Third-Party Software, Non-Essential UWP Packages, Services & Tasks.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Scans:
      - Win32 installed software across 64-bit and 32-bit registry branches.
      - Consumer/OEM AppX packages (PhoneLink, DevHome, FeedbackHub, Teams, Xbox overlays).
      - Third-party scheduled tasks (Spotlight/Creative tasks, update checkers).
      - Non-kernel third-party background services and updaters.
    Produces structured CSV inventories and an executive Markdown KPI report.
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

$AuditKPIs = @{
    TaskName                   = "deep_third_party_software_audit"
    Status                     = "RUNNING"
    StartTime                  = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                     = [bool]$DryRun
    TotalWin32AppsFound        = 0
    TotalUwpBloatCandidates    = 0
    TotalThirdPartyTasks       = 0
    TotalThirdPartyServices    = 0
    DurationSeconds            = 0.0
}

try {
    # -------------------------------------------------------------
    # 1. WIN32 INSTALLED SOFTWARE AUDIT
    # -------------------------------------------------------------
    Write-Log "[Step 1/4] Auditing Win32 installed software programs..." "INFO"
    $win32Apps = @()
    $uninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($key in $uninstallKeys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
            $win32Apps += [PSCustomObject]@{
                DisplayName     = $_.DisplayName
                Publisher       = if ($_.Publisher) { $_.Publisher } else { "Unknown" }
                DisplayVersion  = if ($_.DisplayVersion) { $_.DisplayVersion } else { "N/A" }
                InstallLocation = if ($_.InstallLocation) { $_.InstallLocation } else { "Default" }
                UninstallString = if ($_.UninstallString) { $_.UninstallString } else { "N/A" }
            }
        }
    }
    $win32Apps = $win32Apps | Sort-Object Publisher, DisplayName -Unique
    $AuditKPIs.TotalWin32AppsFound = $win32Apps.Count
    Write-Log "Found $($win32Apps.Count) Win32 software programs." "INFO"

    $win32Csv = Join-Path $ArtifactDir "win32_software_inventory.csv"
    $win32Apps | Export-Csv -Path $win32Csv -NoTypeInformation -Encoding UTF8

    # -------------------------------------------------------------
    # 2. UWP / APPX NON-ESSENTIAL CONSUMER PACKAGES
    # -------------------------------------------------------------
    Write-Log "[Step 2/4] Auditing consumer and non-essential UWP packages..." "INFO"
    $nonEssentialKeywords = @(
        "*YourPhone*", "*FeedbackHub*", "*DevHome*", "*Xbox*", "*Teams*",
        "*ZuneMusic*", "*MicrosoftFamily*", "*QuickAssist*", "*Solitaire*",
        "*BingNews*", "*BingWeather*", "*Cortana*", "*GetHelp*", "*Clipchamp*"
    )

    $uwpCandidates = @()
    $allAppx = Get-AppxPackage
    foreach ($pkg in $allAppx) {
        $isCandidate = $false
        foreach ($kw in $nonEssentialKeywords) {
            if ($pkg.Name -like $kw) {
                $isCandidate = $true
                break
            }
        }
        if ($isCandidate) {
            $uwpCandidates += [PSCustomObject]@{
                PackageName     = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Publisher       = $pkg.PublisherId
                NonRemovable    = $pkg.NonRemovable
                Status          = if ($pkg.NonRemovable) { "System Core" } else { "Removable / Non-Essential" }
            }
        }
    }
    $uwpCandidates = $uwpCandidates | Sort-Object PackageName -Unique
    $AuditKPIs.TotalUwpBloatCandidates = $uwpCandidates.Count
    Write-Log "Identified $($uwpCandidates.Count) consumer/OEM UWP packages." "INFO"

    $uwpCsv = Join-Path $ArtifactDir "uwp_consumer_packages.csv"
    $uwpCandidates | Export-Csv -Path $uwpCsv -NoTypeInformation -Encoding UTF8

    # -------------------------------------------------------------
    # 3. THIRD-PARTY & VENDOR SCHEDULED TASKS
    # -------------------------------------------------------------
    Write-Log "[Step 3/4] Auditing third-party vendor and background updater scheduled tasks..." "INFO"
    $thirdPartyTasks = @()
    $allTasks = Get-ScheduledTask | Where-Object { 
        $_.TaskPath -notlike "\Microsoft\Windows\*" -and 
        $_.TaskPath -ne "\" -or
        $_.TaskName -like "*ASUS*" -or
        $_.TaskName -like "*Google*" -or
        $_.TaskName -like "*Edge*" -or
        $_.TaskName -like "*SoftLanding*"
    }

    foreach ($t in $allTasks) {
        $thirdPartyTasks += [PSCustomObject]@{
            TaskName = $t.TaskName
            State    = $t.State.ToString()
            TaskPath = $t.TaskPath
        }
    }
    $AuditKPIs.TotalThirdPartyTasks = $thirdPartyTasks.Count
    Write-Log "Found $($thirdPartyTasks.Count) third-party / updater scheduled tasks." "INFO"

    $tasksCsv = Join-Path $ArtifactDir "third_party_scheduled_tasks.csv"
    $thirdPartyTasks | Export-Csv -Path $tasksCsv -NoTypeInformation -Encoding UTF8

    # -------------------------------------------------------------
    # 4. THIRD-PARTY & BACKGROUND UPDATER SERVICES
    # -------------------------------------------------------------
    Write-Log "[Step 4/4] Auditing non-kernel services and updaters..." "INFO"
    $thirdPartyServices = @()
    $services = Get-CimInstance Win32_Service | Where-Object {
        $_.Name -like "*edgeupdate*" -or
        $_.Name -like "*Copilot*" -or
        $_.Name -like "*ASUS*" -or
        $_.Name -like "*Intel*" -or
        $_.Name -like "*Dolby*" -or
        $_.Name -like "*Realtek*"
    }

    foreach ($s in $services) {
        $thirdPartyServices += [PSCustomObject]@{
            ServiceName = $s.Name
            DisplayName = $s.DisplayName
            State       = $s.State
            StartMode   = $s.StartMode
            PathName    = $s.PathName
        }
    }
    $AuditKPIs.TotalThirdPartyServices = $thirdPartyServices.Count
    Write-Log "Found $($thirdPartyServices.Count) third-party / driver helper services." "INFO"

    $servicesCsv = Join-Path $ArtifactDir "third_party_services.csv"
    $thirdPartyServices | Export-Csv -Path $servicesCsv -NoTypeInformation -Encoding UTF8

    # Consolidated JSON Export
    $consolidatedJson = Join-Path $ArtifactDir "deep_software_audit_inventory.json"
    @{
        Win32Software       = $win32Apps
        UwpConsumerPackages = $uwpCandidates
        ScheduledTasks      = $thirdPartyTasks
        Services            = $thirdPartyServices
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $consolidatedJson -Encoding UTF8

    $AuditKPIs.Status = "SUCCESS"
}
catch {
    $AuditKPIs.Status = "FAILED"
    $AuditKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during deep software audit: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $AuditKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $AuditKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $AuditKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $win32Rows = @()
    foreach ($a in $win32Apps) {
        $win32Rows += "| **$($a.DisplayName)** | $($a.Publisher) | $($a.DisplayVersion) |"
    }

    $uwpRows = @()
    foreach ($u in $uwpCandidates) {
        $uwpRows += "| **$($u.PackageName)** | $($u.Status) |"
    }

    $taskRows = @()
    foreach ($t in $thirdPartyTasks) {
        $taskRows += "| **$($t.TaskName)** | $($t.State) | `$($t.TaskPath)` |"
    }

    $svcRows = @()
    foreach ($s in $thirdPartyServices) {
        $svcRows += "| **$($s.DisplayName)** | $($s.State) | $($s.StartMode) |"
    }

    $mdLines = @(
        "# Deep Third-Party Software, UWP Bloatware & Services Audit",
        "",
        "- **Task Name:** $($AuditKPIs.TaskName)",
        "- **Status:** **$($AuditKPIs.Status)**",
        "- **Win32 Programs Found:** **$($AuditKPIs.TotalWin32AppsFound)**",
        "- **Consumer UWP Packages Found:** **$($AuditKPIs.TotalUwpBloatCandidates)**",
        "- **Third-Party Tasks Audited:** **$($AuditKPIs.TotalThirdPartyTasks)**",
        "- **Driver / Third-Party Services:** **$($AuditKPIs.TotalThirdPartyServices)**",
        "- **Execution Timestamp:** $($AuditKPIs.StartTime) to $($AuditKPIs.EndTime)",
        "- **Duration:** $($AuditKPIs.DurationSeconds) s",
        "",
        "## 1. Win32 Installed Software Programs",
        "| Program Name | Publisher | Version |",
        "|---|---|---|",
        ($win32Rows -join "`r`n"),
        "",
        "## 2. Consumer & Non-Essential UWP Packages (Removable Bloatware Candidates)",
        "| Package Name | Removability Status |",
        "|---|---|",
        ($uwpRows -join "`r`n"),
        "",
        "## 3. Third-Party & Promotional Scheduled Tasks",
        "| Task Name | State | Path |",
        "|---|---|---|",
        ($taskRows -join "`r`n"),
        "",
        "## 4. Third-Party & Driver Companion Services",
        "| Service Display Name | Current State | Startup Type |",
        "|---|---|---|",
        ($svcRows -join "`r`n"),
        "",
        "## Exported Audit Artifacts",
        "- **Win32 Software CSV:** [win32_software_inventory.csv](file:///$($win32Csv -replace '\\', '/'))",
        "- **UWP Packages CSV:** [uwp_consumer_packages.csv](file:///$($uwpCsv -replace '\\', '/'))",
        "- **Scheduled Tasks CSV:** [third_party_scheduled_tasks.csv](file:///$($tasksCsv -replace '\\', '/'))",
        "- **Services CSV:** [third_party_services.csv](file:///$($servicesCsv -replace '\\', '/'))",
        "- **Consolidated JSON:** [deep_software_audit_inventory.json](file:///$($consolidatedJson -replace '\\', '/'))",
        "- **Detailed Log:** $LogFile"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Deep Software Audit completed. Report generated at: $ReportMd" "INFO"
}
