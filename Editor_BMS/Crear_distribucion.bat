@echo off
rem Crea el zip para distribuir la traduccion completa (instalador + idiomas + editor), sin lo de este equipo.
rem No borra ni cambia nada: deja Traduccion_BMS_<version>.zip junto a la carpeta del paquete.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Crear_distribucion.ps1"
echo.
pause
