<#
.SYNOPSIS
    Import processed photos to Active Directory as thumbnailPhoto attributes

.DESCRIPTION
    This script takes the face-processed 96x96 photos and imports them into Active Directory
    as thumbnailPhoto attributes for the corresponding users. Includes validation, batching,
    error handling, and comprehensive logging.

.PARAMETER ConfigPath
    Path to the JSON configuration file

.PARAMETER PhotoPath
    Path to processed photos directory (overrides config)

.PARAMETER LogPath
    Path to log directory (overrides config)

.PARAMETER DomainController
    Specific domain controller to target (optional)

.PARAMETER BatchSize
    Number of photos to process per batch (overrides config)

.PARAMETER WhatIf
    Show what would be done without actually updating AD

.PARAMETER BackupExisting
    Backup existing thumbnailPhoto attributes before replacement

.EXAMPLE
    .\3_ad_import.ps1
    
.EXAMPLE
    .\3_ad_import.ps1 -WhatIf -BackupExisting
    
.EXAMPLE
    .\3_ad_import.ps1 -PhotoPath "processing/cropped" -BatchSize 10 -DomainController "dc01.domain.com"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config/config.json",
    [string]$PhotoPath = "",
    [string]$LogPath = "",
    [string]$DomainController = "",
    [int]$BatchSize = 0,
    [switch]$WhatIf,
    [switch]$BackupExisting
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
        [string]$LogName = "ad_import"
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

# Get processed photo files
function Get-ProcessedPhotos {
    param(
        [string]$PhotoPath,
        [string]$LogFile
    )
    
    Write-Log -Message "Scanning for processed photos in: $PhotoPath" -LogFile $LogFile
    
    if (-not (Test-Path $PhotoPath)) {
        Write-Log -Message "Photo directory not found: $PhotoPath" -Level "ERROR" -LogFile $LogFile
        throw "Photo directory not found"
    }
    
    $photoFiles = Get-ChildItem -Path $PhotoPath -Filter "*.jpg" | Where-Object {
        $_.Length -le 102400 -and $_.Length -gt 0  # Between 0 and 100KB
    }
    
    Write-Log -Message "Found $($photoFiles.Count) processed photo files" -LogFile $LogFile
    
    return $photoFiles
}

# Validate photo file
function Test-PhotoFile {
    param(
        [System.IO.FileInfo]$PhotoFile,
        [int]$MaxSizeKB = 100
    )
    
    $validation = @{
        IsValid = $true
        Errors = @()
    }
    
    # Check file size
    $sizeKB = [math]::Round($PhotoFile.Length / 1024, 2)
    if ($sizeKB -gt $MaxSizeKB) {
        $validation.IsValid = $false
        $validation.Errors += "File size ${sizeKB}KB exceeds maximum ${MaxSizeKB}KB"
    }
    
    # Check if file is readable
    try {
        $bytes = [System.IO.File]::ReadAllBytes($PhotoFile.FullName)
        if ($bytes.Length -eq 0) {
            $validation.IsValid = $false
            $validation.Errors += "File is empty"
        }
    }
    catch {
        $validation.IsValid = $false
        $validation.Errors += "Cannot read file: $_"
    }
    
    return $validation
}

# Backup existing thumbnailPhoto
function Backup-ExistingPhoto {
    param(
        [string]$sAMAccountName,
        [byte[]]$ExistingPhoto,
        [string]$BackupPath
    )
    
    if ($ExistingPhoto -and $ExistingPhoto.Length -gt 0) {
        $backupFile = Join-Path $BackupPath "${sAMAccountName}_backup.jpg"
        try {
            [System.IO.File]::WriteAllBytes($backupFile, $ExistingPhoto)
            return $backupFile
        }
        catch {
            Write-Warning "Failed to backup existing photo for ${sAMAccountName}: $_"
            return $null
        }
    }
    
    return $null
}

