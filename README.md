# Gallagher Photo Sync

A comprehensive solution for synchronizing photos from Gallagher security systems to Active Directory and Azure AD Connect, with advanced face detection and processing capabilities.

## Overview

This system automates the complete workflow of:
1. **Extracting** photos from Gallagher and mapping ObjectGUID to sAMAccountName
2. **Processing** photos with AI-powered face detection and cropping
3. **Importing** processed photos to Active Directory as thumbnailPhoto attributes
4. **Triggering** Azure AD Connect synchronization
5. **Auditing** the entire process with comprehensive reporting

## Features

### ✨ Enhanced Face Processing
- **InsightFace AI**: State-of-the-art face detection and recognition
- **Quality Scoring**: Automatic filtering of poor-quality faces
- **Smart Cropping**: Head and shoulders crop with intelligent padding
- **Size Optimization**: Automatic JPEG quality adjustment to meet size constraints
- **Batch Processing**: Efficient handling of thousands of photos

### 🔧 Active Directory Integration
- **PowerShell Automation**: Robust AD querying and photo import
- **Batch Operations**: Process photos in configurable batches
- **Error Handling**: Comprehensive error tracking and recovery
- **Backup Support**: Optional backup of existing photos before replacement

### 📊 Monitoring & Reporting
- **Real-time Progress**: Progress bars and status updates
- **Comprehensive Logging**: Detailed logs with rotation
- **HTML Audit Reports**: Beautiful, interactive audit reports
- **Statistics Tracking**: Success rates, error analysis, and recommendations

### 🚀 Enterprise Ready
- **Configuration Management**: JSON-based configuration
- **Remote Operations**: Azure AD Connect remote triggering
- **Non-destructive**: Original files preserved throughout process
- **Scalable**: Designed for enterprise environments with thousands of users

## Project Structure

```
Gallagher_Photo_Sync/
├── config/
│   └── config.json                 # Main configuration file
├── logs/                           # Generated logs and reports
├── input/
│   └── gallagher_photos/           # Original Gallagher photos (ObjectGUID.jpg)
├── processing/
│   ├── renamed/                    # ObjectGUID → sAMAccountName renamed files
│   ├── cropped/                    # Face-processed 96x96 photos
│   └── failed/                     # Photos that failed processing
├── output/
│   ├── successful/                 # Successfully imported photos
│   └── ad_ready/                   # Final photos ready for AD import
├── scripts/
│   ├── 1_extract_and_rename.ps1    # Step 1: Extract and rename photos
│   ├── 2_face_crop_resize.py       # Step 2: Face detection and processing
│   ├── 3_ad_import.ps1             # Step 3: Import to Active Directory
│   ├── 4_sync_trigger.ps1          # Step 4: Trigger Azure AD Connect sync
│   └── 5_audit_report.ps1          # Step 5: Generate audit report
├── utils/                          # Utility functions
├── requirements.txt                # Python dependencies
└── README.md                       # This file
```

## Prerequisites

### System Requirements
- **Windows Server** with PowerShell 5.1 or later
- **Python 3.8+** with pip
- **Active Directory PowerShell Module** (RSAT Tools)
- **Azure AD Connect** (on target server)

### Required Permissions
- **Active Directory**: Read/Write access to user objects and thumbnailPhoto attribute
- **Azure AD Connect Server**: Remote PowerShell access
- **File System**: Read access to Gallagher photo share, write access to processing directories

### Network Access
- Connectivity to domain controllers
- Access to Azure AD Connect server
- Access to Gallagher photo file share

## Installation

### 1. Clone or Download the Project
```bash
git clone https://github.com/your-org/gallagher-photo-sync.git
cd gallagher-photo-sync
```

### 2. Install Python Dependencies
```bash
pip install -r requirements.txt
```

### 3. Configure the System
Edit `config/config.json` with your environment details:

```json
{
  "active_directory": {
    "server": "your-dc-server.domain.com",
    "search_base": "DC=domain,DC=com"
  },
  "azure_ad_connect": {
    "server": "your-aad-connect-server.domain.com"
  }
}
```

