<#
.SYNOPSIS
    Extract and rename Gallagher photos from ObjectGUID.jpg to sAMAccountName.jpg

.DESCRIPTION
    This script queries Active Directory to map ObjectGUID values to sAMAccountName values,
    then renames Gallagher photo files from ObjectGUID.jpg format to sAMAccountName.jpg format.
    Original files are preserved and renamed files are moved to the processing directory.

.PARAMETER ConfigPath
    Path to the JSON configuration file

.PARAMETER GallagherPhotoPath
    Path to the Gallagher photos directory (overrides config)

.PARAMETER OutputPath
    Path to output renamed photos (overrides config)

.PARAMETER LogPath
    Path to log directory (overrides config)

.PARAMETER DomainController
    Specific domain controller to query (optional)

.PARAMETER WhatIf
    Show what would be done without actually renaming files

.EXAMPLE
    .\1_extract_and_rename.ps1
    
.EXAMPLE
    .\1_extract_and_rename.ps1 -WhatIf
    
.EXAMPLE
    .\1_extract_and_rename.ps1 -GallagherPhotoPath "\\server\share\photos" -DomainController "dc01.domain.com"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config/config.json",
    [string]$GallagherPhotoPath = "",
    [string]$OutputPath = "",
    [string]$LogPath = "",
    [string]$DomainController = "",
    [switch]$WhatIf
)

# Import required modules
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Host "✓ Active Directory module loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to import Active Directory module. Please install RSAT tools."
    exit 1
}

# Load configuration
function Load-Config {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "Configuration file not found: $Path"
        exit 1
    }
    
    try {
        $config = Get-Content $Path -Raw | ConvertFrom-Json
        Write-Host "✓ Configuration loaded from $Path" -ForegroundColor Green
        return $config
    }
    catch {
        Write-Error "Failed to parse configuration file: $_"
        exit 1
    }
}

# Setup logging
function Setup-Logging {
    param(
        [string]$LogDirectory,
        [string]$LogName = "extract_rename"
    )
    
    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logFile = Join-Path $LogDirectory "${LogName}_${timestamp}.log"
    
    return $logFile
}

# Write log entry
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with colors
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        default { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Write to log file
    if ($LogFile) {
        Add-Content -Path $LogFile -Value $logEntry
    }
}

# Get ObjectGUID to sAMAccountName mapping from Active Directory
function Get-ADUserMapping {
    param(
        [string]$SearchBase,
        [string]$DomainController,
        [string]$LogFile
    )
    
    Write-Log -Message "Querying Active Directory for user mappings..." -LogFile $LogFile
    
    $adParams = @{
        Filter = "ObjectClass -eq 'user' -and sAMAccountName -like '*'"
        Properties = @('ObjectGUID', 'sAMAccountName', 'DisplayName', 'Enabled')
    }
    
    if ($SearchBase) {
        $adParams.SearchBase = $SearchBase
    }
    
    if ($DomainController) {
        $adParams.Server = $DomainController
    }
    
    try {
        $users = Get-ADUser @adParams
        Write-Log -Message "Found $($users.Count) users in Active Directory" -LogFile $LogFile
        
        # Create mapping hashtable
        $mapping = @{}
        $stats = @{
            Total = $users.Count
            Enabled = 0
            Disabled = 0
            NoSAM = 0
        }
        
        foreach ($user in $users) {
            if ($user.sAMAccountName) {
                $guidString = $user.ObjectGUID.ToString()
                $mapping[$guidString] = @{
                    sAMAccountName = $user.sAMAccountName
                    DisplayName = $user.DisplayName
                    Enabled = $user.Enabled
                }
                
                if ($user.Enabled) {
                    $stats.Enabled++
                } else {
                    $stats.Disabled++
                }
            } else {
                $stats.NoSAM++
                Write-Log -Message "User without sAMAccountName: $($user.DisplayName) ($($user.ObjectGUID))" -Level "WARN" -LogFile $LogFile
            }
        }
        
        Write-Log -Message "Mapping statistics: Total=$($stats.Total), Enabled=$($stats.Enabled), Disabled=$($stats.Disabled), NoSAM=$($stats.NoSAM)" -LogFile $LogFile
        
        return $mapping
    }
    catch {
        Write-Log -Message "Failed to query Active Directory: $_" -Level "ERROR" -LogFile $LogFile
        throw
    }
}