# Update user photo in Active Directory
function Set-ADUserPhoto {
    param(
        [string]$sAMAccountName,
        [byte[]]$PhotoBytes,
        [string]$DomainController,
        [string]$LogFile,
        [switch]$WhatIf
    )
    
    try {
        # Check if user exists
        $adParams = @{
            Identity = $sAMAccountName
            Properties = @('thumbnailPhoto', 'DisplayName', 'Enabled')
        }
        
        if ($DomainController) {
            $adParams.Server = $DomainController
        }
        
        $user = Get-ADUser @adParams -ErrorAction Stop
        
        if (-not $user.Enabled) {
            return @{
                Success = $false
                Error = "User account is disabled"
                UserInfo = @{
                    DisplayName = $user.DisplayName
                    Enabled = $user.Enabled
                }
            }
        }
        
        $userInfo = @{
            DisplayName = $user.DisplayName
            Enabled = $user.Enabled
            HasExistingPhoto = ($user.thumbnailPhoto -and $user.thumbnailPhoto.Length -gt 0)
        }
        
        if ($WhatIf) {
            return @{
                Success = $true
                Message = "WHATIF: Would update thumbnailPhoto for $sAMAccountName"
                UserInfo = $userInfo
                WhatIf = $true
            }
        }
        
        # Update thumbnailPhoto attribute
        $setParams = @{
            Identity = $sAMAccountName
            thumbnailPhoto = $PhotoBytes
        }
        
        if ($DomainController) {
            $setParams.Server = $DomainController
        }
        
        Set-ADUser @setParams -ErrorAction Stop
        
        return @{
            Success = $true
            Message = "Successfully updated thumbnailPhoto"
            UserInfo = $userInfo
        }
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        return @{
            Success = $false
            Error = "User not found in Active Directory"
            UserInfo = $null
        }
    }
    catch {
        return @{
            Success = $false
            Error = $_.Exception.Message
            UserInfo = $null
        }
    }
}

# Process photos in batches
function Process-PhotoBatch {
    param(
        [array]$PhotoFiles,
        [string]$DomainController,
        [string]$LogFile,
        [string]$BackupPath,
        [switch]$WhatIf,
        [switch]$BackupExisting
    )
    
    $results = @()
    $batchStats = @{
        Total = $PhotoFiles.Count
        Success = 0
        Failed = 0
        UserNotFound = 0
        ValidationFailed = 0
        Disabled = 0
    }
    
    foreach ($photoFile in $PhotoFiles) {
        $sAMAccountName = $photoFile.BaseName
        $result = @{
            FileName = $photoFile.Name
            sAMAccountName = $sAMAccountName
            Success = $false
            Message = ""
            Error = ""
            FileSizeKB = [math]::Round($photoFile.Length / 1024, 2)
            BackupFile = ""
            UserInfo = $null
        }
        
        Write-Log -Message "Processing: $($photoFile.Name) -> $sAMAccountName" -LogFile $LogFile
        
        # Validate photo file
        $validation = Test-PhotoFile -PhotoFile $photoFile
        if (-not $validation.IsValid) {
            $result.Error = "Validation failed: $($validation.Errors -join ', ')"
            $batchStats.ValidationFailed++
            Write-Log -Message "✗ $($photoFile.Name): $($result.Error)" -Level "ERROR" -LogFile $LogFile
            $results += $result
            continue
        }
        
        try {
            # Read photo bytes
            $photoBytes = [System.IO.File]::ReadAllBytes($photoFile.FullName)
            
            # Backup existing photo if requested
            if ($BackupExisting -and -not $WhatIf) {
                try {
                    $existingUser = Get-ADUser -Identity $sAMAccountName -Properties thumbnailPhoto -Server $DomainController -ErrorAction SilentlyContinue
                    if ($existingUser -and $existingUser.thumbnailPhoto) {
                        $backupFile = Backup-ExistingPhoto -sAMAccountName $sAMAccountName -ExistingPhoto $existingUser.thumbnailPhoto -BackupPath $BackupPath
                        $result.BackupFile = $backupFile
                    }
                }
                catch {
                    Write-Log -Message "Warning: Could not backup existing photo for ${sAMAccountName}: $_" -Level "WARN" -LogFile $LogFile
                }
            }
            
            # Update AD user photo
            $updateResult = Set-ADUserPhoto -sAMAccountName $sAMAccountName -PhotoBytes $photoBytes -DomainController $DomainController -LogFile $LogFile -WhatIf:$WhatIf
            
            $result.Success = $updateResult.Success
            $result.Message = $updateResult.Message
            $result.Error = $updateResult.Error
            $result.UserInfo = $updateResult.UserInfo
            
            # Update statistics
            if ($updateResult.Success) {
                $batchStats.Success++
                $logLevel = if ($updateResult.WhatIf) { "INFO" } else { "SUCCESS" }
                Write-Log -Message "✓ $($photoFile.Name): $($updateResult.Message)" -Level $logLevel -LogFile $LogFile
            }
            else {
                if ($updateResult.Error -eq "User not found in Active Directory") {
                    $batchStats.UserNotFound++
                }
                elseif ($updateResult.Error -eq "User account is disabled") {
                    $batchStats.Disabled++
                }
                else {
                    $batchStats.Failed++
                }
                Write-Log -Message "✗ $($photoFile.Name): $($updateResult.Error)" -Level "ERROR" -LogFile $LogFile
            }
        }
        catch {
            $result.Error = $_.Exception.Message
            $batchStats.Failed++
            Write-Log -Message "✗ $($photoFile.Name): $_" -Level "ERROR" -LogFile $LogFile
        }
        
        $results += $result
    }
    
    return @{
        Results = $results
        Statistics = $batchStats
    }
}

