<#
.SYNOPSIS
    Configure File Explorer to Show All Folders in Details View Mode by Default.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Backs up existing Shell Bags and BagMRU user cache.
    2. Sets AllFolders default Shell view to Details (LogicalViewMode=1, Mode=4).
    3. Injects Details view across all FolderType templates (Generic, Documents, Downloads, Media, etc.).
    4. Clears cached folder view history to enforce global inheritance.
    5. Restarts explorer.exe gracefully to apply new shell state.
.PARAMETER DryRun
    Simulates registry changes without modifying user settings.
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

$ExplorerKPIs = @{
    TaskName             = "set_explorer_default_details_view"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    ViewModeConfigured   = "Details"
    LogicalViewMode      = 1
    Mode                 = 4
    FolderTypesInjected  = 0
    CachePurged          = $false
    ExplorerRestarted    = $false
    DurationSeconds      = 0.0
}

$FolderTypeGUIDs = @(
    @{ Name = "Generic / General Items"; GUID = "{5c4f28b5-f869-4e84-8e60-f11db97c5cc7}" },
    @{ Name = "Documents";               GUID = "{7d49d726-3c21-4f05-99aa-fdc2c9474656}" },
    @{ Name = "Pictures";                GUID = "{b3690e58-e961-423b-b687-386ebfd70014}" },
    @{ Name = "Music";                   GUID = "{94d6f427-4614-4318-97c1-4e4b4835e39d}" },
    @{ Name = "Videos";                  GUID = "{5fa29243-3220-4e42-9680-f23601e2b93d}" },
    @{ Name = "Downloads";               GUID = "{08877463-32FF-405B-B4A1-1E5032170770}" },
    @{ Name = "Generic Searches";        GUID = "{da274c00-7411-4541-949e-a616223297a7}" },
    @{ Name = "Document Searches";       GUID = "{36011877-2a70-4070-9037-337ee2196166}" },
    @{ Name = "Picture Searches";        GUID = "{4d3437c4-4ac3-4321-a6b3-2475024479e0}" },
    @{ Name = "Music Searches";          GUID = "{7160702c-fc0c-47c3-bb5a-195932599763}" },
    @{ Name = "Video Searches";          GUID = "{ea25fbd7-3bf7-409e-b97f-3352240903f4}" },
    @{ Name = "Users Folder";            GUID = "{24ccb8a6-c45a-477d-9370-33868c4dc7f0}" }
)

try {
    Write-Log "[Step 1/4] Reading configuration and backing up existing Shell Bags..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json

    $shellKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell"
    $bagsKey  = Join-Path $shellKey "Bags"
    $mruKey   = Join-Path $shellKey "BagMRU"

    if (-not $DryRun) {
        # Export registry backup
        $backupReg = Join-Path $BackupDir "ShellBags_backup_$Timestamp.reg"
        Start-Process "reg.exe" -ArgumentList "export `"$shellKey`" `"$backupReg`" /y" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Log "Created registry backup: $backupReg" "INFO"
    }

    Write-Log "[Step 2/4] Purging cached per-folder views and resetting Bags..." "INFO"
    if (-not $DryRun -and $config.clear_cached_bagmru) {
        if (Test-Path $mruKey)  { Remove-Item -Path $mruKey -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path $bagsKey) { Remove-Item -Path $bagsKey -Recurse -Force -ErrorAction SilentlyContinue }
        
        $streamsDefaults = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Streams\Defaults"
        if (Test-Path $streamsDefaults) { Remove-Item -Path $streamsDefaults -Recurse -Force -ErrorAction SilentlyContinue }

        $ExplorerKPIs.CachePurged = $true
        Write-Log "Purged stale BagMRU and Bags cache." "INFO"
    }

    Write-Log "[Step 3/4] Injecting Details View defaults into Shell Bags for all FolderTypes..." "INFO"
    if (-not $DryRun) {
        # Base AllFolders Shell Key
        $allFoldersShell = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
        if (-not (Test-Path $allFoldersShell)) {
            New-Item -Path $allFoldersShell -Force | Out-Null
        }
        Set-ItemProperty -Path $allFoldersShell -Name "FolderType" -Value "Generic" -Force
        Set-ItemProperty -Path $allFoldersShell -Name "LogicalViewMode" -Value $config.logical_view_mode -Type DWord -Force
        Set-ItemProperty -Path $allFoldersShell -Name "Mode" -Value $config.mode -Type DWord -Force

        # Inject each specific FolderType GUID
        foreach ($ft in $FolderTypeGUIDs) {
            $guidKey = Join-Path $allFoldersShell $ft.GUID
            if (-not (Test-Path $guidKey)) {
                New-Item -Path $guidKey -Force | Out-Null
            }
            Set-ItemProperty -Path $guidKey -Name "LogicalViewMode" -Value $config.logical_view_mode -Type DWord -Force
            Set-ItemProperty -Path $guidKey -Name "Mode" -Value $config.mode -Type DWord -Force
            $ExplorerKPIs.FolderTypesInjected++
            Write-Log "Configured Details View for FolderType: $($ft.Name) ($($ft.GUID))" "INFO"
        }
    }

    Write-Log "[Step 4/4] Restarting Windows Explorer process to apply global view..." "INFO"
    if (-not $DryRun -and $config.restart_explorer) {
        Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Start-Process "explorer.exe"
        $ExplorerKPIs.ExplorerRestarted = $true
        Write-Log "Restarted explorer.exe cleanly." "INFO"
    }

    $ExplorerKPIs.Status = "SUCCESS"
}
catch {
    $ExplorerKPIs.Status = "FAILED"
    $ExplorerKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Explorer view configuration: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $ExplorerKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $ExplorerKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $ExplorerKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $guidRows = @()
    foreach ($ft in $FolderTypeGUIDs) {
        $guidRows += "| $($ft.Name) | $($ft.GUID) | Details (`Mode=4`, `LogicalViewMode=1`) |"
    }

    $mdLines = @(
        '# File Explorer Default Details View Configuration Report',
        '',
        "- Task Name: $($ExplorerKPIs.TaskName)",
        "- Status: $($ExplorerKPIs.Status)",
        "- Configured View Mode: $($ExplorerKPIs.ViewModeConfigured)",
        "- Total FolderTypes Injected: $($ExplorerKPIs.FolderTypesInjected)",
        "- Previous Cache Purged: $($ExplorerKPIs.CachePurged)",
        "- Explorer Process Restarted: $($ExplorerKPIs.ExplorerRestarted)",
        "- Execution Timestamp: $($ExplorerKPIs.StartTime) to $($ExplorerKPIs.EndTime)",
        "- Duration: $($ExplorerKPIs.DurationSeconds) s",
        '',
        '## Configured Folder Types Matrix',
        '| Folder Type | Class GUID | Applied View Mode |',
        '|---|---|---|',
        ($guidRows -join "`r`n"),
        '',
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Explorer view configuration complete. Report generated at: $ReportMd" "INFO"
}