### 4. Verify Prerequisites
```powershell
# Test AD Module
Import-Module ActiveDirectory
Get-ADUser -Filter "Name -like 'test*'" -Properties thumbnailPhoto

# Test Azure AD Connect Access
Test-NetConnection your-aad-connect-server.domain.com -Port 5985
```

## Usage

### Quick Start (Complete Process)
```powershell
# Step 1: Extract and rename photos
.\scripts\1_extract_and_rename.ps1

# Step 2: Process faces
python scripts\2_face_crop_resize.py

# Step 3: Import to AD
.\scripts\3_ad_import.ps1

# Step 4: Sync to Azure AD
.\scripts\4_sync_trigger.ps1 -Monitor

# Step 5: Generate audit report
.\scripts\5_audit_report.ps1 -ValidateAzureAD
```

### Step-by-Step Execution

#### Step 1: Extract and Rename Photos
```powershell
# Basic execution
.\scripts\1_extract_and_rename.ps1

# With custom parameters
.\scripts\1_extract_and_rename.ps1 -GallagherPhotoPath "\\server\photos" -WhatIf

# Override domain controller
.\scripts\1_extract_and_rename.ps1 -DomainController "dc01.domain.com"
```

#### Step 2: Face Processing
```python
# Basic execution
python scripts/2_face_crop_resize.py

# With verbose logging
python scripts/2_face_crop_resize.py --verbose

# Custom configuration
python scripts/2_face_crop_resize.py --config "config/custom_config.json"
```

#### Step 3: Active Directory Import
```powershell
# Basic import
.\scripts\3_ad_import.ps1

# Test run (no actual changes)
.\scripts\3_ad_import.ps1 -WhatIf

# With existing photo backup
.\scripts\3_ad_import.ps1 -BackupExisting

# Custom batch size
.\scripts\3_ad_import.ps1 -BatchSize 10
```

#### Step 4: Azure AD Connect Sync
```powershell
# Delta sync (default)
.\scripts\4_sync_trigger.ps1

# Full sync with monitoring
.\scripts\4_sync_trigger.ps1 -SyncType Full -Monitor

# Custom server and credentials
.\scripts\4_sync_trigger.ps1 -SyncServer "aadconnect01.domain.com" -Credential (Get-Credential)
```

#### Step 5: Audit Report
```powershell
# Basic audit report
.\scripts\5_audit_report.ps1

# Comprehensive report with Azure AD validation
.\scripts\5_audit_report.ps1 -ValidateAzureAD -IncludeDetailedLogs

# Custom output location
.\scripts\5_audit_report.ps1 -OutputPath "reports/final_audit.html"
```

## Configuration Options

### Main Configuration (`config/config.json`)

#### Face Processing Settings
```json
{
  "face_processing": {
    "target_size": [96, 96],
    "max_file_size_kb": 100,
    "min_face_confidence": 0.5,
    "padding_width_factor": 0.6,
    "padding_height_factor": 1.5,
    "batch_size": 50
  }
}
```

#### Active Directory Settings
```json
{
  "active_directory": {
    "server": "dc01.domain.com",
    "search_base": "DC=domain,DC=com",
    "batch_size": 25
  }
}
```

#### Logging Configuration
```json
{
  "logging": {
    "level": "INFO",
    "max_file_size_mb": 10,
    "backup_count": 5
  }
}
```

## Troubleshooting

### Common Issues

#### Face Detection Problems
```bash
# Issue: No faces detected
# Solution: Lower confidence threshold
python scripts/2_face_crop_resize.py --config config/low_confidence_config.json

# Issue: Poor quality faces
# Solution: Review failed photos in processing/failed directory
```

#### Active Directory Issues
```powershell
# Issue: Permission denied
# Solution: Verify AD permissions
Get-ADUser $env:USERNAME -Properties MemberOf

# Issue: User not found
# Solution: Check search base configuration
Get-ADUser -Filter * -SearchBase "DC=domain,DC=com" | Measure-Object
```

#### Azure AD Connect Issues
```powershell
# Issue: Sync not triggered
# Solution: Check connectivity and credentials
Test-NetConnection aadconnect-server.domain.com -Port 5985
Enter-PSSession -ComputerName aadconnect-server.domain.com
```

### Log Analysis

