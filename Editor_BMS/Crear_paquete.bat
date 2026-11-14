@echo off
setlocal
chcp 65001 >nul
rem Crea una copia limpia del Editor BMS para pasarla a otras personas.
rem NO borra nada de esta carpeta: copia lo necesario y lo comprime en un zip junto a ella.
rem Se excluye lo que cada uno se instala (venv, ffmpeg, modelo), lo generado (cache, wav_es,
rem prueba, Falcon_*.tlk, latentes, Voces\Idiomas) y lo personal (voces.json, Editados, Originales, Respaldo).

set "ORIGEN=%~dp0"
set "ORIGEN=%ORIGEN:~0,-1%"
for %%I in ("%ORIGEN%") do set "PADRE=%%~dpI"
set "TMPD=%TEMP%\Editor_BMS_paquete"
set "DEST=%TMPD%\Editor_BMS"
set "ZIP=%PADRE%Editor_BMS_distribuir.zip"

echo Preparando copia limpia del Editor BMS...
if exist "%TMPD%" rmdir /s /q "%TMPD%"

robocopy "%ORIGEN%" "%DEST%" /E /NFL /NDL /NJH /NJS /NP ^
  /XD venv venv_cb .venv ffmpeg modelos cache cache_cb wav_es prueba __pycache__ Editados Originales Respaldo "%ORIGEN%\Voces\Idiomas" ^
  /XF voces.json idioma.txt Mapa_*.origen.txt *.latentes.pt *.chatterbox.pt Falcon_*.tlk montado_*.json *.tmp *.pyc *.bak Editor_BMS_distribuir.zip >nul
if errorlevel 8 (
  echo ERROR al copiar los ficheros.
  goto :fin
)

if exist "%ZIP%" del /q "%ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path $env:DEST -DestinationPath $env:ZIP -CompressionLevel Optimal"
if errorlevel 1 (
  echo ERROR al crear el zip.
  goto :fin
)
rmdir /s /q "%TMPD%"

echo.
echo Hecho:
echo   %ZIP%
for %%A in ("%ZIP%") do echo   Tamano: %%~zA bytes
echo.
echo Quien lo reciba: descomprimir, abrir Editor_BMS.bat y, para las voces,
echo pulsar "Preparar entorno..." en la pestana Voces.

:fin
echo.
pause
