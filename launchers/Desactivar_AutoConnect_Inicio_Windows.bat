@echo off
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"

echo ========================================================
echo Desactivando Shokz Auto-Connect del inicio de Windows...
echo ========================================================
del "%STARTUP%\ShokzAutoConnect.lnk" >nul 2>&1
taskkill /F /IM ShokzAutoConnect.exe >nul 2>&1
powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*ShokzAutoConnect.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
echo [OK] Desactivado del inicio y detenido.
ping 127.0.0.1 -n 3 >nul
