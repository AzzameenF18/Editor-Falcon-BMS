@echo off
rem Retira del instalador los ficheros identicos a su original en ingles (Data_ORIGINAL):
rem los mueve a Ficheros\_retirados y quita su linea de Archivos.csv (guarda antes una copia).
rem Pide confirmacion antes de tocar nada. Idioma: el elegido en el instalador (o Retirar_redundantes.bat PT).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Revisar_redundantes.ps1" -Retirar %*
echo.
pause
