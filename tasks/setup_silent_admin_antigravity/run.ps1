<#
.SYNOPSIS
    Create Native Silent Administrator Elevation Launcher & Taskbar Shortcut for Antigravity.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    1. Creates elevated Windows Scheduled Task (Launch_Antigravity_Elevated, RunLevel=Highest).
    2. Compiles a native Windows GUI executable launcher (AntigravitySilentAdmin.exe, /target:winexe) for zero-window, zero-UAC execution.
    3. Creates Desktop and Start Menu shortcuts pointing directly to the compiled launcher with the official Antigravity icon.
    4. Allows immediate, 1-click "Pin to Taskbar" support.
.PARAMETER DryRun
    Simulates setup without modifying system tasks or shortcuts.
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

$SetupKPIs = @{
    TaskName                = "setup_silent_admin_antigravity"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    ScheduledTaskCreated    = $false
    CompiledLauncherPath    = ""
    DesktopShortcutPath     = ""
    StartMenuShortcutPath   = ""
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/4] Loading configuration from config/settings.json..." "INFO"
    $config = Get-Content -Path (Join-Path $ConfigDir "settings.json") -Raw | ConvertFrom-Json
    $antiExe = $config.antigravity_path
    $taskName = $config.task_scheduler_name
    $launcherDir = $config.launcher_dir

    if (-not (Test-Path $antiExe)) {
        throw "Antigravity executable not found at: $antiExe"
    }

    if (-not (Test-Path $launcherDir)) {
        New-Item -ItemType Directory -Path $launcherDir -Force | Out-Null
    }

    Write-Log "[Step 2/4] Registering elevated Scheduled Task in Windows Task Scheduler..." "INFO"
    if (-not $DryRun) {
        $action = New-ScheduledTaskAction -Execute $antiExe
        $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel -ExecutionTimeLimit (New-TimeSpan -Days 0)

        # Unregister existing task if present
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        
        # Register new elevated task
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Description "Silent Administrator Launcher for Google Antigravity IDE" | Out-Null
        $SetupKPIs.ScheduledTaskCreated = $true
        Write-Log "Registered elevated scheduled task: $taskName (RunLevel=Highest)." "INFO"
    }

    Write-Log "[Step 3/4] Compiling native Windows GUI executable launcher..." "INFO"
    $outExe = Join-Path $launcherDir "AntigravitySilentAdmin.exe"
    $srcFile = Join-Path $launcherDir "Program.cs"
    
    $source = @"
using System;
using System.Diagnostics;

namespace AntigravityLauncher {
    class Program {
        static void Main(string[] args) {
            try {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "schtasks.exe";
                psi.Arguments = "/run /tn \"$taskName\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WindowStyle = ProcessWindowStyle.Hidden;
                Process.Start(psi);
            } catch {}
        }
    }
}
"@

    if (-not $DryRun) {
        Set-Content -Path $srcFile -Value $source -Encoding UTF8
        $csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
        & $csc /target:winexe /out:$outExe $srcFile | Out-Null
        $SetupKPIs.CompiledLauncherPath = $outExe
        Write-Log "Compiled native GUI launcher: $outExe" "INFO"
    }

    Write-Log "[Step 4/4] Creating Windows Shortcuts with official Antigravity icon..." "INFO"
    if (-not $DryRun) {
        $desktopPath = [Environment]::GetFolderPath("Desktop")
        $programsPath = [Environment]::GetFolderPath("Programs")
        $scDesktop  = "$desktopPath\Antigravity (Admin Silencioso).lnk"
        $scPrograms = "$programsPath\Antigravity (Admin Silencioso).lnk"

        $wsh = New-Object -ComObject WScript.Shell
        foreach ($scPath in @($scDesktop, $scPrograms)) {
            $sc = $wsh.CreateShortcut($scPath)
            $sc.TargetPath = $outExe
            $sc.WorkingDirectory = $launcherDir
            $sc.IconLocation = "$antiExe,0"
            $sc.Description = "Ejecutar Google Antigravity con privilegios de Administrador sin advertencias de UAC"
            $sc.Save()
            Write-Log "Created Shortcut: $scPath" "INFO"
        }

        $SetupKPIs.DesktopShortcutPath = $scDesktop
        $SetupKPIs.StartMenuShortcutPath = $scPrograms
    }

    $SetupKPIs.Status = "SUCCESS"
}
catch {
    $SetupKPIs.Status = "FAILED"
    $SetupKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during Silent Admin setup: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $SetupKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $SetupKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $SetupKPIs | ConvertTo-Json -Depth 4 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdLines = @(
        "# Antigravity Native Silent Administrator Elevation Report",
        "",
        "- Task Name: $($SetupKPIs.TaskName)",
        "- Status: $($SetupKPIs.Status)",
        "- Elevated Task Created: $($SetupKPIs.ScheduledTaskCreated)",
        "- Native Compiled Launcher: $($SetupKPIs.CompiledLauncherPath)",
        "- Desktop Shortcut: $($SetupKPIs.DesktopShortcutPath)",
        "- Start Menu Shortcut: $($SetupKPIs.StartMenuShortcutPath)",
        "- Execution Timestamp: $($SetupKPIs.StartTime) to $($SetupKPIs.EndTime)",
        "- Duration: $($SetupKPIs.DurationSeconds) s",
        "",
        "## Fixed Architecture",
        "- Replaced script-based wrapper with a compiled native Windows GUI launcher (`AntigravitySilentAdmin.exe`).",
        "- The shortcut target points directly to `AntigravitySilentAdmin.exe` with Antigravity's official icon.",
        "- Zero Explorer windows, zero console flicker, zero UAC confirmation prompts.",
        "",
        "## How to Pin to Taskbar",
        "1. Right-click on `f:\\windows\\launchers\\AntigravitySilentAdmin.exe` or on the Desktop shortcut **Antigravity (Admin Silencioso)**.",
        "2. Select **'Pin to taskbar'** (Anclar a la barra de tareas).",
        "",
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8
    Write-Log "Silent Admin Antigravity setup complete. Report generated at: $ReportMd" "INFO"
}
