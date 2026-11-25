@echo off
rem Start the game (Godot 4.5.1 in %USERPROFILE%\Godot\4.5.1). If Godot is missing, download it first.
set "GODOT=%USERPROFILE%\Godot\4.5.1\Godot_v4.5.1-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot 4.5.1 not found. Downloading...
  powershell -ExecutionPolicy Bypass -File "%~dp0tools\fetch_godot.ps1"
  if errorlevel 1 (
    echo Failed to download Godot. See the message above.
    pause
    exit /b 1
  )
)
start "" "%GODOT%" --path "%~dp0."
