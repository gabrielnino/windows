@echo off
echo ========================================================
echo Deteniendo Shokz Auto-Connect...
echo ========================================================
taskkill /F /IM ShokzAutoConnect.exe >nul 2>&1
powershell -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*ShokzAutoConnect.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }" >nul 2>&1
echo [OK] Monitor detenido.
ping 127.0.0.1 -n 3 >nul
