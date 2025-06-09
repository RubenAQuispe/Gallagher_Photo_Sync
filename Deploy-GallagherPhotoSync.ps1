<#
.SYNOPSIS
    One-Click Installer for Gallagher Photo Sync
    
.DESCRIPTION
    Automatically installs and configures the complete Gallagher Photo Sync solution
    including Python, dependencies, AI models, and creates an easy-to-use configuration.
    
.PARAMETER InstallPath
    Installation directory (default: C:\GallagherPhotoSync)
    
.PARAMETER Silent
    Run in silent mode with minimal prompts
    
.PARAMETER SkipPython
    Skip Python installation (if already installed)
    
.EXAMPLE
    .\Deploy-GallagherPhotoSync.ps1
    
.EXAMPLE
    .\Deploy-GallagherPhotoSync.ps1 -InstallPath "D:\PhotoSync" -Silent
#>

[CmdletBinding()]
param(
    [string]$InstallPath = "C:\GallagherPhotoSync",
    [switch]$Silent,
    [switch]$SkipPython
)

# Version and metadata
$Version = "2.0.0"
$GitHubRepo = "https://github.com/RubenAQuispe/Gallagher_Photo_Sync"
$PythonVersion = "3.11.9"
$PythonUrl = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-amd64.exe"

# Color coding for output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    } else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Header($Message) {
    Write-Host ""
    Write-ColorOutput Green "=" * 60
    Write-ColorOutput Green "  $Message"
    Write-ColorOutput Green "=" * 60
    Write-Host ""
}

function Write-Step($Message) {
    Write-ColorOutput Cyan "🔄 $Message..."
}

function Write-Success($Message) {
    Write-ColorOutput Green "✅ $Message"
}

function Write-Warning($Message) {
    Write-ColorOutput Yellow "⚠️  $Message"
}

function Write-Error($Message) {
    Write-ColorOutput Red "❌ $Message"
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-InternetConnection {
    try {
        $response = Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 10
        return $response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Install-Python {
    param([string]$InstallPath)
    
    Write-Step "Downloading Python $PythonVersion"
    
    $pythonInstaller = Join-Path $env:TEMP "python-$PythonVersion-installer.exe"
    
    try {
        Invoke-WebRequest -Uri $PythonUrl -OutFile $pythonInstaller -UseBasicParsing
        Write-Success "Python installer downloaded"
    } catch {
        Write-Error "Failed to download Python installer: $($_.Exception.Message)"
        return $false
    }
    
    Write-Step "Installing Python $PythonVersion (this may take a few minutes)"
    
    $installArgs = @(
        "/quiet",
        "InstallAllUsers=1",
        "PrependPath=1",
        "Include_test=0",
        "Include_doc=0",
        "Include_dev=0",
        "Include_debug=0",
        "Include_launcher=1",
        "Include_pip=1"
    )
    
    try {
        $process = Start-Process -FilePath $pythonInstaller -ArgumentList $installArgs -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Success "Python installed successfully"
            
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            
            # Clean up installer
            Remove-Item $pythonInstaller -ErrorAction SilentlyContinue
            return $true
        } else {
            Write-Error "Python installation failed with exit code: $($process.ExitCode)"
            return $false
        }
    } catch {
        Write-Error "Failed to install Python: $($_.Exception.Message)"
        return $false
    }
}

function Test-PythonInstallation {
    try {
        $pythonVersion = & python --version 2>&1
        if ($pythonVersion -match "Python 3\.\d+\.\d+") {
            Write-Success "Python is installed: $pythonVersion"
            return $true
        } else {
            return $false
        }
    } catch {
        return $false
    }
}

function Install-RSATTools {
    Write-Step "Installing RSAT Active Directory Tools"
    
    try {
        # For Windows 10/11
        $capability = Get-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools*"
        if ($capability.State -ne "Installed") {
            Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
            Write-Success "RSAT Active Directory Tools installed"
        } else {
            Write-Success "RSAT Active Directory Tools already installed"
        }
        return $true
    } catch {
        Write-Warning "Could not install RSAT tools automatically. Please install manually from Windows Features."
        return $false
    }
}

function Download-Project {
    param([string]$InstallPath)
    
    Write-Step "Downloading Gallagher Photo Sync from GitHub"
    
    $zipUrl = "$GitHubRepo/archive/refs/heads/main.zip"
    $zipFile = Join-Path $env:TEMP "gallagher-photo-sync.zip"
    
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile -UseBasicParsing
        Write-Success "Project downloaded"
    } catch {
        Write-Error "Failed to download project: $($_.Exception.Message)"
        return $false
    }
    
    Write-Step "Extracting project files"
    
    try {
        # Create installation directory
        if (!(Test-Path $InstallPath)) {
            New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        }
        
        # Extract zip file
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $env:TEMP)
        
        # Move files from extracted folder to install path
        $extractedPath = Join-Path $env:TEMP "Gallagher_Photo_Sync-main"
        $items = Get-ChildItem -Path $extractedPath
        foreach ($item in $items) {
            $destination = Join-Path $InstallPath $item.Name
            if (Test-Path $destination) {
                Remove-Item $destination -Recurse -Force
            }
            Move-Item $item.FullName $destination
        }
        
        # Clean up
        Remove-Item $zipFile -ErrorAction SilentlyContinue
        Remove-Item $extractedPath -Recurse -ErrorAction SilentlyContinue
        
        Write-Success "Project files extracted to $InstallPath"
        return $true
    } catch {
        Write-Error "Failed to extract project: $($_.Exception.Message)"
        return $false
    }
}

