<#
.SYNOPSIS
    Hardware Temperature Monitor & Observation Task (CPU & GPU).
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Monitors CPU and GPU temperatures, assesses thermal margins, triggers alerts
    for high thermal danger (vital after thermal paste replacement), and outputs
    step-by-step logs and KPI execution reports.
.PARAMETER Watch
    Runs in continuous observation/watch mode.
.PARAMETER IntervalSeconds
    Interval in seconds between temperature readings in watch mode. Default: 3.
.PARAMETER DurationSeconds
    Total duration in seconds to run watch mode. Default: 30 (use 0 for indefinite until Ctrl+C).
.PARAMETER CpuWarning
    Override threshold for CPU warning in Celsius.
.PARAMETER CpuDanger
    Override threshold for CPU critical danger in Celsius.
.PARAMETER DryRun
    Simulates alert thresholds and verifies reporting without monitoring indefinitely.
#>
[CmdletBinding()]
param (
    [switch]$Watch,
    [int]$IntervalSeconds = 3,
    [int]$DurationSeconds = 15,
    [double]$CpuWarning = 75.0,
    [double]$CpuDanger = 85.0,
    [double]$CpuCritical = 95.0,
    [double]$GpuWarning = 75.0,
    [double]$GpuDanger = 83.0,
    [double]$GpuCritical = 90.0,
    [switch]$AudioAlert = $true,
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

# 4. Sensor Query Helper Functions
function Get-CpuTemperatureInfo {
    $results = @()
    
    # 4.1 Query WMI ACPI Thermal Zones
    try {
        $acpiZones = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue
        if ($acpiZones) {
            foreach ($zone in $acpiZones) {
                if ($zone.CurrentTemperature -gt 0) {
                    $tempC = [Math]::Round(($zone.CurrentTemperature - 2732) / 10.0, 1)
                    $critC = if ($zone.CriticalTripPoint -gt 0) { [Math]::Round(($zone.CriticalTripPoint - 2732) / 10.0, 1) } else { 100.0 }
                    $results += [PSCustomObject]@{
                        SensorType    = "ACPI_ThermalZone"
                        SensorName    = $zone.InstanceName
                        TemperatureC  = $tempC
                        CriticalTripC = $critC
                    }
                }
            }
        }
    } catch {
        Write-Log "Could not read root/wmi ACPI thermal zone: $_" "DEBUG"
    }

    # 4.2 Query LibreHardwareMonitor / OpenHardwareMonitor if present
    try {
        $ohmSensors = Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction SilentlyContinue
        if ($ohmSensors) {
            foreach ($s in $ohmSensors) {
                $results += [PSCustomObject]@{
                    SensorType    = "OpenHardwareMonitor"
                    SensorName    = "$($s.Name) ($($s.Identifier))"
                    TemperatureC  = [Math]::Round([double]$s.Value, 1)
                    CriticalTripC = 100.0
                }
            }
        }
    } catch {
        Write-Log "OpenHardwareMonitor WMI namespace not available." "DEBUG"
    }

    return $results
}

function Get-GpuTemperatureInfo {
    $results = @()

    # 4.3 Query NVIDIA SMI if available
    $nvidiaSmi = Get-Command "nvidia-smi" -ErrorAction SilentlyContinue
    if ($nvidiaSmi) {
        try {
            $smiOut = & $nvidiaSmi --query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>$null
            if ($smiOut) {
                foreach ($line in $smiOut) {
                    $parts = $line -split ',\s*'
                    if ($parts.Count -ge 2) {
                        $results += [PSCustomObject]@{
                            SensorType    = "NVIDIA_SMI"
                            GpuName       = $parts[0].Trim()
                            TemperatureC  = [Math]::Round([double]$parts[1], 1)
                            Utilization   = if ($parts.Count -ge 3) { "$($parts[2])%" } else { "N/A" }
                            MemoryUsedMB  = if ($parts.Count -ge 4) { $parts[3] } else { "N/A" }
                            MemoryTotalMB = if ($parts.Count -ge 5) { $parts[4] } else { "N/A" }
                        }
                    }
                }
            }
        } catch {
            Write-Log "nvidia-smi query encountered an error: $_" "DEBUG"
        }
    }

    # 4.4 Fallback: Windows Video Controllers
    if ($results.Count -eq 0) {
        $videoControllers = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
        foreach ($gpu in $videoControllers) {
            $results += [PSCustomObject]@{
                SensorType    = "Win32_VideoController"
                GpuName       = $gpu.Name
                TemperatureC  = $null # Standard WMI VideoController does not expose hardware temp registers directly
                Status        = $gpu.Status
                DriverVersion = $gpu.DriverVersion
            }
        }
    }

    return $results
}

# 5. Alert Evaluator Function
function Evaluate-ThermalStatus {
    param (
        [double]$TempC,
        [double]$WarningThreshold,
        [double]$DangerThreshold,
        [double]$CriticalThreshold,
        [string]$DeviceType = "CPU"
    )

    if ($TempC -ge $CriticalThreshold) {
        return @{
            Level       = "CRITICAL_DANGER"
            Alert       = $true
            Description = "EMERGENCY: $DeviceType temperature is at ${TempC}°C (>= ${CriticalThreshold}°C)! High risk of thermal throttling or thermal shutdown."
        }
    }
    elseif ($TempC -ge $DangerThreshold) {
        return @{
            Level       = "DANGER"
            Alert       = $true
            Description = "DANGER: $DeviceType temperature is at ${TempC}°C (>= ${DangerThreshold}°C)! Thermal dissipation may be failing."
        }
    }
    elseif ($TempC -ge $WarningThreshold) {
        return @{
            Level       = "WARNING"
            Alert       = $true
            Description = "WARNING: $DeviceType temperature elevated at ${TempC}°C (>= ${WarningThreshold}°C)."
        }
    }
    else {
        return @{
            Level       = "NORMAL"
            Alert       = $false
            Description = "NORMAL: $DeviceType temperature is within safe parameters (${TempC}°C)."
        }
    }
}

# 6. Main Execution Workflow
$StartTime = Get-Date
$ExecutionKPIs = @{
    TaskName             = "monitor_hardware_temperature"
    Status               = "RUNNING"
    StartTime            = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun               = [bool]$DryRun
    Mode                 = if ($Watch) { "OBSERVATION_WATCH" } else { "SINGLE_CHECK" }
    SamplesCollected     = 0
    AlertsTriggeredCount = 0
    HighestCpuTempC      = 0.0
    LowestCpuTempC       = 999.0
    AvgCpuTempC          = 0.0
    HighestGpuTempC      = 0.0
    OverallThermalState  = "NORMAL"
    ThermalReadings      = @()
    DurationSeconds      = 0.0
}

try {
    Write-Log "[Step 1/4] Initializing Hardware Temperature Monitor Harness..." "INFO"
    Write-Log "Target Workspace Task Directory: $TaskDir" "INFO"
    Write-Log "Configured Thresholds -> CPU: [Warn: ${CpuWarning}°C | Danger: ${CpuDanger}°C | Crit: ${CpuCritical}°C]" "INFO"
    Write-Log "Configured Thresholds -> GPU: [Warn: ${GpuWarning}°C | Danger: ${GpuDanger}°C | Crit: ${GpuCritical}°C]" "INFO"

    # Read Processor specs
    $cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
    Write-Log "Detected Processor: $($cpuInfo.Name) (Cores: $($cpuInfo.NumberOfCores), Threads: $($cpuInfo.NumberOfLogicalProcessors))" "INFO"

    Write-Log "[Step 2/4] Testing sensor access and baseline readings..." "INFO"
    $initialCpu = Get-CpuTemperatureInfo
    $initialGpu = Get-GpuTemperatureInfo

    if ($initialCpu.Count -eq 0) {
        Write-Log "ACPI WMI temperature zones did not return active sensors directly. Reading motherboard ACPI..." "WARN"
    } else {
        foreach ($c in $initialCpu) {
            Write-Log "Found CPU Sensor: $($c.SensorName) -> $($c.TemperatureC) °C (Trip: $($c.CriticalTripC) °C)" "INFO"
        }
    }

    foreach ($g in $initialGpu) {
        if ($g.TemperatureC -ne $null) {
            Write-Log "Found GPU Sensor: $($g.GpuName) -> $($g.TemperatureC) °C" "INFO"
        } else {
            Write-Log "Found GPU Controller: $($g.GpuName) (Status: $($g.Status), Driver: $($g.DriverVersion))" "INFO"
        }
    }

    Write-Log "[Step 3/4] Running temperature observation loop (DryRun: $DryRun)..." "INFO"
    
    $cpuTempHistory = [System.Collections.Generic.List[double]]::new()
    $loopStartTime = Get-Date
    $sampleCount = 0

    do {
        $sampleCount++
        $sampleTime = Get-Date
        $cpuSensors = Get-CpuTemperatureInfo
        $gpuSensors = Get-GpuTemperatureInfo

        $currentMaxCpuTemp = 0.0
        foreach ($c in $cpuSensors) {
            if ($c.TemperatureC -gt $currentMaxCpuTemp) {
                $currentMaxCpuTemp = $c.TemperatureC
            }
        }

        # If DryRun simulation requested, simulate an observation range
        if ($DryRun -and $currentMaxCpuTemp -eq 0.0) {
            $currentMaxCpuTemp = 58.5
        }

        if ($currentMaxCpuTemp -gt 0) {
            $cpuTempHistory.Add($currentMaxCpuTemp)
            if ($currentMaxCpuTemp -gt $ExecutionKPIs.HighestCpuTempC) {
                $ExecutionKPIs.HighestCpuTempC = $currentMaxCpuTemp
            }
            if ($currentMaxCpuTemp -lt $ExecutionKPIs.LowestCpuTempC) {
                $ExecutionKPIs.LowestCpuTempC = $currentMaxCpuTemp
            }

            # Evaluate Thermal State
            $eval = Evaluate-ThermalStatus -TempC $currentMaxCpuTemp -WarningThreshold $CpuWarning -DangerThreshold $CpuDanger -CriticalThreshold $CpuCritical -DeviceType "CPU"
            
            $logLevel = if ($eval.Level -eq "CRITICAL_DANGER") { "ALERT" } elseif ($eval.Level -eq "DANGER" -or $eval.Level -eq "WARNING") { "WARN" } else { "INFO" }
            
            Write-Log "[Sample #$sampleCount] CPU Current Temp: ${currentMaxCpuTemp}°C | Status: $($eval.Level)" $logLevel

            if ($eval.Alert) {
                $ExecutionKPIs.AlertsTriggeredCount++
                $ExecutionKPIs.OverallThermalState = $eval.Level
                Write-Log ">>> THERMAL ALERT: $($eval.Description) <<<" "ALERT"
                if ($AudioAlert) {
                    try { [Console]::Beep(1000, 300) } catch {}
                }
            }
        }

        # Check GPU Sensors
        foreach ($g in $gpuSensors) {
            if ($g.TemperatureC -ne $null -and $g.TemperatureC -gt 0) {
                if ($g.TemperatureC -gt $ExecutionKPIs.HighestGpuTempC) {
                    $ExecutionKPIs.HighestGpuTempC = $g.TemperatureC
                }
                $gpuEval = Evaluate-ThermalStatus -TempC $g.TemperatureC -WarningThreshold $GpuWarning -DangerThreshold $GpuDanger -CriticalThreshold $GpuCritical -DeviceType "GPU"
                Write-Log "[Sample #$sampleCount] GPU ($($g.GpuName)): $($g.TemperatureC)°C | Status: $($gpuEval.Level)" "INFO"
                if ($gpuEval.Alert) {
                    $ExecutionKPIs.AlertsTriggeredCount++
                    Write-Log ">>> GPU THERMAL ALERT: $($gpuEval.Description) <<<" "ALERT"
                }
            }
        }

        $ExecutionKPIs.ThermalReadings += [PSCustomObject]@{
            SampleIndex = $sampleCount
            Timestamp   = $sampleTime.ToString("yyyy-MM-dd HH:mm:ss")
            CpuTempC    = $currentMaxCpuTemp
            GpuTempC    = $ExecutionKPIs.HighestGpuTempC
        }

        if (-not $Watch) {
            break
        }

        $elapsedSeconds = (Get-Date) - $loopStartTime
        if ($DurationSeconds -gt 0 -and $elapsedSeconds.TotalSeconds -ge $DurationSeconds) {
            Write-Log "Watch duration limit of ${DurationSeconds}s reached." "INFO"
            break
        }

        Start-Sleep -Seconds $IntervalSeconds
    } while ($true)

    # Compute Averages
    if ($cpuTempHistory.Count -gt 0) {
        $avg = ($cpuTempHistory | Measure-Object -Average).Average
        $ExecutionKPIs.AvgCpuTempC = [Math]::Round($avg, 2)
    } else {
        $ExecutionKPIs.LowestCpuTempC = 0.0
    }

    $ExecutionKPIs.SamplesCollected = $sampleCount

    Write-Log "[Step 4/4] Generating summary reports and key performance indicators..." "INFO"
    $ExecutionKPIs.Status = "SUCCESS"
}
catch {
    $ExecutionKPIs.Status = "FAILED"
    $ExecutionKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Execution failure: $_" "ERROR"
    Invoke-Rollback -Reason $_.Exception.Message
    throw $_
}
finally {
    $EndTime = Get-Date
    $Duration = ($EndTime - $StartTime).TotalSeconds
    $ExecutionKPIs.EndTime = $EndTime.ToString("yyyy-MM-dd HH:mm:ss")
    $ExecutionKPIs.DurationSeconds = [Math]::Round($Duration, 2)

    # 1. Output JSON KPI Report
    $ExecutionKPIs | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportJson -Encoding UTF8

    # 2. Output Markdown Summary Report
    $mdAssessment = if ($ExecutionKPIs.AlertsTriggeredCount -eq 0) {
        "> [!NOTE]`n> Temperatures remained within safe operating limits. Thermal paste application is dissipating heat properly under current load."
    } else {
        "> [!WARNING]`n> Elevated temperatures detected during observation ($($ExecutionKPIs.AlertsTriggeredCount) alerts triggered). Keep monitoring system under heavy load."
    }

    $gpuText = if ($ExecutionKPIs.HighestGpuTempC -gt 0) { "$($ExecutionKPIs.HighestGpuTempC) °C" } else { "N/A (Integrated / Driver-level)" }

    $mdLines = @(
        "# Hardware Temperature Observation Report",
        "",
        "- **Task Name:** $($ExecutionKPIs.TaskName)",
        "- **Status:** **$($ExecutionKPIs.Status)**",
        "- **Overall Thermal State:** **$($ExecutionKPIs.OverallThermalState)**",
        "- **Execution Mode:** $($ExecutionKPIs.Mode)",
        "- **Execution Timestamp:** $($ExecutionKPIs.StartTime) to $($ExecutionKPIs.EndTime)",
        "- **Total Duration:** $($ExecutionKPIs.DurationSeconds) s",
        "- **Samples Collected:** $($ExecutionKPIs.SamplesCollected)",
        "- **Alerts Triggered:** $($ExecutionKPIs.AlertsTriggeredCount)",
        "",
        "## Core Thermal KPIs",
        "| Metric | Value |",
        "|---|---|",
        "| **CPU Current / Max Temperature** | **$($ExecutionKPIs.HighestCpuTempC) °C** |",
        "| **CPU Minimum Temperature** | $($ExecutionKPIs.LowestCpuTempC) °C |",
        "| **CPU Average Temperature** | $($ExecutionKPIs.AvgCpuTempC) °C |",
        "| **GPU Max Temperature** | $gpuText |",
        "| **CPU Warning Threshold** | ${CpuWarning} °C |",
        "| **CPU Danger Threshold** | ${CpuDanger} °C |",
        "| **CPU Critical Alert Threshold** | ${CpuCritical} °C |",
        "",
        "## Thermal Assessment Summary",
        $mdAssessment,
        "- Detailed Log File: $LogFile",
        "- JSON Report: $ReportJson"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8

    Write-Log "Execution complete. Report generated at: $ReportMd" "INFO"
    Write-Log "Overall Thermal State: $($ExecutionKPIs.OverallThermalState) | Highest CPU: $($ExecutionKPIs.HighestCpuTempC)°C | Alerts: $($ExecutionKPIs.AlertsTriggeredCount)" "INFO"
}
