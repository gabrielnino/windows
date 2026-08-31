<#
.SYNOPSIS
    Deep Bluetooth Radio Beacon & Advertisement Scanner with Auto-Pairing.
#>
[CmdletBinding()]
param (
    [int]$ScanDurationSeconds = 15
)

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

[Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Bluetooth.Advertisement.BluetoothLEScanningMode, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Bluetooth.BluetoothDevice, Windows.Devices.Bluetooth, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType=WindowsRuntime] | Out-Null
[Windows.Devices.Enumeration.DevicePairingResult, Windows.Devices.Enumeration, ContentType=WindowsRuntime] | Out-Null

$watcher = New-Object Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher
$watcher.ScanningMode = [Windows.Devices.Bluetooth.Advertisement.BluetoothLEScanningMode]::Active

$discoveredAddresses = [System.Collections.Generic.HashSet[ulong]]::new()
$discoveredDevices = [System.Collections.Generic.List[object]]::new()

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "     DIAGNOSTICO EN CONSOLA: ESCANEANDO BEACONS DE BLUETOOTH     " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Radio Bluetooth activo. Escaneando anuncios durante $ScanDurationSeconds segundos..." -ForegroundColor Yellow

$action = {
    param($sender, $args)
    $addr = $args.BluetoothAddress
    if (-not $discoveredAddresses.Contains($addr)) {
        $discoveredAddresses.Add($addr) | Out-Null
        
        $hexMac = ($addr.ToString("X12") -split '([A-F0-9]{2})' | Where-Object { $_ }) -join ':'
        $localName = $args.Advertisement.LocalName
        $rssi = $args.RawSignalStrengthInDBm
        
        $nameDisplay = if ($localName) { $localName } else { "<Sin Nombre / Beacon Anonimo>" }
        Write-Host ("[DETECTADO] MAC: {0} | RSSI: {1} dBm | Nombre: '{2}'" -f $hexMac, $rssi, $nameDisplay) -ForegroundColor Green
        
        $obj = [PSCustomObject]@{
            AddressHex = $hexMac
            AddressUlong = $addr
            Name = $localName
            RSSI = $rssi
        }
        $discoveredDevices.Add($obj)

        if ($localName -and (
            $localName.ToLower() -like "*shokz*" -or 
            $localName.ToLower() -like "*openrun*" -or 
            $localName.ToLower() -like "*aftershokz*" -or 
            $localName.ToLower() -like "*opencomm*" -or 
            $localName.ToLower() -like "*openfit*"
        )) {
            Write-Host ("MATCH ENCONTRADO EN CONSOLA: {0}" -f $localName) -ForegroundColor Cyan
            Write-Host ("Intentando obtener objeto BluetoothDevice para MAC: {0}..." -f $hexMac) -ForegroundColor Cyan
            
            try {
                $devOp = [Windows.Devices.Bluetooth.BluetoothDevice]::FromBluetoothAddressAsync($addr)
                $btDev = Await-WinRt $devOp ([Windows.Devices.Bluetooth.BluetoothDevice])
                
                if ($btDev) {
                    Write-Host ("Dispositivo obtenido: {0}. IsPaired: {1}" -f $btDev.Name, $btDev.DeviceInformation.Pairing.IsPaired) -ForegroundColor Green
                    Write-Host "Iniciando solicitud de emparejamiento..." -ForegroundColor Yellow
                    
                    $pairOp = $btDev.DeviceInformation.Pairing.PairAsync([Windows.Devices.Enumeration.DevicePairingProtectionLevel]::None)
                    $pairRes = Await-WinRt $pairOp ([Windows.Devices.Enumeration.DevicePairingResult])
                    
                    Write-Host "RESULTADO DEL EMPAREJAMIENTO: $($pairRes.Status)" -ForegroundColor Yellow
                } else {
                    Write-Host "No se pudo obtener el dispositivo Bluetooth desde la direccion MAC." -ForegroundColor Red
                }
            } catch {
                Write-Host "Excepcion durante el emparejamiento: $_" -ForegroundColor Red
            }
        }
    }
}

$handler = [Windows.Foundation.TypedEventHandler[Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher, Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementReceivedEventArgs]]$action
$watcher.add_Received($handler)

$watcher.Start()

$timer = 0
while ($timer -lt $ScanDurationSeconds) {
    Start-Sleep -Seconds 1
    $timer++
}

$watcher.Stop()

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "                   RESUMEN TOTAL DEL ESCANEO                     " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Dispositivos totales descubiertos: $($discoveredDevices.Count)" -ForegroundColor Yellow
if ($discoveredDevices.Count -gt 0) {
    $discoveredDevices | Format-Table -AutoSize
} else {
    Write-Host "No se recibio ningun paquete de radio Bluetooth durante el escaneo." -ForegroundColor Red
}