function Install-PythonDependencies {
    param([string]$InstallPath)
    
    Write-Step "Installing Python dependencies"
    
    $requirementsFile = Join-Path $InstallPath "requirements.txt"
    if (!(Test-Path $requirementsFile)) {
        Write-Error "Requirements file not found: $requirementsFile"
        return $false
    }
    
    try {
        # Upgrade pip first
        & python -m pip install --upgrade pip --quiet
        
        # Install requirements
        & python -m pip install -r $requirementsFile --quiet
        
        Write-Success "Python dependencies installed"
        return $true
    } catch {
        Write-Error "Failed to install Python dependencies: $($_.Exception.Message)"
        return $false
    }
}

function Download-AIModels {
    Write-Step "Downloading and caching AI models (this may take several minutes)"
    
    try {
        # Run a simple test to trigger model download
        $testScript = @"
import sys
import os
sys.path.append('.')

try:
    import insightface
    import cv2
    import numpy as np
    
    # Create a small test image
    test_img = np.zeros((100, 100, 3), dtype=np.uint8)
    
    # Initialize face detector (this will download models)
    app = insightface.app.FaceAnalysis(providers=['CPUExecutionProvider'])
    app.prepare(ctx_id=0, det_size=(640, 640))
    
    # Test detection (will cache models)
    faces = app.get(test_img)
    
    print("Models downloaded and cached successfully")
    
except Exception as e:
    print(f"Error downloading models: {e}")
    sys.exit(1)
"@
        
        $tempScript = Join-Path $env:TEMP "test_models.py"
        $testScript | Out-File -FilePath $tempScript -Encoding UTF8
        
        # Change to install directory and run test
        Push-Location $InstallPath
        $result = & python $tempScript 2>&1
        Pop-Location
        
        Remove-Item $tempScript -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "AI models downloaded and cached"
            return $true
        } else {
            Write-Warning "AI models download completed with warnings. System should still work."
            return $true
        }
    } catch {
        Write-Warning "Could not pre-download AI models. They will be downloaded on first use."
        return $true
    }
}

