<#
.SYNOPSIS
    Automated Daily Performance, Cache & Temporary Files Purge Worker.
.DESCRIPTION
    1. Cleans Windows User & System Temp files.
    2. Cleans Thorium Browser shader, code, and GPU cache without wiping user logins/history.
    3. Cleans Antigravity cache and temp media storage.
    4. Flushes process memory working sets.
    5. Records execution timestamp and freed bytes in f:\windows\logs\daily_purge_history.log.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$LogDir = "f:\windows\logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "daily_purge_history.log"

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$BytesCleaned = 0
$FilesCleaned = 0

function Remove-StaleFiles {
    param ([string]$Path, [int]$DaysOld = 0)
    if (-not (Test-Path $Path)) { return }
    $items = Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        try {
            $len = $item.Length
            Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $item.FullName)) {
                $script:BytesCleaned += $len
                $script:FilesCleaned++
            }
        } catch {}
    }
}

# 1. Windows Temp directories
Remove-StaleFiles "$env:TEMP\*"
Remove-StaleFiles "C:\Windows\Temp\*"
Remove-StaleFiles "C:\Windows\Minidump\*"

# 2. Thorium Browser Cache
$thoriumCachePaths = @(
    "$env:LOCALAPPDATA\Thorium\User Data\Default\Cache\Cache_Data",
    "$env:LOCALAPPDATA\Thorium\User Data\Default\Code Cache",
    "$env:LOCALAPPDATA\Thorium\User Data\Default\GPUCache",
    "$env:LOCALAPPDATA\Thorium\User Data\Default\DawnGraphiteCache",
    "$env:LOCALAPPDATA\Thorium\User Data\Default\DawnWebGPUCache",
    "$env:LOCALAPPDATA\Thorium\User Data\ShaderCache"
)
foreach ($cp in $thoriumCachePaths) {
    Remove-StaleFiles $cp
}

# 3. Antigravity IDE Cache & Temp Storage
$antigravityCachePaths = @(
    "$env:APPDATA\Antigravity\Cache",
    "$env:APPDATA\Antigravity\Code Cache",
    "$env:APPDATA\Antigravity\GPUCache",
    "$env:USERPROFILE\.gemini\antigravity\crashes",
    "$env:USERPROFILE\.gemini\antigravity\tempmediaStorage"
)
foreach ($acp in $antigravityCachePaths) {
    Remove-StaleFiles $acp
}

# 4. Memory Flush
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DailyMemoryCleaner {
    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);
    public static void CleanMemory() {
        foreach (var p in System.Diagnostics.Process.GetProcesses()) {
            try { if (p.Id > 4) { EmptyWorkingSet(p.Handle); } } catch {}
        }
    }
}
"@ -ErrorAction SilentlyContinue
    [DailyMemoryCleaner]::CleanMemory()
    [GC]::Collect()
} catch {}

$MB_Cleaned = [Math]::Round($BytesCleaned / 1MB, 2)
$LogLine = "[$Timestamp] [SUCCESS] Daily Performance Purge Completed. Deleted $FilesCleaned files ($MB_Cleaned MB). Memory trimmed."
Add-Content -Path $LogFile -Value $LogLine
Write-Output $LogLine
