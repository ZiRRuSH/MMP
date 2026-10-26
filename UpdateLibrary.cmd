@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0GenerateLibrary.ps1"
if errorlevel 1 echo FAILED: See the error above. The previous library may still be in place.
pause
