$mac = "b8:84:11:64:50:ac"
$cli = Join-Path $PSScriptRoot "BluetoothDevicePairing.exe"
$wshell = New-Object -ComObject WScript.Shell

Write-Host "Iniciando monitor de proximidad para OpenRun Pro 2..."

while ($true) {
    # 1. Verificar si los audifonos ya estan conectados a Windows
    $connected = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { 
        $_.FriendlyName -like "*OpenRun*" -and $_.Present -eq $true 
    }

    if ($connected) {
        # Si estan conectados, no hacer nada. Esperar 10 segundos.
        Start-Sleep -Seconds 10
    } else {
        # Si estan desconectados, intentar conectar si estan cerca
        $output = & $cli pair-by-mac --mac $mac --type Bluetooth 2>&1 | Out-String

        # Comprobar si la conexion tuvo exito
        Start-Sleep -Seconds 2
        $nowConnected = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { 
            $_.FriendlyName -like "*OpenRun*" -and $_.Present -eq $true 
        }

        if ($nowConnected) {
            # Se han conectado! Mostrar confirmacion
            $wshell.Popup("OpenRun Pro 2 detectados cerca y conectados automaticamente.", 3, "Shokz Auto-Connect", 64) | Out-Null
            Start-Sleep -Seconds 10
        } else {
            # No estan cerca o estan apagados. Volver a mirar en 5 segundos
            Start-Sleep -Seconds 5
        }
    }
}
