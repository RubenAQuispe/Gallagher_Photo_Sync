# Gallagher Photo Sync - One-Click Deployment Guide

## 🚀 Quick Start (Recommended)

### Step 1: Download the Installer
1. Download the latest release from: https://github.com/RubenAQuispe/Gallagher_Photo_Sync
2. Extract all files to a folder (e.g., `C:\Temp\GallagherInstaller\`)

### Step 2: Run the One-Click Installer
1. **Right-click** on `QUICK_START.bat`
2. Select **"Run as administrator"**
3. Follow the prompts in the installer

That's it! The installer will handle everything automatically.

---

## 📋 What the Installer Does

### ✅ Automatic Installation Process

**Phase 1: System Check**
- Verifies Windows 10+ and Administrator privileges
- Tests internet connectivity
- Creates installation directory

**Phase 2: Prerequisites**
- Downloads and installs Python 3.11 (silent installation)
- Enables RSAT Active Directory Tools
- Updates system PATH variables

**Phase 3: Project Setup**
- Downloads latest Gallagher Photo Sync from GitHub
- Installs all Python dependencies (OpenCV, InsightFace, etc.)
- Downloads and caches AI models for offline use

**Phase 4: Configuration Wizard**
- Interactive setup without network scanning
- Prompts for AD domain and server information
- Configures Azure AD Connect settings
- Sets up file paths and processing options

**Phase 5: Finalization**
- Creates desktop shortcuts
- Sets up Start Menu entries
- Tests the installation
- Displays completion summary

---

## 🎯 Configuration Wizard

The installer will prompt you for the following information:

### Active Directory Configuration
```
📋 Active Directory Settings
- Domain: [Auto-detected or manual entry]
- Domain Controller: [Optional specific server]
- Search Base: [Auto-generated from domain]
```

### Azure AD Connect Configuration
```
☁️ Azure AD Connect Settings
- Server Name: [Manual entry required]
- Authentication: [Current credentials or service account]
```

### File Locations
```
📁 File Paths
- Gallagher Photos: [Network path or local folder]
- Installation Directory: [Default: C:\GallagherPhotoSync]
```

### Processing Settings
```
⚙️ Processing Options
- Batch Size: [25/50/100 based on environment size]
- Face Detection: [Use defaults or customize]
```

---

## 🖥️ Post-Installation

### Desktop Shortcuts Created
- **"Run Gallagher Photo Sync"** - Main execution
- **"Photo Sync Configuration"** - Edit settings
- **"Photo Sync Logs"** - View processing logs

### Start Menu Integration
```
Programs > Gallagher Photo Sync >
├── Run Photo Sync
├── Configuration
└── View Logs
```

### Directory Structure
```
C:\GallagherPhotoSync\
├── config\config.json          # Main configuration
├── scripts\                    # All processing scripts
├── input\gallagher_photos\     # Place source photos here
├── processing\                 # Temporary processing folders
├── output\                     # Final processed photos
└── logs\                       # All log files
```

---

## 🔧 Advanced Installation Options

### Silent Installation
For automated deployments without user prompts:
```powershell
.\Deploy-GallagherPhotoSync.ps1 -Silent
```

### Custom Installation Path
```powershell
.\Deploy-GallagherPhotoSync.ps1 -InstallPath "D:\PhotoSync"
```

### Skip Python Installation
If Python 3.8+ is already installed:
```powershell
.\Deploy-GallagherPhotoSync.ps1 -SkipPython
```

---

## 📊 System Requirements

### Minimum Requirements
- **OS**: Windows 10 or Windows Server 2016+
- **RAM**: 8GB (16GB recommended for large photo sets)
- **Disk**: 5GB free space (more for photo processing)
- **Network**: Internet access during installation
- **Permissions**: Local Administrator rights

### Required Network Access
- **Domain Controllers**: For Active Directory operations
- **Azure AD Connect Server**: For synchronization
- **Gallagher Photo Share**: To access source photos
- **Internet**: During installation only (for downloading dependencies)

### Software Dependencies (Auto-Installed)
- **Python 3.11**: Automatically downloaded and installed
- **RSAT Tools**: Enabled via Windows Features
- **Python Packages**: OpenCV, InsightFace, Pillow, NumPy, etc.

---

## 🛡️ Security Features

### Enterprise-Safe Installation
- **No Network Scanning**: User provides all server information
- **Minimal Privileges**: Uses current user credentials where possible
- **Audit Trail**: Complete installation logging
- **Non-Destructive**: All original files preserved

### Data Protection
- **Offline Capable**: Works without internet after installation
- **Local Processing**: All face detection happens locally
- **Secure Credentials**: Supports service account authentication
- **Encrypted Storage**: Configuration can use secured credential storage

---

## 🚨 Troubleshooting

### Common Installation Issues

**"Not running as Administrator"**
```
Solution: Right-click QUICK_START.bat and select "Run as administrator"
```

**"Internet connection required"**
```
Solution: Ensure internet access during installation
Check firewall and proxy settings
```

**"Python installation failed"**
```
Solution: Download Python manually from python.org
Run installer again with -SkipPython parameter
```

**"RSAT Tools failed to install"**
```
Solution: Install manually from Windows Features:
Control Panel > Programs > Turn Windows features on or off
Enable "Remote Server Administration Tools"
```

### Post-Installation Issues

**"Configuration file not found"**
```
Solution: Re-run the configuration wizard:
.\Deploy-GallagherPhotoSync.ps1 -ConfigOnly
```

**"Python imports failing"**
```
Solution: Reinstall Python dependencies:
cd C:\GallagherPhotoSync
python -m pip install -r requirements.txt
```

**"Face detection not working"**
```
Solution: Re-download AI models:
Delete %USERPROFILE%\.insightface folder
Run face processing script to re-download models
```

---

## 📞 Support and Documentation

### Getting Help
1. **Check Logs**: `C:\GallagherPhotoSync\logs\`
2. **Run Diagnostics**: Use the installation test functions
3. **Review Configuration**: Verify `config\config.json` settings

### Additional Resources
- **Main Documentation**: README.md in installation directory
- **GitHub Repository**: https://github.com/RubenAQuispe/Gallagher_Photo_Sync
- **Configuration Examples**: config\templates\ directory

### Reporting Issues
When reporting problems, include:
- Installation log files
- Configuration file (remove sensitive data)
- Windows version and system specifications
- Error messages and steps to reproduce

---

## ⚡ Quick Reference

### Start Photo Sync
```
Double-click: "Run Gallagher Photo Sync" desktop shortcut
Or: C:\GallagherPhotoSync\run_complete_sync.ps1
```

### Edit Configuration
```
Double-click: "Photo Sync Configuration" desktop shortcut
Or: Notepad C:\GallagherPhotoSync\config\config.json
```

### View Processing Logs
```
Double-click: "Photo Sync Logs" desktop shortcut
Or: Explorer C:\GallagherPhotoSync\logs\
```

### Reinstall/Reconfigure
```
Re-run: Deploy-GallagherPhotoSync.ps1
```

---

## 🎉 Success!

After successful installation, you should have:
- ✅ Gallagher Photo Sync fully installed and configured
- ✅ Desktop shortcuts for easy access
- ✅ All dependencies installed and tested
- ✅ Configuration file ready for your environment
- ✅ AI models downloaded and cached locally

**Next Steps:**
1. Place Gallagher photos in the input directory
2. Run your first sync using the desktop shortcut
3. Review the generated audit report
4. Set up scheduled tasks if desired

The system is now ready for production use!
