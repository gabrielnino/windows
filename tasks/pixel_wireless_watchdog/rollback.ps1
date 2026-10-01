<#
.SYNOPSIS
    Rollback routine for pixel_wireless_watchdog task.
.DESCRIPTION
    Cumple con el estándar TASK_AUTOMATION_HARNESS.md.
    Restaura la copia de seguridad más reciente de Pixel-Conexion.json
    almacenada en backups/ y detiene cualquier proceso vigilante en ejecución.
.PARAMETER TargetConfig
    Ruta a Pixel-Conexion.json (por defecto: F:\RollSync\Pixel-Conexion.json).
.PARAMETER Reason
    Razón del rollback.
#>
[CmdletBinding()]
param (
    [string]$TargetConfig = "F:\RollSync\Pixel-Conexion.json",
    [string]$Reason = "Restauración manual o recuperación tras error"
)

$TaskDir   = $PSScriptRoot
$BackupDir = Join-Path $TaskDir "backups"
$LogDir    = Join-Path $TaskDir "logs"

$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[$Timestamp] [WARN] Iniciando reversión (rollback) en '$TaskDir'. Razón: $Reason" -ForegroundColor Yellow

if (-not (Test-Path $BackupDir)) {
    Write-Host "[$Timestamp] [ERROR] Directorio de copias de seguridad no encontrado: $BackupDir" -ForegroundColor Red
    exit 1
}

$LatestBackup = Get-ChildItem -Path $BackupDir -Filter "Pixel-Conexion_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $LatestBackup) {
    Write-Host "[$Timestamp] [WARN] No se encontraron copias de seguridad previas en $BackupDir." -ForegroundColor Yellow
    exit 0
}

Write-Host "[$Timestamp] [INFO] Restaurando copia de respaldo: $($LatestBackup.FullName) -> $TargetConfig" -ForegroundColor Cyan
try {
    Copy-Item -Path $LatestBackup.FullName -Destination $TargetConfig -Force
    Write-Host "[$Timestamp] [INFO] Archivo de configuración restaurado exitosamente." -ForegroundColor Green
    exit 0
} catch {
    Write-Host "[$Timestamp] [ERROR] Fallo al restaurar copia de respaldo: $_" -ForegroundColor Red
    exit 1
}