#### Check Processing Logs
```powershell
# View latest face processing log
Get-Content (Get-ChildItem logs\face_processing_*.log | Sort LastWriteTime -Desc)[0].FullName -Tail 50

# Search for errors
Select-String -Path "logs\*.log" -Pattern "ERROR" | Select-Object -Last 10
```

#### Performance Monitoring
```powershell
# Check processing times
Select-String -Path "logs\face_processing_*.log" -Pattern "processing time" | Measure-Object
```

## Performance Optimization

### For Large Deployments (1000+ Photos)

#### Face Processing Optimization
```json
{
  "face_processing": {
    "batch_size": 100,
    "intermediate_size": [128, 128]
  },
  "insightface": {
    "providers": ["CUDAExecutionProvider", "CPUExecutionProvider"]
  }
}
```

#### Active Directory Optimization
```json
{
  "active_directory": {
    "batch_size": 50
  }
}
```

### Hardware Recommendations
- **CPU**: Multi-core processor (8+ cores recommended)
- **RAM**: 16GB+ for large photo processing
- **Storage**: SSD for temp processing directories
- **GPU**: Optional CUDA-compatible GPU for faster face detection

## Security Considerations

### Data Protection
- **Original files preserved**: All processing is non-destructive
- **Audit trails**: Comprehensive logging of all operations
- **Backup support**: Optional backup of existing AD photos
- **Secure credentials**: Support for credential objects and secure storage

### Network Security
- **Encrypted connections**: PowerShell remoting uses WinRM with encryption
- **Minimal permissions**: Scripts use least-privilege access patterns
- **Audit logging**: All AD modifications are logged

## Integration Examples

### Scheduled Automation
```powershell
# Create scheduled task for weekly photo sync
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\GallagherPhotoSync\run_complete_sync.ps1"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "GallagherPhotoSync"
```

### Email Notifications
```powershell
# Add to end of processing scripts
if ($totalErrors -gt 0) {
    Send-MailMessage -To "admin@domain.com" -From "photosync@domain.com" -Subject "Photo Sync Errors" -Body "Check logs for details"
}
```

### SharePoint Integration
```powershell
# Custom script to upload reports to SharePoint
.\scripts\5_audit_report.ps1
$reportPath = "logs\audit_report_*.html"
# Upload to SharePoint using PnP PowerShell
```

## API Reference

### Python Script Parameters
```python
# 2_face_crop_resize.py
python scripts/2_face_crop_resize.py [options]
  --config CONFIG_PATH        Path to configuration file
  --verbose, -v              Enable verbose logging
```

### PowerShell Script Parameters
```powershell
# Common parameters across scripts
-ConfigPath              # Path to config.json
-WhatIf                  # Test mode (no actual changes)
-LogPath                 # Override log directory
-Verbose                 # Enable verbose output
```

## Contributing

### Development Setup
```bash
# Install development dependencies
pip install -r requirements.txt
pip install pytest black flake8

# Run tests
python -m pytest tests/

# Format code
black scripts/
flake8 scripts/
```

### Adding New Features
1. Update configuration schema in `config/config.json`
2. Add logging and error handling
3. Update audit report generation
4. Add tests and documentation
5. Update README.md

## Support

### Getting Help
- **Check logs**: All operations generate detailed logs in the `logs/` directory
- **Run audit report**: Use `5_audit_report.ps1` for comprehensive system analysis
- **Use WhatIf mode**: Test all operations with `-WhatIf` parameter before production runs

### Reporting Issues
When reporting issues, please include:
- Configuration file (with sensitive data removed)
- Relevant log files
- System specifications
- Steps to reproduce

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Changelog

### Version 2.0.0 (Current)
- ✨ Enhanced face processing with InsightFace AI
- 📊 Comprehensive audit reporting with HTML output
- 🔧 Improved error handling and recovery
- 🚀 Batch processing for enterprise scale
- 💾 Configuration-driven operation
- 📝 Detailed logging and monitoring

### Version 1.0.0 (Original)
- Basic face cropping with OpenCV
- Simple PowerShell AD integration
- Manual processing workflow

---

**Note**: This system is designed for enterprise environments. Please test thoroughly in a development environment before deploying to production.
