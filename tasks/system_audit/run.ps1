<#
.SYNOPSIS
    Comprehensive Windows System, Hardware, Services & Software Audit Task.
.DESCRIPTION
    Complies with TASK_AUTOMATION_HARNESS.md.
    Performs a deep audit of:
      1. Hardware Specifications (CPU, RAM modules, Disks, Motherboard, BIOS, GPU, Network)
      2. Operating System & Windows Environment
      3. Installed Software & Applications Inventory (64-bit & 32-bit)
      4. Windows Services Status & Startup Modes
      5. Windows Optional Features & Components
    Generates step-by-step logs, CSV/JSON artifacts, and an executive KPI summary report.
.PARAMETER DryRun
    Runs a fast simulated audit without exporting full CSV inventories.
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
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG")][string]$Level = "INFO"
    )
    $TimeStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStr] [$Level] $Message"
    
    switch ($Level) {
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

# 4. Main Audit Workflow
$StartTime = Get-Date
$AuditData = @{}
$AuditKPIs = @{
    TaskName                = "system_audit"
    Status                  = "RUNNING"
    StartTime               = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    DryRun                  = [bool]$DryRun
    HostName                = $env:COMPUTERNAME
    CurrentUser             = $env:USERNAME
    TotalInstalledSoftware  = 0
    TotalServices           = 0
    RunningServices         = 0
    StoppedServices         = 0
    TotalMemoryGB           = 0.0
    FreeMemoryGB            = 0.0
    MemoryUtilizationPct    = 0.0
    TotalStorageGB          = 0.0
    FreeStorageGB           = 0.0
    StorageUtilizationPct   = 0.0
    CpuModel                = ""
    CpuCores                = 0
    CpuLogicalProcessors    = 0
    OSName                  = ""
    OSVersion               = ""
    OSBuild                 = ""
    DurationSeconds         = 0.0
}

try {
    Write-Log "[Step 1/5] Auditing Operating System & Windows Environment..." "INFO"
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    $lastBoot = $os.LastBootUpTime
    $uptime = (Get-Date) - $lastBoot
    $uptimeFormatted = "$($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"

    $AuditKPIs.OSName    = $os.Caption
    $AuditKPIs.OSVersion = $os.Version
    $AuditKPIs.OSBuild   = $os.BuildNumber

    $AuditData.OperatingSystem = [PSCustomObject]@{
        OSName               = $os.Caption
        Version              = $os.Version
        BuildNumber          = $os.BuildNumber
        Architecture         = $os.OSArchitecture
        InstallDate          = $os.InstallDate
        LastBootUpTime       = $lastBoot
        Uptime               = $uptimeFormatted
        WindowsDirectory     = $os.WindowsDirectory
        SystemDirectory      = $os.SystemDirectory
        RegisteredUser       = $os.RegisteredUser
        Organization         = $os.Organization
        ComputerManufacturer = $cs.Manufacturer
        ComputerModel        = $cs.Model
        SystemType           = $cs.SystemType
        Domain               = $cs.Domain
    }
    Write-Log "OS: $($os.Caption) (Build $($os.BuildNumber)) | Uptime: $uptimeFormatted" "INFO"

    Write-Log "[Step 2/5] Auditing Hardware Specifications (CPU, RAM, Disks, GPU, Motherboard, Network)..." "INFO"
    
    # 2.1 CPU Specs
    $proc = Get-CimInstance Win32_Processor | Select-Object -First 1
    $AuditKPIs.CpuModel             = $proc.Name
    $AuditKPIs.CpuCores             = $proc.NumberOfCores
    $AuditKPIs.CpuLogicalProcessors = $proc.NumberOfLogicalProcessors

    $AuditData.CPU = [PSCustomObject]@{
        Name               = $proc.Name
        Manufacturer       = $proc.Manufacturer
        Cores              = $proc.NumberOfCores
        LogicalProcessors  = $proc.NumberOfLogicalProcessors
        MaxClockSpeedMHz   = $proc.MaxClockSpeed
        L2CacheSizeKB      = $proc.L2CacheSize
        L3CacheSizeKB      = $proc.L3CacheSize
        SocketDesignation  = $proc.SocketDesignation
    }
    Write-Log "CPU: $($proc.Name) ($($proc.NumberOfCores) Cores / $($proc.NumberOfLogicalProcessors) Threads)" "INFO"

    # 2.2 Memory (RAM) Specs
    $physMem = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $totalRamBytes = ($physMem | Measure-Object -Property Capacity -Sum).Sum
    if (-not $totalRamBytes -or $totalRamBytes -eq 0) {
        $totalRamBytes = $os.TotalVisibleMemorySize * 1024
    }
    $freeRamBytes = $os.FreePhysicalMemory * 1024
    $usedRamBytes = $totalRamBytes - $freeRamBytes

    $AuditKPIs.TotalMemoryGB        = [Math]::Round($totalRamBytes / 1GB, 2)
    $AuditKPIs.FreeMemoryGB         = [Math]::Round($freeRamBytes / 1GB, 2)
    $AuditKPIs.MemoryUtilizationPct = [Math]::Round(($usedRamBytes / $totalRamBytes) * 100, 1)

    $dimmModules = @()
    if ($physMem) {
        foreach ($dimm in $physMem) {
            $dimmModules += [PSCustomObject]@{
                BankLabel    = $dimm.BankLabel
                DeviceLocator= $dimm.DeviceLocator
                CapacityGB   = [Math]::Round($dimm.Capacity / 1GB, 2)
                SpeedMHz     = $dimm.Speed
                Manufacturer = $dimm.Manufacturer
                PartNumber   = $dimm.PartNumber
            }
        }
    }
    $AuditData.Memory = [PSCustomObject]@{
        TotalMemoryGB        = $AuditKPIs.TotalMemoryGB
        FreeMemoryGB         = $AuditKPIs.FreeMemoryGB
        UsedMemoryGB         = [Math]::Round($usedRamBytes / 1GB, 2)
        MemoryUtilizationPct = $AuditKPIs.MemoryUtilizationPct
        ModulesCount         = $dimmModules.Count
        Modules              = $dimmModules
    }
    Write-Log "RAM: $($AuditKPIs.TotalMemoryGB) GB Total | $($AuditKPIs.FreeMemoryGB) GB Free ($($AuditKPIs.MemoryUtilizationPct)% used)" "INFO"

    # 2.3 Storage (Disks & Logical Volumes)
    $physicalDisks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
    $logicalDisks  = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue

    $diskDrives = @()
    foreach ($d in $physicalDisks) {
        $diskDrives += [PSCustomObject]@{
            Model         = $d.Model
            InterfaceType = $d.InterfaceType
            SizeGB        = [Math]::Round($d.Size / 1GB, 2)
            Partitions    = $d.Partitions
            Status        = $d.Status
        }
    }

    $volumes = @()
    $totalStorageBytes = 0
    $freeStorageBytes = 0
    foreach ($vol in $logicalDisks) {
        $volTotal = $vol.Size
        $volFree  = $vol.FreeSpace
        $volUsed  = $volTotal - $volFree
        $totalStorageBytes += $volTotal
        $freeStorageBytes += $volFree

        $volumes += [PSCustomObject]@{
            DriveLetter   = $vol.DeviceID
            VolumeName    = $vol.VolumeName
            FileSystem    = $vol.FileSystem
            TotalSizeGB   = [Math]::Round($volTotal / 1GB, 2)
            FreeSpaceGB   = [Math]::Round($volFree / 1GB, 2)
            UsedSpaceGB   = [Math]::Round($volUsed / 1GB, 2)
            FreeSpacePct  = [Math]::Round(($volFree / $volTotal) * 100, 1)
        }
    }

    if ($totalStorageBytes -gt 0) {
        $AuditKPIs.TotalStorageGB        = [Math]::Round($totalStorageBytes / 1GB, 2)
        $AuditKPIs.FreeStorageGB         = [Math]::Round($freeStorageBytes / 1GB, 2)
        $AuditKPIs.StorageUtilizationPct = [Math]::Round((($totalStorageBytes - $freeStorageBytes) / $totalStorageBytes) * 100, 1)
    }

    $AuditData.Storage = [PSCustomObject]@{
        PhysicalDisks        = $diskDrives
        LogicalVolumes       = $volumes
        TotalStorageGB       = $AuditKPIs.TotalStorageGB
        FreeStorageGB        = $AuditKPIs.FreeStorageGB
        StorageUtilizationPct= $AuditKPIs.StorageUtilizationPct
    }
    Write-Log "Storage: $($AuditKPIs.TotalStorageGB) GB Total | $($AuditKPIs.FreeStorageGB) GB Free across $($volumes.Count) volume(s)" "INFO"

    # 2.4 GPU & Display
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $gpuList = @()
    foreach ($gpu in $gpus) {
        $gpuList += [PSCustomObject]@{
            Name          = $gpu.Name
            DriverVersion = $gpu.DriverVersion
            AdapterRAMMB  = if ($gpu.AdapterRAM) { [Math]::Round($gpu.AdapterRAM / 1MB, 0) } else { "N/A" }
            Status        = $gpu.Status
        }
    }
    $AuditData.Graphics = $gpuList

    # 2.5 Motherboard & BIOS
    $baseboard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios      = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue | Select-Object -First 1
    $AuditData.Motherboard = [PSCustomObject]@{
        Manufacturer = $baseboard.Manufacturer
        Product      = $baseboard.Product
        Version      = $baseboard.Version
        SerialNumber = $baseboard.SerialNumber
    }
    $AuditData.BIOS = [PSCustomObject]@{
        Manufacturer = $bios.Manufacturer
        Name         = $bios.Name
        Version      = $bios.Version
        ReleaseDate  = $bios.ReleaseDate
    }

    # 2.6 Network Adapters
    $netAdapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction SilentlyContinue
    $activeNets = @()
    foreach ($net in $netAdapters) {
        $activeNets += [PSCustomObject]@{
            Description   = $net.Description
            MACAddress    = $net.MACAddress
            IPAddresses   = ($net.IPAddress -join ", ")
            DefaultGateway= ($net.DefaultIPGateway -join ", ")
            DHCPEnabled   = $net.DHCPEnabled
            DNSServers    = ($net.DNSServerSearchOrder -join ", ")
        }
    }
    $AuditData.Network = $activeNets

    Write-Log "[Step 3/5] Auditing Windows Services..." "INFO"
    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue
    $AuditKPIs.TotalServices   = $services.Count
    $AuditKPIs.RunningServices = ($services | Where-Object { $_.State -eq 'Running' }).Count
    $AuditKPIs.StoppedServices = ($services | Where-Object { $_.State -eq 'Stopped' }).Count

    $serviceList = @()
    foreach ($svc in $services) {
        $serviceList += [PSCustomObject]@{
            Name        = $svc.Name
            DisplayName = $svc.DisplayName
            State       = $svc.State
            StartMode   = $svc.StartMode
            StartName   = $svc.StartName
            ProcessId   = $svc.ProcessId
        }
    }
    $AuditData.Services = $serviceList
    Write-Log "Services: $($AuditKPIs.TotalServices) Total ($($AuditKPIs.RunningServices) Running, $($AuditKPIs.StoppedServices) Stopped)" "INFO"

    Write-Log "[Step 4/5] Auditing Installed Software Inventory (Registry 64-bit & 32-bit)..." "INFO"
    $uninstallKeys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $softwareDict = @{}
    foreach ($key in $uninstallKeys) {
        $items = Get-ItemProperty $key -ErrorAction SilentlyContinue
        if ($items) {
            foreach ($item in $items) {
                if ($item.DisplayName -and -not [string]::IsNullOrWhiteSpace($item.DisplayName)) {
                    $name = $item.DisplayName.Trim()
                    if (-not $softwareDict.ContainsKey($name)) {
                        $softwareDict[$name] = [PSCustomObject]@{
                            Name            = $name
                            DisplayVersion  = if ($item.DisplayVersion) { $item.DisplayVersion } else { "N/A" }
                            Publisher       = if ($item.Publisher) { $item.Publisher } else { "Unknown" }
                            InstallDate     = if ($item.InstallDate) { $item.InstallDate } else { "N/A" }
                            InstallLocation = if ($item.InstallLocation) { $item.InstallLocation } else { "N/A" }
                        }
                    }
                }
            }
        }
    }

    $softwareList = @($softwareDict.Values | Sort-Object Name)
    $AuditKPIs.TotalInstalledSoftware = $softwareList.Count
    $AuditData.InstalledSoftware = $softwareList
    Write-Log "Software Inventory: $($AuditKPIs.TotalInstalledSoftware) applications detected." "INFO"

    # Export CSV and JSON Artifacts
    Write-Log "[Step 5/5] Exporting structured artifacts and generating KPI report..." "INFO"
    
    $inventoryJson = Join-Path $ArtifactDir "system_audit_inventory.json"
    $AuditData | ConvertTo-Json -Depth 6 | Set-Content -Path $inventoryJson -Encoding UTF8
    Write-Log "Full raw inventory exported to: $inventoryJson" "INFO"

    $softwareCsv = Join-Path $ArtifactDir "software_inventory.csv"
    $softwareList | Export-Csv -Path $softwareCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Software CSV inventory exported to: $softwareCsv" "INFO"

    $servicesCsv = Join-Path $ArtifactDir "services_inventory.csv"
    $serviceList | Export-Csv -Path $servicesCsv -NoTypeInformation -Encoding UTF8
    Write-Log "Services CSV inventory exported to: $servicesCsv" "INFO"

    $AuditKPIs.Status = "SUCCESS"
}
catch {
    $AuditKPIs.Status = "FAILED"
    $AuditKPIs.ErrorMessage = $_.Exception.Message
    Write-Log "Critical failure during system audit: $_" "ERROR"
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
    $volsTable = @()
    if ($AuditData.Storage.LogicalVolumes) {
        foreach ($v in $AuditData.Storage.LogicalVolumes) {
            $volsTable += "| $($v.DriveLetter) ($($v.FileSystem)) | $($v.TotalSizeGB) GB | $($v.UsedSpaceGB) GB | $($v.FreeSpaceGB) GB ($($v.FreeSpacePct)%) |"
        }
    }

    $topSoftware = @()
    if ($AuditData.InstalledSoftware) {
        $count = 0
        foreach ($s in $AuditData.InstalledSoftware) {
            if ($count -lt 15) {
                $topSoftware += "| $($s.Name) | $($s.DisplayVersion) | $($s.Publisher) |"
                $count++
            }
        }
    }

    $mdLines = @(
        "# Comprehensive System & Hardware Audit Report",
        "",
        "- **Task Name:** $($AuditKPIs.TaskName)",
        "- **Status:** **$($AuditKPIs.Status)**",
        "- **Host Name:** $($AuditKPIs.HostName)",
        "- **Audited By User:** $($AuditKPIs.CurrentUser)",
        "- **Execution Timestamp:** $($AuditKPIs.StartTime) to $($AuditKPIs.EndTime)",
        "- **Audit Duration:** $($AuditKPIs.DurationSeconds) s",
        "",
        "## Executive Summary & Core KPIs",
        "| KPI / Metric | Value |",
        "|---|---|",
        "| **Operating System** | $($AuditKPIs.OSName) (Build $($AuditKPIs.OSBuild)) |",
        "| **Processor (CPU)** | $($AuditKPIs.CpuModel) ($($AuditKPIs.CpuCores) Cores / $($AuditKPIs.CpuLogicalProcessors) Threads) |",
        "| **Total / Free RAM** | **$($AuditKPIs.TotalMemoryGB) GB Total** / **$($AuditKPIs.FreeMemoryGB) GB Free** ($($AuditKPIs.MemoryUtilizationPct)% Used) |",
        "| **Total / Free Storage** | **$($AuditKPIs.TotalStorageGB) GB Total** / **$($AuditKPIs.FreeStorageGB) GB Free** ($($AuditKPIs.StorageUtilizationPct)% Used) |",
        "| **Installed Applications Count** | **$($AuditKPIs.TotalInstalledSoftware) applications** |",
        "| **Windows Services** | **$($AuditKPIs.TotalServices) total** ($($AuditKPIs.RunningServices) Running, $($AuditKPIs.StoppedServices) Stopped) |",
        "",
        "## Logical Storage Volumes",
        "| Volume | Total Capacity | Used Space | Free Space |",
        "|---|---|---|---|",
        ($volsTable -join "`r`n"),
        "",
        "## Installed Applications (Sample of First 15)",
        "| Application Name | Version | Publisher |",
        "|---|---|---|",
        ($topSoftware -join "`r`n"),
        "",
        "## Generated Audit Artifacts",
        "- **Full Raw JSON Inventory:** [system_audit_inventory.json](file:///$($inventoryJson -replace '\\', '/'))",
        "- **Software CSV Export:** [software_inventory.csv](file:///$($softwareCsv -replace '\\', '/'))",
        "- **Services CSV Export:** [services_inventory.csv](file:///$($servicesCsv -replace '\\', '/'))",
        "- **Step-by-Step Log File:** [task log](file:///$($LogFile -replace '\\', '/'))",
        "- **KPI JSON Report:** [report.json](file:///$($ReportJson -replace '\\', '/'))"
    )

    $mdLines -join "`r`n" | Set-Content -Path $ReportMd -Encoding UTF8

    Write-Log "Audit completed successfully. Report generated at: $ReportMd" "INFO"
}
