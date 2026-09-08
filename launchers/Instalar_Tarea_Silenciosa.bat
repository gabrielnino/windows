@echo off
echo =========================================================
echo Registrando tarea silenciosa para Shokz Toggle (Sin UAC)
echo =========================================================
schtasks /create /tn "Toggle_Shokz_Headset" /tr "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File \"F:\windows\launchers\Toggle-Shokz.ps1\"" /sc onlogon /rl highest /f
echo.
echo Listo. Ya puedes hacer clic en el acceso directo sin aviso de Administrador.
pause