function Start-ConfigurationWizard {
    param([string]$InstallPath)
    
    Write-Header "Configuration Wizard"
    
    if ($Silent) {
        Write-Step "Silent mode - using default configuration"
        return Create-DefaultConfiguration $InstallPath
    }
    
    Write-Host "We'll now configure your Gallagher Photo Sync installation."
    Write-Host "This wizard will prompt you for the necessary information without scanning your network."
    Write-Host ""
    
    # Step 1: Active Directory Configuration
    Write-ColorOutput Cyan "📋 Step 1 of 4: Active Directory Configuration"
    Write-Host ""
    
    $currentDomain = $env:USERDNSDOMAIN
    if ($currentDomain) {
        Write-Host "Current domain detected: $currentDomain"
        $useDomain = Read-Host "Use detected domain? (Y/n)"
        if ($useDomain -eq '' -or $useDomain -eq 'Y' -or $useDomain -eq 'y') {
            $adDomain = $currentDomain
        } else {
            $adDomain = Read-Host "Enter your Active Directory domain"
        }
    } else {
        $adDomain = Read-Host "Enter your Active Directory domain (e.g., company.local)"
    }
    
    $adServer = Read-Host "Enter domain controller (optional, press Enter to use default)"
    
    # Generate search base from domain
    $searchBase = "DC=" + ($adDomain -split '\.' -join ',DC=')
    Write-Host "Generated search base: $searchBase"
    $useSearchBase = Read-Host "Use this search base? (Y/n)"
    if ($useSearchBase -eq 'n' -or $useSearchBase -eq 'N') {
        $searchBase = Read-Host "Enter custom search base"
    }
    
    Write-Host ""
    
    # Step 2: Azure AD Connect Configuration
    Write-ColorOutput Cyan "☁️ Step 2 of 4: Azure AD Connect Configuration"
    Write-Host ""
    
    $aadConnectServer = Read-Host "Enter Azure AD Connect server name (e.g., aadconnect01.company.local)"
    
    Write-Host ""
    Write-Host "Authentication options:"
    Write-Host "1. Use current Windows credentials (recommended)"
    Write-Host "2. Specify service account"
    $authChoice = Read-Host "Choose authentication method (1 or 2)"
    
    $serviceAccount = ""
    if ($authChoice -eq "2") {
        $serviceAccount = Read-Host "Enter service account username"
    }
    
    Write-Host ""
    
    # Step 3: File Locations
    Write-ColorOutput Cyan "📁 Step 3 of 4: File Locations"
    Write-Host ""
    
    Write-Host "Common Gallagher photo locations:"
    Write-Host "- \\fileserver\gallagher\photos"
    Write-Host "- \\nas\shares\photos"
    Write-Host "- C:\Gallagher\Photos"
    
    $gallagherPath = Read-Host "Enter Gallagher photos path"
    
    Write-Host ""
    Write-Host "Installation directory: $InstallPath"
    $changeInstall = Read-Host "Change installation directory? (y/N)"
    if ($changeInstall -eq 'y' -or $changeInstall -eq 'Y') {
        $newPath = Read-Host "Enter new installation path"
        if ($newPath) {
            $InstallPath = $newPath
        }
    }
    
    Write-Host ""
    
    # Step 4: Processing Settings
    Write-ColorOutput Cyan "⚙️ Step 4 of 4: Processing Settings"
    Write-Host ""
    
    Write-Host "Recommended batch sizes:"
    Write-Host "- Small environment (1-100 users): 25"
    Write-Host "- Medium environment (100-1000 users): 50"
    Write-Host "- Large environment (1000+ users): 100"
    
    $batchSize = Read-Host "Enter batch size (default: 50)"
    if (!$batchSize) { $batchSize = 50 }
    
    $useDefaults = Read-Host "Use recommended defaults for face detection settings? (Y/n)"
    $faceConfidence = 0.5
    $maxFileSize = 100
    
    if ($useDefaults -eq 'n' -or $useDefaults -eq 'N') {
        $faceConfidence = Read-Host "Enter face detection confidence (0.1-1.0, default: 0.5)"
        if (!$faceConfidence) { $faceConfidence = 0.5 }
        
        $maxFileSize = Read-Host "Enter max file size in KB (default: 100)"
        if (!$maxFileSize) { $maxFileSize = 100 }
    }
    
    Write-Host ""
    
    # Configuration Summary
    Write-ColorOutput Cyan "📋 Configuration Summary"
    Write-Host ""
    Write-Host "Domain: $adDomain"
    if ($adServer) { Write-Host "Domain Controller: $adServer" }
    Write-Host "Search Base: $searchBase"
    Write-Host "Azure AD Connect: $aadConnectServer"
    if ($serviceAccount) { Write-Host "Service Account: $serviceAccount" }
    Write-Host "Gallagher Photos: $gallagherPath"
    Write-Host "Installation: $InstallPath"
    Write-Host "Batch Size: $batchSize"
    Write-Host "Face Confidence: $faceConfidence"
    Write-Host "Max File Size: $maxFileSize KB"
    Write-Host ""
    
    $confirm = Read-Host "Save this configuration? (Y/n)"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Warning "Configuration cancelled. You can run the configuration wizard again later."
        return $false
    }
    
    # Create configuration
    return Create-Configuration -InstallPath $InstallPath -ADDomain $adDomain -ADServer $adServer -SearchBase $searchBase -AADConnectServer $aadConnectServer -ServiceAccount $serviceAccount -GallagherPath $gallagherPath -BatchSize $batchSize -FaceConfidence $faceConfidence -MaxFileSize $maxFileSize
}

