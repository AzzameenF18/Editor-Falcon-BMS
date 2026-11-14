@echo off
rem Saca una lista de los ficheros del instalador que son identicos al original en ingles
rem (se pueden retirar). No borra ni modifica nada: el resultado va a Revision_redundantes_XX.txt (XX = idioma)
rem Usa el idioma elegido en el instalador; para otro: Revisar_redundantes.bat PT
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Revisar_redundantes.ps1" %*
echo.
pause
