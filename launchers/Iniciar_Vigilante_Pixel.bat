@echo off
title Pixel 8 Pro - Vigilante Inalambrico RollSync
color 0B
echo.
echo   =========================================================
echo        PIXEL 8 PRO ^| VIGILANTE INALAMBRICO ROLLSYNC
echo        Supervision automatica de IP y puerto por mDNS
echo   =========================================================
echo.
echo   Iniciando servicio de supervision en segundo plano...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tasks\pixel_wireless_watchdog\run.ps1" -Continuous -IntervalSeconds 30
if errorlevel 1 pause
