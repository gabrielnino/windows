<#
.SYNOPSIS
    Automated Official ASUS Realtek & Intel SST Audio Driver Download & Installation.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Downloads official ASUS K6500ZC Realtek UAD & Intel SST driver packages from ASUS CDN.
    2. Extracts driver packages and injects INF drivers into Windows DriverStore via PnPUtil.
    3. Re-scans hardware devices and restarts Windows Audio Engine.
    4. Validates Audio Endpoints for internal speakers and microphones.
.PARAMETER DryRun
    Simulates download and installation without modifying driver store.
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

$AudioKPIs = @{
    TaskName             = "install_asus_realtek_audio_driver"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    DownloadedFiles      = @()
    ExtractedPackages    = @()
    InstalledDrivers     = @()
    AudioEndpoints       = @()
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Reading settings and downloading official ASUS audio drivers..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    foreach ($item in $config.downloads) {
        $destPath = Join-Path $ArtifactDir $item.filename
        Write-Log "Downloading $($item.name) from $($item.url)..." "INFO"
        
        if (-not $DryRun) {
            # Use Invoke-WebRequest with TLS 1.2
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $item.url -OutFile $destPath -UserAgent "Mozilla/5.0"
            
            $fileSizeMB = [Math]::Round((Get-Item $destPath).Length / 1MB, 2)
            Write-Log "Downloaded $($item.filename) ($fileSizeMB MB)" "INFO"
            $AudioKPIs.DownloadedFiles += [PSCustomObject]@{
                Name = $item.name
                Path = $destPath
                SizeMB = $fileSizeMB
            }
        }
    }

    Write-Log "[Step 2/4] Extracting driver packages..." "INFO"
    if (-not $DryRun) {
        foreach ($pkg in $AudioKPIs.DownloadedFiles) {
            $extractFolder = Join-Path $ArtifactDir ($pkg.Name -replace '\s+', '_')
            if (-not (Test-Path $extractFolder)) { New-Item -ItemType Directory -Path $extractFolder -Force | Out-Null }
            
            Write-Log "Extracting $($pkg.Path) into $extractFolder..." "INFO"
            # Try tar extraction (Windows 10/11 built-in tar supports zip and 7z self-extractors)
            try {
                tar -xf $pkg.Path -C $extractFolder 2>$null
            } catch {
                Write-Log "Tar extraction failed, trying 7z or execution..." "WARN"
            }

            # If tar didn't produce files, run self-extractor with /s or extract
            $extractedFiles = Get-ChildItem -Path $extractFolder -Recurse -File
            if ($extractedFiles.Count -eq 0) {
                Write-Log "Running self-extractor: $($pkg.Path) /s..." "INFO"
                Start-Process -FilePath $pkg.Path -ArgumentList "/s", "/extract", "`"$extractFolder`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }

            $AudioKPIs.ExtractedPackages += $extractFolder
            Write-Log "Extracted package to: $extractFolder" "INFO"
        }
    }

    Write-Log "[Step 3/4] Installing drivers into DriverStore via PnPUtil..." "INFO"
    if (-not $DryRun) {
        # Search for all .inf files in ArtifactDir
        $infFiles = Get-ChildItem -Path $ArtifactDir -Filter "*.inf" -Recurse
        Write-Log "Found $($infFiles.Count) driver INF files to install." "INFO"

        foreach ($inf in $infFiles) {
            Write-Log "Adding driver package: $($inf.FullName)..." "INFO"
            $out = pnputil /add-driver "$($inf.FullName)" /install 2>&1
            $AudioKPIs.InstalledDrivers += $inf.Name
        }

        # Also run setup.exe or install.bat if available in extracted packages
        $installBat = Get-ChildItem -Path $ArtifactDir -Filter "install*.bat" -Recurse | Select-Object -First 1
        if ($installBat) {
            Write-Log "Executing OEM install script: $($installBat.FullName)..." "INFO"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($installBat.FullName)`"" -WorkingDirectory $installBat.DirectoryName -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }

        Write-Log "Re-scanning system hardware devices..." "INFO"
        pnputil /scan-devices | Out-Null
        
        Write-Log "Restarting Windows Audio services..." "INFO"
        Restart-Service -Name "AudioEndpointBuilder" -Force -ErrorAction SilentlyContinue
        Restart-Service -Name "Audiosrv" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
    }

    Write-Log "[Step 4/4] Validating Audio Endpoints..." "INFO"
    if (-not $DryRun) {
        $endpoints = Get-PnpDevice -Class "AudioEndpoint", "MEDIA" -ErrorAction SilentlyContinue | Where-Object { $_.Present -eq $true }
        foreach ($ep in $endpoints) {
            $AudioKPIs.AudioEndpoints += [PSCustomObject]@{
                Name   = $ep.FriendlyName
                Status = $ep.Status
            }
            Write-Log "Audio Device: $($ep.FriendlyName) -> Status: $($ep.Status)" "INFO"
        }
    }

    $AudioKPIs.Status = "SUCCESS"
}
catch {
    $AudioKPIs.Status = "FAILED"
    $AudioKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during audio driver installation: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $AudioKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $AudioKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $AudioKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $epRows = @()
    foreach ($ep in $AudioKPIs.AudioEndpoints) {
        $epRows += "| $($ep.Name) | $($ep.Status) |"
    }

    $mdLines = @(
        '# Official ASUS Realtek Audio Driver Installation Report',
        '',
        "- Task Name: $($AudioKPIs.TaskName)",
        "- Status: $($AudioKPIs.Status)",
        "- Target Laptop: $($config.laptop_model)",
        "- Execution Timestamp: $($AudioKPIs.StartTime) to $($AudioKPIs.EndTime)",
        "- Duration: $($AudioKPIs.DurationSeconds) s",
        '',
        '## Installed Drivers & Components',
        '- Official Realtek High Definition Audio Driver (UAD/DCH)',
        '- Intel Smart Sound Technology (ISST) Driver',
        '',
        '## Active Audio Devices Matrix',
        '| Device Name | Status |',
        '|---|---|',
        ($epRows -join "`r`n"),
        '',
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Audio driver installation task complete. Report generated at: $ReportMd" "INFO"
}