# Generate comprehensive report
function Generate-Report {
    param(
        [array]$AllResults,
        [hashtable]$TotalStatistics,
        [string]$LogPath,
        [string]$LogFile,
        [bool]$WhatIfMode
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $prefix = if ($WhatIfMode) { "whatif_" } else { "" }
    
    # Detailed CSV report
    $reportPath = Join-Path $LogPath "${prefix}ad_import_report_${timestamp}.csv"
    $AllResults | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
    
    # Summary report
    $summaryPath = Join-Path $LogPath "${prefix}ad_import_summary_${timestamp}.txt"
    
    $modeText = if ($WhatIfMode) { " (WHAT-IF MODE)" } else { "" }
    
    $summary = @"
=== Active Directory Photo Import Report${modeText} ===
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

=== Summary Statistics ===
Total photos processed: $($TotalStatistics.Total)
Successfully imported: $($TotalStatistics.Success)
Failed imports: $($TotalStatistics.Failed)
Users not found: $($TotalStatistics.UserNotFound)
Validation failures: $($TotalStatistics.ValidationFailed)
Disabled accounts: $($TotalStatistics.Disabled)

=== Success Rate ===
"@

    if ($TotalStatistics.Total -gt 0) {
        $successRate = [math]::Round(($TotalStatistics.Success / $TotalStatistics.Total) * 100, 2)
        $summary += "Import success rate: $successRate%`n"
    }
    
    $summary += @"

=== File Information ===
Detailed results: $reportPath
Processing log: $LogFile

=== Next Steps ===
"@

    if ($WhatIfMode) {
        $summary += @"
1. Review the results above
2. Run without -WhatIf to perform actual imports
3. After import, run Azure AD Connect sync
"@
    }
    else {
        $summary += @"
1. Review any failed imports in the detailed report
2. Run Azure AD Connect sync: .\4_sync_trigger.ps1
3. Generate audit report: .\5_audit_report.ps1
"@
    }
    
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
    $modeText = if ($WhatIf) { " (WHAT-IF MODE)" } else { "" }
    Write-Host "`n=== Active Directory Photo Import${modeText} ===" -ForegroundColor Cyan
    Write-Host "Starting photo import process...`n" -ForegroundColor White
    
    # Load configuration
    $config = Load-Config -Path $ConfigPath
    
    # Override config with parameters if provided
    $photoPath = if ($PhotoPath) { $PhotoPath } else { $config.directories.processing_cropped }
    $logPath = if ($LogPath) { $LogPath } else { $config.directories.logs }
    $batchSizeToUse = if ($BatchSize -gt 0) { $BatchSize } else { $config.active_directory.batch_size }
    
    # Setup logging
    $logFile = Setup-Logging -LogDirectory $logPath -LogName "ad_import"
    
    Write-Log -Message "=== Starting Active Directory Photo Import${modeText} ===" -LogFile $logFile
    Write-Log -Message "Configuration: $ConfigPath" -LogFile $logFile
    Write-Log -Message "Photo directory: $photoPath" -LogFile $logFile
    Write-Log -Message "Batch size: $batchSizeToUse" -LogFile $logFile
    Write-Log -Message "Domain controller: $(if ($DomainController) { $DomainController } else { 'Auto-detect' })" -LogFile $logFile
    Write-Log -Message "Backup existing: $BackupExisting" -LogFile $logFile
    Write-Log -Message "WhatIf mode: $WhatIf" -LogFile $logFile
    
    try {
        # Get processed photos
        $photoFiles = Get-ProcessedPhotos -PhotoPath $photoPath -LogFile $logFile
        
        if ($photoFiles.Count -eq 0) {
            Write-Log -Message "No processed photos found. Nothing to import." -Level "WARN" -LogFile $logFile
            return
        }
        
        Write-Log -Message "Found $($photoFiles.Count) photos to import" -LogFile $logFile
        
        # Create backup directory if needed
        $backupPath = ""
        if ($BackupExisting) {
            $backupPath = Join-Path $logPath "photo_backups_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            if (-not $WhatIf) {
                New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
                Write-Log -Message "Created backup directory: $backupPath" -LogFile $logFile
            }
        }
        
        # Process photos in batches
        $allResults = @()
        $totalStats = @{
            Total = 0
            Success = 0
            Failed = 0
            UserNotFound = 0
            ValidationFailed = 0
            Disabled = 0
        }
        
        $batchCount = [math]::Ceiling($photoFiles.Count / $batchSizeToUse)
        
        for ($i = 0; $i -lt $photoFiles.Count; $i += $batchSizeToUse) {
            $currentBatch = $i / $batchSizeToUse + 1
            $batch = $photoFiles[$i..([math]::Min($i + $batchSizeToUse - 1, $photoFiles.Count - 1))]
            
            Write-Log -Message "Processing batch $currentBatch of $batchCount ($($batch.Count) photos)" -LogFile $logFile
            Write-Host "Processing batch $currentBatch of $batchCount..." -ForegroundColor Yellow
            
            $batchResult = Process-PhotoBatch -PhotoFiles $batch -DomainController $DomainController -LogFile $logFile -BackupPath $backupPath -WhatIf:$WhatIf -BackupExisting:$BackupExisting
            
            $allResults += $batchResult.Results
            
            # Aggregate statistics
            $totalStats.Total += $batchResult.Statistics.Total
            $totalStats.Success += $batchResult.Statistics.Success
            $totalStats.Failed += $batchResult.Statistics.Failed
            $totalStats.UserNotFound += $batchResult.Statistics.UserNotFound
            $totalStats.ValidationFailed += $batchResult.Statistics.ValidationFailed
            $totalStats.Disabled += $batchResult.Statistics.Disabled
            
            # Brief pause between batches to avoid overwhelming AD
            if ($currentBatch -lt $batchCount -and -not $WhatIf) {
                Write-Log -Message "Pausing 2 seconds between batches..." -LogFile $logFile
                Start-Sleep -Seconds 2
            }
        }
        
        # Generate reports
        $reports = Generate-Report -AllResults $allResults -TotalStatistics $totalStats -LogPath $logPath -LogFile $logFile -WhatIfMode $WhatIf
        
        # Display summary
        Write-Host "`n=== Import Complete${modeText} ===" -ForegroundColor Cyan
        Write-Host "Total photos: $($totalStats.Total)" -ForegroundColor White
        Write-Host "Successfully imported: $($totalStats.Success)" -ForegroundColor Green
        Write-Host "Failed imports: $($totalStats.Failed)" -ForegroundColor Red
        Write-Host "Users not found: $($totalStats.UserNotFound)" -ForegroundColor Yellow
        Write-Host "Validation failures: $($totalStats.ValidationFailed)" -ForegroundColor Red
        Write-Host "Disabled accounts: $($totalStats.Disabled)" -ForegroundColor Yellow
        
        if ($totalStats.Total -gt 0) {
            $successRate = [math]::Round(($totalStats.Success / $totalStats.Total) * 100, 2)
            Write-Host "Success rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
        }
        
        Write-Host "`nReports generated:" -ForegroundColor White
        Write-Host "  Detailed: $($reports.DetailedReport)" -ForegroundColor Gray
        Write-Host "  Summary: $($reports.SummaryReport)" -ForegroundColor Gray
        Write-Host "  Log: $logFile" -ForegroundColor Gray
        
        if ($BackupExisting -and -not $WhatIf) {
            Write-Host "  Backups: $backupPath" -ForegroundColor Gray
        }
        
        Write-Log -Message "=== Import process completed successfully ===" -Level "SUCCESS" -LogFile $logFile
    }
    catch {
        Write-Log -Message "Import process failed: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "`nImport process failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Execute main function
Main
