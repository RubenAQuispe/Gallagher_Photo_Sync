@echo off
:: Gallagher Photo Sync - One-Click Installer Launcher
:: This batch file launches the PowerShell installer with proper execution policy

echo.
echo ================================================================
echo   Gallagher Photo Sync - One-Click Installer
echo ================================================================
echo.
echo This will install and configure Gallagher Photo Sync on your system.
echo.
echo Requirements:
echo - Windows 10 or later
echo - Administrator privileges
echo - Internet connection
echo.
echo The installer will:
echo 1. Install Python 3.11
echo 2. Install RSAT Active Directory Tools
echo 3. Download and configure Gallagher Photo Sync
echo 4. Set up AI models for face detection
echo 5. Create desktop shortcuts
echo.
pause

:: Check if running as administrator
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo ERROR: This installer must be run as Administrator
    echo.
    echo Please right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: Launch PowerShell installer with bypass execution policy
echo.
echo Starting installation...
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Deploy-GallagherPhotoSync.ps1"

echo.
echo Installation process completed.
echo.
pause
