@echo off
echo =======================================================
echo Restaurando el driver de OpenRun Pro 2 by Shokz...
echo =======================================================
powershell -Command "Get-PnpDevice -Class Bluetooth | Where-Object { $_.InstanceId -like '*B884116450AC*' } | Enable-PnpDevice -Confirm:$false"
echo.
echo Listo! El driver ha sido reactivado y el mensaje de 'Driver error' desaparecera de Configuracion.
pause
