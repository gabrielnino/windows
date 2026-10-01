<#
.SYNOPSIS
    Watchdog de conexión inalámbrica para Google Pixel 8 Pro y RollSync.
.DESCRIPTION
    Cumple con el estándar TASK_AUTOMATION_HARNESS.md.
    Supervisa pasivamente anuncios mDNS de Android (_adb-tls-connect._tcp).
    Detecta cambios de dirección IP y puerto dinámico del Pixel 8 Pro,
    mantiene activa la conexión ADB inalámbrica y actualiza de forma atómica
    el archivo Pixel-Conexion.json de RollSync.
.PARAMETER Continuous
    Ejecuta el vigilante en modo continuo cada N segundos.
.PARAMETER Once
    Ejecuta un único ciclo de verificación y genera el informe KPI.
.PARAMETER IntervalSeconds
    Intervalo en segundos entre cada comprobación (por defecto: 30s).
.PARAMETER DryRun
    Simula la detección sin sobrescribir Pixel-Conexion.json.
.PARAMETER NoVoice
    Desactiva las notificaciones de voz colombiana (Salomé).
.EXAMPLE
    .\tasks\pixel_wireless_watchdog\run.ps1 -Once
.EXAMPLE
    .\tasks\pixel_wireless_watchdog\run.ps1 -Continuous -IntervalSeconds 30
#>
[CmdletBinding()]
param (
    [switch]$Continuous,
    [switch]$Once,
    [int]$IntervalSeconds = 30,
    [switch]$DryRun,
    [switch]$NoVoice
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$TaskDir     = $PSScriptRoot
$LogDir      = Join-Path $TaskDir "logs"
$ReportDir   = Join-Path $TaskDir "reports"
$ConfigDir   = Join-Path $TaskDir "config"
$BackupDir   = Join-Path $TaskDir "backups"
$ArtifactDir = Join-Path $TaskDir "artifacts"

New-Item -ItemType Directory -Force -Path $LogDir, $ReportDir, $ConfigDir, $BackupDir, $ArtifactDir | Out-Null

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $LogDir "task_$Timestamp.log"

function Write-Log {
    param (
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "DEBUG", "ALERT")][string]$Level = "INFO"
    )
    $TimeStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Line = "[$TimeStr] [$Level] $Message"
    
    switch ($Level) {
        "ALERT" { Write-Host $Line -ForegroundColor Red -BackgroundColor Black }
        "ERROR" { Write-Host $Line -ForegroundColor Red }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        "DEBUG" { Write-Host $Line -ForegroundColor DarkGray }
        default { Write-Host $Line -ForegroundColor Cyan }
    }
    Add-Content -Path $LogFile -Value $Line -Encoding utf8
}

Write-Log "Iniciando pixel_wireless_watchdog harness..." "INFO"

# Construir argumentos para run.py
$PythonExe = "python"
$RunPy     = Join-Path $TaskDir "run.py"

$ArgsList = @()
if ($Continuous) {
    $ArgsList += "--daemon"
    $ArgsList += "--interval"
    $ArgsList += $IntervalSeconds.ToString()
} else {
    $ArgsList += "--once"
}

if ($DryRun) { $ArgsList += "--dry-run" }
if ($NoVoice) { $ArgsList += "--no-voice" }

try {
    & $PythonExe $RunPy @ArgsList
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -eq 0) {
        Write-Log "Tarea pixel_wireless_watchdog finalizada con éxito (Código 0)." "INFO"
        exit 0
    } else {
        Write-Log "Tarea pixel_wireless_watchdog terminó con código $ExitCode." "ERROR"
        exit $ExitCode
    }
} catch {
    Write-Log "Excepción no controlada ejecutando el vigilante: $_" "ERROR"
    exit 1
}
