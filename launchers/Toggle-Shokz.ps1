$wshell = New-Object -ComObject WScript.Shell
$mac = "b8:84:11:64:50:ac"
$cli = Join-Path $PSScriptRoot "BluetoothDevicePairing.exe"

# Re-enable if disabled from old script
$disabledDevice = Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { 
    $_.InstanceId -like "*DEV_B884116450AC*" -and $_.Problem -eq "CM_PROB_DISABLED" 
}
if ($disabledDevice) {
    try {
        Enable-PnpDevice -InstanceId $disabledDevice.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}
}

# Check if audio endpoint is currently connected
$connectedEndpoint = Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { 
    $_.FriendlyName -like "*OpenRun*" -and $_.Present -eq $true 
}

if ($connectedEndpoint) {
    & $cli disconnect-bluetooth-audio-device-by-mac --mac $mac --type Bluetooth | Out-Null
    $wshell.Popup("OpenRun Pro 2: Desconectado", 2, "Shokz Bluetooth", 64) | Out-Null
} else {
    & $cli pair-by-mac --mac $mac --type Bluetooth | Out-Null
    $wshell.Popup("OpenRun Pro 2: Conectando...", 2, "Shokz Bluetooth", 64) | Out-Null
}