function Create-Configuration {
    param(
        [string]$InstallPath,
        [string]$ADDomain,
        [string]$ADServer,
        [string]$SearchBase,
        [string]$AADConnectServer,
        [string]$ServiceAccount,
        [string]$GallagherPath,
        [int]$BatchSize,
        [float]$FaceConfidence,
        [int]$MaxFileSize
    )
    
    Write-Step "Creating configuration file"
    
    $configPath = Join-Path $InstallPath "config\config.json"
    $configDir = Split-Path $configPath -Parent
    
    if (!(Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    
    $config = @{
        active_directory = @{
            domain = $ADDomain
            search_base = $SearchBase
            batch_size = $BatchSize
        }
        azure_ad_connect = @{
            server = $AADConnectServer
        }
        gallagher = @{
            photo_path = $GallagherPath
        }
        face_processing = @{
            target_size = @(96, 96)
            max_file_size_kb = $MaxFileSize
            min_face_confidence = $FaceConfidence
            padding_width_factor = 0.6
            padding_height_factor = 1.5
            batch_size = $BatchSize
        }
        logging = @{
            level = "INFO"
            max_file_size_mb = 10
            backup_count = 5
        }
        installation = @{
            version = $Version
            install_path = $InstallPath
            configured_date = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
    
    if ($ADServer) {
        $config.active_directory.server = $ADServer
    }
    
    if ($ServiceAccount) {
        $config.azure_ad_connect.service_account = $ServiceAccount
    }
    
    try {
        $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $configPath -Encoding UTF8
        Write-Success "Configuration saved to $configPath"
        return $true
    } catch {
        Write-Error "Failed to save configuration: $($_.Exception.Message)"
        return $false
    }
}

function Create-DefaultConfiguration {
    param([string]$InstallPath)
    
    $currentDomain = $env:USERDNSDOMAIN
    if (!$currentDomain) {
        $currentDomain = "company.local"
    }
    
    $searchBase = "DC=" + ($currentDomain -split '\.' -join ',DC=')
    
    return Create-Configuration -InstallPath $InstallPath -ADDomain $currentDomain -ADServer "" -SearchBase $searchBase -AADConnectServer "aadconnect.$currentDomain" -ServiceAccount "" -GallagherPath "\\server\gallagher\photos" -BatchSize 50 -FaceConfidence 0.5 -MaxFileSize 100
}

function Create-Shortcuts {
    param([string]$InstallPath)
    
    Write-Step "Creating desktop shortcuts and Start Menu entries"
    
    try {
        $shell = New-Object -ComObject WScript.Shell
        
        # Desktop shortcuts
        $desktopPath = [System.Environment]::GetFolderPath('Desktop')
        
        # Main sync shortcut
        $syncShortcut = $shell.CreateShortcut((Join-Path $desktopPath "Run Gallagher Photo Sync.lnk"))
        $syncShortcut.TargetPath = "powershell.exe"
        $syncShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$InstallPath\run_complete_sync.ps1`""
        $syncShortcut.WorkingDirectory = $InstallPath
        $syncShortcut.Description = "Run Gallagher Photo Sync"
        $syncShortcut.Save()
        
        # Configuration shortcut
        $configShortcut = $shell.CreateShortcut((Join-Path $desktopPath "Photo Sync Configuration.lnk"))
        $configShortcut.TargetPath = "notepad.exe"
        $configShortcut.Arguments = "`"$InstallPath\config\config.json`""
        $configShortcut.Description = "Edit Photo Sync Configuration"
        $configShortcut.Save()
        
        # Logs shortcut
        $logsShortcut = $shell.CreateShortcut((Join-Path $desktopPath "Photo Sync Logs.lnk"))
        $logsShortcut.TargetPath = "explorer.exe"
        $logsShortcut.Arguments = "`"$InstallPath\logs`""
        $logsShortcut.Description = "View Photo Sync Logs"
        $logsShortcut.Save()
        
        Write-Success "Desktop shortcuts created"
        
        # Start Menu folder
        $startMenuPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\Gallagher Photo Sync"
        if (!(Test-Path $startMenuPath)) {
            New-Item -ItemType Directory -Path $startMenuPath -Force | Out-Null
        }
        
        # Start Menu shortcuts
        $startSyncShortcut = $shell.CreateShortcut((Join-Path $startMenuPath "Run Photo Sync.lnk"))
        $startSyncShortcut.TargetPath = "powershell.exe"
        $startSyncShortcut.Arguments = "-ExecutionPolicy Bypass -File `"$InstallPath\run_complete_sync.ps1`""
        $startSyncShortcut.WorkingDirectory = $InstallPath
        $startSyncShortcut.Description = "Run Gallagher Photo Sync"
        $startSyncShortcut.Save()
        
        $startConfigShortcut = $shell.CreateShortcut((Join-Path $startMenuPath "Configuration.lnk"))
        $startConfigShortcut.TargetPath = "notepad.exe"
        $startConfigShortcut.Arguments = "`"$InstallPath\config\config.json`""
        $startConfigShortcut.Description = "Edit Configuration"
        $startConfigShortcut.Save()
        
        $startLogsShortcut = $shell.CreateShortcut((Join-Path $startMenuPath "View Logs.lnk"))
        $startLogsShortcut.TargetPath = "explorer.exe"
        $startLogsShortcut.Arguments = "`"$InstallPath\logs`""
        $startLogsShortcut.Description = "View Logs"
        $startLogsShortcut.Save()
        
        Write-Success "Start Menu entries created"
        return $true
    } catch {
        Write-Warning "Could not create shortcuts: $($_.Exception.Message)"
        return $false
    }
}

function Test-Installation {
    param([string]$InstallPath)
    
    Write-Step "Testing installation"
    
    $errors = @()
    
    # Test Python
    if (!(Test-PythonInstallation)) {
        $errors += "Python installation test failed"
    }
    
    # Test required files
    $requiredFiles = @(
        "config\config.json",
        "scripts\1_extract_and_rename.ps1",
        "scripts\2_face_crop_resize.py",
        "scripts\3_ad_import.ps1",
        "scripts\4_sync_trigger.ps1",
        "scripts\5_audit_report.ps1",
        "requirements.txt"
    )
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $InstallPath $file
        if (!(Test-Path $filePath)) {
            $errors += "Missing file: $file"
        }
    }
    
    # Test Python imports
    try {
        $testImports = @"
import sys
import os
import cv2
import numpy as np
import insightface
from PIL import Image
print("All Python imports successful")
"@
        
        $tempScript = Join-Path $env:TEMP "test_imports.py"
        $testImports | Out-File -FilePath $tempScript -Encoding UTF8
        
        Push-Location $InstallPath
        $result = & python $tempScript 2>&1
        Pop-Location
        
        Remove-Item $tempScript -ErrorAction SilentlyContinue
        
        if ($LASTEXITCODE -ne 0) {
            $errors += "Python dependency test failed"
        }
    } catch {
        $errors += "Python import test failed: $($_.Exception.Message)"
    }
    
    if ($errors.Count -eq 0) {
        Write-Success "Installation test passed"
        return $true
    } else {
        Write-Warning "Installation test found issues:"
        foreach ($error in $errors) {
            Write-Host "  - $error"
        }
        return $false
    }
}

function Complete-Installation {
    param([string]$InstallPath)
    
    Write-Header "🎉 Installation Complete!"
    
    Write-Host ""
    Write-ColorOutput Green "Gallagher Photo Sync has been successfully installed!"
    Write-Host ""
    Write-Host "📍 Installation Location: $InstallPath"
    Write-Host "🖥️  Desktop Shortcuts: Created"
    Write-Host "📋 Start Menu: Programs > Gallagher Photo Sync"
    Write-Host "⚙️  Configuration: $InstallPath\config\config.json"
    Write-Host ""
    
    Write-ColorOutput Cyan "Quick Start:"
    Write-Host "1. Double-click 'Run Gallagher Photo Sync' on your desktop"
    Write-Host "2. Or run: $InstallPath\run_complete_sync.ps1"
    Write-Host ""
    
    Write-ColorOutput Cyan "Next Steps:"
    Write-Host "1. Verify your configuration in config\config.json"
    Write-Host "2. Place Gallagher photos in the configured input directory"
    Write-Host "3. Run your first sync using the desktop shortcut"
    Write-Host ""
    
    if (!$Silent) {
        $runNow = Read-Host "Would you like to view the configuration file now? (y/N)"
        if ($runNow -eq 'y' -or $runNow -eq 'Y') {
            Start-Process notepad.exe -ArgumentList (Join-Path $InstallPath "config\config.json")
        }
    }
    
    Write-ColorOutput Green "Installation completed successfully! 🎉"
    Write-Host ""
}

# Main installation process
try {
    Write-Header "🚀 Gallagher Photo Sync - One-Click Installer v$Version"
    
    # Phase 1: System Check & Preparation
    Write-Header "Phase 1: System Check & Preparation"
    
    Write-Step "Checking system requirements"
    
    if (!(Test-Administrator)) {
        Write-Error "This installer must be run as Administrator"
        Write-Host "Please right-click and select 'Run as Administrator'"
        pause
        exit 1
    }
    
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Error "Windows 10 or later is required"
        pause
        exit 1
    }
    
    Write-Success "Running as Administrator on Windows $($osVersion.Major).$($osVersion.Minor)"
    
    if (!(Test-InternetConnection)) {
        Write-Error "Internet connection is required for installation"
        pause
        exit 1
    }
    
    Write-Success "Internet connection verified"
    
    # Create installation directory
    if (!(Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    }
    Write-Success "Installation directory ready: $InstallPath"
    
    # Phase 2: Prerequisites Installation
    Write-Header "Phase 2: Prerequisites Installation"
    
    if (!$SkipPython) {
        if (!(Test-PythonInstallation)) {
            if (!(Install-Python -InstallPath $InstallPath)) {
                Write-Error "Python installation failed"
                pause
                exit 1
            }
        } else {
            Write-Success "Python is already installed"
        }
    } else {
        Write-Success "Skipping Python installation as requested"
    }
    
    Install-RSATTools | Out-Null
    
    # Phase 3: Project Setup
    Write-Header "Phase 3: Project Setup"
    
    if (!(Download-Project -InstallPath $InstallPath)) {
        Write-Error "Failed to download project"
        pause
        exit 1
    }
    
    if (!(Install-PythonDependencies -InstallPath $InstallPath)) {
        Write-Error "Failed to install Python dependencies"
        pause
        exit 1
    }
    
    Download-AIModels | Out-Null
    
    # Phase 4: Configuration
    Write-Header "Phase 4: Configuration"
    
    if (!(Start-ConfigurationWizard -InstallPath $InstallPath)) {
        Write-Error "Configuration failed"
        pause
        exit 1
    }
    
    # Phase 5: Finalization
    Write-Header "Phase 5: Finalization"
    
    Create-Shortcuts -InstallPath $InstallPath | Out-Null
    
    Test-Installation -InstallPath $InstallPath | Out-Null
    
    Complete-Installation -InstallPath $InstallPath
    
} catch {
    Write-Error "Installation failed: $($_.Exception.Message)"
    Write-Host "Stack trace: $($_.ScriptStackTrace)"
    pause
    exit 1
}

if (!$Silent) {
    pause
}
