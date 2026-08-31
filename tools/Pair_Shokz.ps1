<#
.SYNOPSIS
    Automated Bluetooth Device Discovery and Pairing Script for Shokz Headphones.
#>
[CmdletBinding()]
param(
    [int]$ScanTimeoutSeconds = 25
)

$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "       BUSCANDO Y EMPAREJANDO AUDÍFONOS SHOKZ EN BLUETOOTH       " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Por favor asegúrate de que los audífonos Shokz estén en modo emparejamiento" -ForegroundColor Yellow
Write-Host "(Luces parpadeando en rojo/azul o azul continuo).`n" -ForegroundColor Yellow

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { 
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.IsGenericMethod 
} | Select-Object -First 1

function Await-WinRt($WinRtTask, $ResultType) {
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait()
    return $netTask.Result
}

[Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Enumeration.DevicePairingResult, Windows.Devices.Enumeration, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null

$selector = [Windows.Devices.Bluetooth.BluetoothDevice]::GetDeviceSelector()
$watcher = [Windows.Devices.Enumeration.DeviceInformation]::CreateWatcher($selector)

$foundDevices = [System.Collections.Generic.List[object]]::new()
$paired = $false

Register-ObjectEvent -InputObject $watcher -EventName 'Added' -Action {
    $info = $Event.SourceEventArgs
    if ($info.Name -and $info.Name.Trim().Length -gt 0) {
        Write-Host "[DETECTADO] Dispositivo: $($info.Name) (ID: $($info.Id))" -ForegroundColor Green
        $foundDevices.Add($info)
        
        $n = $info.Name.ToLower()
        if ($n -like "*shokz*" -or $n -like "*openrun*" -or $n -like "*aftershokz*" -or $n -like "*opencomm*" -or $n -like "*openfit*" -or $n -like "*headphone*" -or $n -like "*audifono*") {
            Write-Host "`n>>> ¡COINCIDENCIA ENCONTRADA: '$($info.Name)'! Iniciando emparejamiento automático... <<<" -ForegroundColor Cyan
            try {
                $pairOp = $info.Pairing.PairAsync([Windows.Devices.Enumeration.DevicePairingProtectionLevel]::None)
                $res = Await-WinRt $pairOp ([Windows.Devices.Enumeration.DevicePairingResult])
                Write-Host "`n========================================================" -ForegroundColor Cyan
                Write-Host "RESULTADO DEL EMPAREJAMIENTO PARA '$($info.Name)': $($res.Status)" -ForegroundColor Yellow
                Write-Host "========================================================`n" -ForegroundColor Cyan
                $script:paired = $true
            } catch {
                Write-Host "Error al emparejar: $_" -ForegroundColor Red
            }
        }
    }
} | Out-Null

Write-Host "Iniciando escáner de radio Bluetooth durante $ScanTimeoutSeconds segundos..." -ForegroundColor Cyan
$watcher.Start()

$elapsed = 0
while ($elapsed -lt $ScanTimeoutSeconds -and -not $paired) {
    Start-Sleep -Seconds 1
    $elapsed++
}

$watcher.Stop()
Write-Host "`nEscaneo finalizado." -ForegroundColor Cyan

if (-not $paired) {
    Write-Host "`nDispositivos detectados durante el escaneo:" -ForegroundColor Yellow
    if ($foundDevices.Count -gt 0) {
        $foundDevices | Select-Object Name, Id | Format-Table -AutoSize
    } else {
        Write-Host "No se detectaron dispositivos nuevos en modo emparejamiento." -ForegroundColor DarkYellow
    }
}
