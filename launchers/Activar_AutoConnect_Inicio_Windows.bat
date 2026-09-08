@echo off
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "TARGET=F:\windows\launchers\ShokzAutoConnect.exe"

echo ========================================================
echo Activando Shokz Auto-Connect al iniciar Windows...
echo ========================================================

powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $sc = $ws.CreateShortcut('%STARTUP%\ShokzAutoConnect.lnk'); $sc.TargetPath = '%TARGET%'; $sc.WorkingDirectory = 'F:\windows\launchers'; $sc.IconLocation = 'F:\windows\launchers\audifonos.ico,0'; $sc.Save()"

echo.
echo [OK] Auto-Connect configurado para arrancar con Windows.
echo Iniciando proceso ahora en segundo plano...
start "" "F:\windows\launchers\ShokzAutoConnect.exe"
echo.
echo Listo! El monitor de proximidad ya esta activo.
ping 127.0.0.1 -n 3 >nul