# Get photo files from Gallagher directory
function Get-GallagherPhotos {
    param(
        [string]$PhotoPath,
        [string]$LogFile
    )
    
    Write-Log -Message "Scanning for Gallagher photos in: $PhotoPath" -LogFile $LogFile
    
    if (-not (Test-Path $PhotoPath)) {
        Write-Log -Message "Gallagher photo directory not found: $PhotoPath" -Level "ERROR" -LogFile $LogFile
        throw "Photo directory not found"
    }
    
    # Look for files that match ObjectGUID pattern (typically 32 characters with hyphens)
    $photoFiles = Get-ChildItem -Path $PhotoPath -Filter "*.jpg" | Where-Object {
        $_.BaseName -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    }
    
    Write-Log -Message "Found $($photoFiles.Count) potential Gallagher photo files" -LogFile $LogFile
    
    return $photoFiles
}

# Process and rename photos
function Process-Photos {
    param(
        [array]$PhotoFiles,
        [hashtable]$UserMapping,
        [string]$OutputPath,
        [string]$LogFile,
        [switch]$WhatIf
    )
    
    Write-Log -Message "Processing $($PhotoFiles.Count) photo files..." -LogFile $LogFile
    
    # Create output directory if it doesn't exist
    if (-not $WhatIf -and -not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-Log -Message "Created output directory: $OutputPath" -LogFile $LogFile
    }
    
    $stats = @{
        Total = $PhotoFiles.Count
        Matched = 0
        NotMatched = 0
        Renamed = 0
        Errors = 0
        Duplicates = 0
    }
    
    $processedFiles = @()
    $duplicateTracker = @{}
    
    foreach ($file in $PhotoFiles) {
        $result = @{
            OriginalFile = $file.Name
            ObjectGUID = $file.BaseName
            sAMAccountName = ""
            DisplayName = ""
            Enabled = $false
            Status = ""
            NewFileName = ""
            Error = ""
        }
        
        # Check if ObjectGUID exists in mapping
        if ($UserMapping.ContainsKey($file.BaseName)) {
            $userInfo = $UserMapping[$file.BaseName]
            $result.sAMAccountName = $userInfo.sAMAccountName
            $result.DisplayName = $userInfo.DisplayName
            $result.Enabled = $userInfo.Enabled
            $result.NewFileName = "$($userInfo.sAMAccountName).jpg"
            $stats.Matched++
            
            # Check for duplicate sAMAccountName
            if ($duplicateTracker.ContainsKey($userInfo.sAMAccountName)) {
                $result.Status = "DUPLICATE"
                $result.Error = "sAMAccountName already processed: $($userInfo.sAMAccountName)"
                $stats.Duplicates++
                Write-Log -Message "Duplicate sAMAccountName: $($file.Name) -> $($userInfo.sAMAccountName)" -Level "WARN" -LogFile $LogFile
            }
            else {
                $duplicateTracker[$userInfo.sAMAccountName] = $file.BaseName
                
                # Attempt to rename/copy file
                $newFilePath = Join-Path $OutputPath $result.NewFileName
                
                if ($WhatIf) {
                    $result.Status = "WOULD_RENAME"
                    Write-Log -Message "WHATIF: Would rename $($file.Name) -> $($result.NewFileName)" -LogFile $LogFile
                }
                else {
                    try {
                        Copy-Item -Path $file.FullName -Destination $newFilePath -Force
                        $result.Status = "SUCCESS"
                        $stats.Renamed++
                        Write-Log -Message "✓ Renamed: $($file.Name) -> $($result.NewFileName) ($($result.DisplayName))" -Level "SUCCESS" -LogFile $LogFile
                    }
                    catch {
                        $result.Status = "ERROR"
                        $result.Error = $_.Exception.Message
                        $stats.Errors++
                        Write-Log -Message "✗ Failed to rename $($file.Name): $_" -Level "ERROR" -LogFile $LogFile
                    }
                }
            }
        }
        else {
            $result.Status = "NOT_MATCHED"
            $result.Error = "ObjectGUID not found in Active Directory"
            $stats.NotMatched++
            Write-Log -Message "No AD match for: $($file.Name)" -Level "WARN" -LogFile $LogFile
        }
        
        $processedFiles += $result
    }
    
    return @{
        Results = $processedFiles
        Statistics = $stats
    }
}

