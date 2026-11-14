@echo off
REM Abre el instalador grafico de la traduccion (no necesita instalar nada).
if not exist "%~dp0Instalador\Instalador.ps1" (
   echo No se encuentra Instalador\Instalador.ps1 junto a este fichero.
   pause
   exit /b
)
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Instalador\Instalador.ps1"
