@echo off
REM Abre el Editor de Falcon BMS (SCF, RSC y campanas en una sola ventana con pestanas).
REM Deja una ventana minimizada mientras se usa; se cierra sola al rato de cerrar el navegador.
if not exist "%~dp0Editor_BMS.ps1" (
   echo No se encuentra Editor_BMS.ps1 junto a este fichero.
   pause
   exit /b
)
start "Editor de Falcon BMS" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Editor_BMS.ps1"