# Generate detailed report
function Generate-Report {
    param(
        [array]$Results,
        [hashtable]$Statistics,
        [string]$LogPath,
        [string]$LogFile
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $LogPath "extract_rename_report_${timestamp}.csv"
    
    # Export detailed results to CSV
    $Results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    
    # Generate summary report
    $summaryPath = Join-Path $LogPath "extract_rename_summary_${timestamp}.txt"
    
    $summary = @"
=== Gallagher Photo Extract and Rename Report ===
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

=== Summary Statistics ===
Total photos processed: $($Statistics.Total)
Successfully matched: $($Statistics.Matched)
Not matched in AD: $($Statistics.NotMatched)
Successfully renamed: $($Statistics.Renamed)
Duplicate sAMAccountNames: $($Statistics.Duplicates)
Errors: $($Statistics.Errors)

=== Success Rate ===
"@

    if ($Statistics.Total -gt 0) {
        $matchRate = [math]::Round(($Statistics.Matched / $Statistics.Total) * 100, 2)
        $renameRate = [math]::Round(($Statistics.Renamed / $Statistics.Total) * 100, 2)
        
        $summary += @"
Match rate: $matchRate%
Rename rate: $renameRate%

"@
    }
    
    $summary += @"
=== Files for Review ===
Detailed results: $reportPath
Processing log: $LogFile

=== Next Steps ===
1. Review unmatched photos in the detailed report
2. Copy successfully renamed photos to face processing input directory
3. Run face processing script: python scripts/2_face_crop_resize.py
"@

    Set-Content -Path $summaryPath -Value $summary
    
    Write-Log -Message "Detailed report: $reportPath" -LogFile $LogFile
    Write-Log -Message "Summary report: $summaryPath" -LogFile $LogFile
    
    return @{
        DetailedReport = $reportPath
        SummaryReport = $summaryPath
    }
}

# Main execution
function Main {
    Write-Host "`n=== Gallagher Photo Extract and Rename ===" -ForegroundColor Cyan
    Write-Host "Starting photo extraction and renaming process...`n" -ForegroundColor White
    
    # Load configuration
    $config = Load-Config -Path $ConfigPath
    
    # Override config with parameters if provided
    $gallagherPath = if ($GallagherPhotoPath) { $GallagherPhotoPath } else { $config.directories.input_gallagher }
    $outputPath = if ($OutputPath) { $OutputPath } else { $config.directories.processing_renamed }
    $logPath = if ($LogPath) { $LogPath } else { $config.directories.logs }
    
    # Setup logging
    $logFile = Setup-Logging -LogDirectory $logPath -LogName "extract_rename"
    
    Write-Log -Message "=== Starting Gallagher Photo Extract and Rename ===" -LogFile $logFile
    Write-Log -Message "Configuration: $ConfigPath" -LogFile $logFile
    Write-Log -Message "Gallagher photos: $gallagherPath" -LogFile $logFile
    Write-Log -Message "Output directory: $outputPath" -LogFile $logFile
    Write-Log -Message "WhatIf mode: $WhatIf" -LogFile $logFile
    
    try {
        # Get AD user mapping
        $userMapping = Get-ADUserMapping -SearchBase $config.active_directory.search_base -DomainController $DomainController -LogFile $logFile
        
        # Get Gallagher photos
        $photoFiles = Get-GallagherPhotos -PhotoPath $gallagherPath -LogFile $logFile
        
        if ($photoFiles.Count -eq 0) {
            Write-Log -Message "No Gallagher photos found. Nothing to process." -Level "WARN" -LogFile $logFile
            return
        }
        
        # Process photos
        $result = Process-Photos -PhotoFiles $photoFiles -UserMapping $userMapping -OutputPath $outputPath -LogFile $logFile -WhatIf:$WhatIf
        
        # Generate reports
        $reports = Generate-Report -Results $result.Results -Statistics $result.Statistics -LogPath $logPath -LogFile $logFile
        
        # Display summary
        Write-Host "`n=== Processing Complete ===" -ForegroundColor Cyan
        Write-Host "Total photos: $($result.Statistics.Total)" -ForegroundColor White
        Write-Host "Successfully matched: $($result.Statistics.Matched)" -ForegroundColor Green
        Write-Host "Successfully renamed: $($result.Statistics.Renamed)" -ForegroundColor Green
        Write-Host "Not matched: $($result.Statistics.NotMatched)" -ForegroundColor Yellow
        Write-Host "Errors: $($result.Statistics.Errors)" -ForegroundColor Red
        
        if ($result.Statistics.Total -gt 0) {
            $successRate = [math]::Round(($result.Statistics.Renamed / $result.Statistics.Total) * 100, 2)
            Write-Host "Success rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
        }
        
        Write-Host "`nReports generated:" -ForegroundColor White
        Write-Host "  Detailed: $($reports.DetailedReport)" -ForegroundColor Gray
        Write-Host "  Summary: $($reports.SummaryReport)" -ForegroundColor Gray
        Write-Host "  Log: $logFile" -ForegroundColor Gray
        
        Write-Log -Message "=== Process completed successfully ===" -Level "SUCCESS" -LogFile $logFile
    }
    catch {
        Write-Log -Message "Process failed: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "`nProcess failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Execute main function
Main
