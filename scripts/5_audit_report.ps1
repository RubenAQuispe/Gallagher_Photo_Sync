<#
.SYNOPSIS
    Generate comprehensive audit report for Gallagher Photo Sync process

.DESCRIPTION
    This script generates a comprehensive audit report covering the entire photo sync process
    from Gallagher extraction through Azure AD Connect sync. Includes statistics, success rates,
    and recommendations for any issues found.

.PARAMETER ConfigPath
    Path to the JSON configuration file

.PARAMETER LogPath
    Path to log directory (overrides config)

.PARAMETER OutputPath
    Path to save audit report (optional)

.PARAMETER IncludeDetailedLogs
    Include detailed log analysis in the report

.PARAMETER ValidateAzureAD
    Attempt to validate photos in Azure AD (requires Azure AD PowerShell)

.EXAMPLE
    .\5_audit_report.ps1
    
.EXAMPLE
    .\5_audit_report.ps1 -IncludeDetailedLogs -ValidateAzureAD
    
.EXAMPLE
    .\5_audit_report.ps1 -OutputPath "reports/final_audit.html"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config/config.json",
    [string]$LogPath = "",
    [string]$OutputPath = "",
    [switch]$IncludeDetailedLogs,
    [switch]$ValidateAzureAD
)

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

# Analyze directory contents
function Get-DirectoryStats {
    param(
        [string]$Path,
        [string]$Description
    )
    
    if (-not (Test-Path $Path)) {
        return @{
            Description = $Description
            Path = $Path
            Exists = $false
            FileCount = 0
            TotalSizeKB = 0
            LastModified = $null
            Files = @()
        }
    }
    
    $files = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue
    $totalSize = ($files | Measure-Object Length -Sum).Sum
    $lastModified = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    
    return @{
        Description = $Description
        Path = $Path
        Exists = $true
        FileCount = $files.Count
        TotalSizeKB = [math]::Round($totalSize / 1024, 2)
        LastModified = $lastModified
        Files = $files
    }
}

# Analyze log files
function Get-LogAnalysis {
    param(
        [string]$LogDirectory
    )
    
    if (-not (Test-Path $LogDirectory)) {
        return @{
            ExtractRename = @{ Exists = $false; LastRun = $null; Summary = "" }
            FaceProcessing = @{ Exists = $false; LastRun = $null; Summary = "" }
            ADImport = @{ Exists = $false; LastRun = $null; Summary = "" }
            AADSync = @{ Exists = $false; LastRun = $null; Summary = "" }
        }
    }
    
    $analysis = @{
        ExtractRename = @{ Exists = $false; LastRun = $null; Summary = ""; SuccessCount = 0; ErrorCount = 0 }
        FaceProcessing = @{ Exists = $false; LastRun = $null; Summary = ""; SuccessCount = 0; ErrorCount = 0 }
        ADImport = @{ Exists = $false; LastRun = $null; Summary = ""; SuccessCount = 0; ErrorCount = 0 }
        AADSync = @{ Exists = $false; LastRun = $null; Summary = ""; SuccessCount = 0; ErrorCount = 0 }
    }
    
    # Analyze extract/rename logs
    $extractLogs = Get-ChildItem -Path $LogDirectory -Filter "extract_rename_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($extractLogs) {
        $latestLog = $extractLogs[0]
        $analysis.ExtractRename.Exists = $true
        $analysis.ExtractRename.LastRun = $latestLog.LastWriteTime
        
        $content = Get-Content $latestLog.FullName -ErrorAction SilentlyContinue
        $successLines = $content | Where-Object { $_ -match "\[SUCCESS\]" }
        $errorLines = $content | Where-Object { $_ -match "\[ERROR\]" }
        
        $analysis.ExtractRename.SuccessCount = $successLines.Count
        $analysis.ExtractRename.ErrorCount = $errorLines.Count
        $analysis.ExtractRename.Summary = "Last run: $($latestLog.LastWriteTime). Success: $($successLines.Count), Errors: $($errorLines.Count)"
    }
    
    # Analyze face processing logs
    $faceProcessingLogs = Get-ChildItem -Path $LogDirectory -Filter "face_processing_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($faceProcessingLogs) {
        $latestLog = $faceProcessingLogs[0]
        $analysis.FaceProcessing.Exists = $true
        $analysis.FaceProcessing.LastRun = $latestLog.LastWriteTime
        
        $content = Get-Content $latestLog.FullName -ErrorAction SilentlyContinue
        $successLines = $content | Where-Object { $_ -match "✓.*:" }
        $errorLines = $content | Where-Object { $_ -match "✗.*:" }
        
        $analysis.FaceProcessing.SuccessCount = $successLines.Count
        $analysis.FaceProcessing.ErrorCount = $errorLines.Count
        $analysis.FaceProcessing.Summary = "Last run: $($latestLog.LastWriteTime). Success: $($successLines.Count), Errors: $($errorLines.Count)"
    }
    
    # Analyze AD import logs
    $adImportLogs = Get-ChildItem -Path $LogDirectory -Filter "ad_import_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($adImportLogs) {
        $latestLog = $adImportLogs[0]
        $analysis.ADImport.Exists = $true
        $analysis.ADImport.LastRun = $latestLog.LastWriteTime
        
        $content = Get-Content $latestLog.FullName -ErrorAction SilentlyContinue
        $successLines = $content | Where-Object { $_ -match "\[SUCCESS\]" }
        $errorLines = $content | Where-Object { $_ -match "\[ERROR\]" }
        
        $analysis.ADImport.SuccessCount = $successLines.Count
        $analysis.ADImport.ErrorCount = $errorLines.Count
        $analysis.ADImport.Summary = "Last run: $($latestLog.LastWriteTime). Success: $($successLines.Count), Errors: $($errorLines.Count)"
    }
    
    # Analyze AAD sync logs
    $aadSyncLogs = Get-ChildItem -Path $LogDirectory -Filter "aad_sync_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($aadSyncLogs) {
        $latestLog = $aadSyncLogs[0]
        $analysis.AADSync.Exists = $true
        $analysis.AADSync.LastRun = $latestLog.LastWriteTime
        
        $content = Get-Content $latestLog.FullName -ErrorAction SilentlyContinue
        $successLines = $content | Where-Object { $_ -match "\[SUCCESS\]" }
        $errorLines = $content | Where-Object { $_ -match "\[ERROR\]" }
        
        $analysis.AADSync.SuccessCount = $successLines.Count
        $analysis.AADSync.ErrorCount = $errorLines.Count
        $analysis.AADSync.Summary = "Last run: $($latestLog.LastWriteTime). Success: $($successLines.Count), Errors: $($errorLines.Count)"
    }
    
    return $analysis
}

# Get report files
function Get-ReportFiles {
    param(
        [string]$LogDirectory
    )
    
    $reports = @{
        ExtractRename = @()
        FaceProcessing = @()
        ADImport = @()
        AADSync = @()
    }
    
    if (Test-Path $LogDirectory) {
        $reports.ExtractRename = Get-ChildItem -Path $LogDirectory -Filter "*extract_rename_report_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $reports.FaceProcessing = Get-ChildItem -Path $LogDirectory -Filter "*face_processing_report_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $reports.ADImport = Get-ChildItem -Path $LogDirectory -Filter "*ad_import_report_*.csv" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
        $reports.AADSync = Get-ChildItem -Path $LogDirectory -Filter "*aad_sync_report_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    }
    
    return $reports
}

# Validate Azure AD photos (if requested)
function Test-AzureADPhotos {
    param(
        [array]$ExpectedUsers
    )
    
    try {
        # Check if Azure AD module is available
        $azModule = Get-Module -ListAvailable -Name AzureAD, AzureADPreview | Select-Object -First 1
        if (-not $azModule) {
            return @{
                Supported = $false
                Error = "Azure AD PowerShell module not installed"
                Results = @()
            }
        }
        
        Import-Module $azModule.Name -ErrorAction Stop
        
        # Check if connected to Azure AD
        try {
            $context = Get-AzureADCurrentSessionInfo -ErrorAction Stop
        }
        catch {
            return @{
                Supported = $false
                Error = "Not connected to Azure AD. Run Connect-AzureAD first."
                Results = @()
            }
        }
        
        $results = @()
        $processed = 0
        
        foreach ($user in $ExpectedUsers) {
            $processed++
            if ($processed % 10 -eq 0) {
                Write-Progress -Activity "Validating Azure AD Photos" -Status "Processing user $processed of $($ExpectedUsers.Count)" -PercentComplete (($processed / $ExpectedUsers.Count) * 100)
            }
            
            try {
                $azUser = Get-AzureADUser -ObjectId $user -ErrorAction SilentlyContinue
                if ($azUser) {
                    $photoExists = $false
                    try {
                        $photo = Get-AzureADUserThumbnailPhoto -ObjectId $user -ErrorAction SilentlyContinue
                        $photoExists = ($photo -and $photo.Length -gt 0)
                    }
                    catch {
                        $photoExists = $false
                    }
                    
                    $results += @{
                        User = $user
                        Found = $true
                        HasPhoto = $photoExists
                        Error = ""
                    }
                }
                else {
                    $results += @{
                        User = $user
                        Found = $false
                        HasPhoto = $false
                        Error = "User not found in Azure AD"
                    }
                }
            }
            catch {
                $results += @{
                    User = $user
                    Found = $false
                    HasPhoto = $false
                    Error = $_.Exception.Message
                }
            }
        }
        
        Write-Progress -Activity "Validating Azure AD Photos" -Completed
        
        return @{
            Supported = $true
            Error = ""
            Results = $results
        }
    }
    catch {
        return @{
            Supported = $false
            Error = "Failed to validate Azure AD photos: $_"
            Results = @()
        }
    }
}

# Generate comprehensive audit report
function Generate-AuditReport {
    param(
        [hashtable]$DirectoryStats,
        [hashtable]$LogAnalysis,
        [hashtable]$ReportFiles,
        [hashtable]$AzureADValidation,
        [string]$OutputPath,
        [bool]$IncludeDetailedLogs
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    # Calculate overall statistics
    $totalOriginalPhotos = $DirectoryStats.InputGallagher.FileCount
    $totalRenamed = $DirectoryStats.ProcessingRenamed.FileCount
    $totalCropped = $DirectoryStats.ProcessingCropped.FileCount
    $totalFailed = $DirectoryStats.ProcessingFailed.FileCount
    $totalSuccessful = $DirectoryStats.OutputSuccessful.FileCount
    
    $overallSuccessRate = if ($totalOriginalPhotos -gt 0) { 
        [math]::Round(($totalSuccessful / $totalOriginalPhotos) * 100, 2) 
    } else { 0 }
    
    # Generate HTML report
    $htmlReport = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gallagher Photo Sync - Audit Report</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #e0e0e0; }
        .header h1 { color: #2c3e50; margin: 0; font-size: 2.5em; }
        .header .subtitle { color: #7f8c8d; font-size: 1.1em; margin-top: 5px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 1.2em; }
        .summary-card .number { font-size: 2.5em; font-weight: bold; margin: 10px 0; }
        .summary-card .label { font-size: 0.9em; opacity: 0.9; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
        .stats-table { width: 100%; border-collapse: collapse; margin-top: 15px; }
        .stats-table th, .stats-table td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        .stats-table th { background-color: #f8f9fa; font-weight: bold; }
        .status-success { color: #27ae60; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .status-error { color: #e74c3c; font-weight: bold; }
        .progress-bar { width: 100%; height: 20px; background-color: #ecf0f1; border-radius: 10px; overflow: hidden; }
        .progress-fill { height: 100%; background: linear-gradient(90deg, #27ae60, #2ecc71); transition: width 0.3s ease; }
        .log-section { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin-top: 15px; }
        .recommendations { background-color: #fff3cd; border: 1px solid #ffeaa7; padding: 20px; border-radius: 5px; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #e0e0e0; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Gallagher Photo Sync</h1>
            <div class="subtitle">Comprehensive Audit Report</div>
            <div class="subtitle">Generated: $timestamp</div>
        </div>
        
        <div class="summary-grid">
            <div class="summary-card">
                <h3>Original Photos</h3>
                <div class="number">$totalOriginalPhotos</div>
                <div class="label">From Gallagher System</div>
            </div>
            <div class="summary-card">
                <h3>Successfully Processed</h3>
                <div class="number">$totalSuccessful</div>
                <div class="label">Ready for Azure AD</div>
            </div>
            <div class="summary-card">
                <h3>Success Rate</h3>
                <div class="number">$overallSuccessRate%</div>
                <div class="label">End-to-End Processing</div>
            </div>
            <div class="summary-card">
                <h3>Failed Processing</h3>
                <div class="number">$totalFailed</div>
                <div class="label">Requires Review</div>
            </div>
        </div>
        
        <div class="section">
            <h2>🔄 Processing Pipeline Status</h2>
            <table class="stats-table">
                <thead>
                    <tr>
                        <th>Stage</th>
                        <th>Input Count</th>
                        <th>Output Count</th>
                        <th>Success Rate</th>
                        <th>Last Run</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@

    # Add pipeline stages to table
    $stages = @(
        @{
            Name = "1. Extract & Rename"
            Input = $DirectoryStats.InputGallagher.FileCount
            Output = $DirectoryStats.ProcessingRenamed.FileCount
            LastRun = $LogAnalysis.ExtractRename.LastRun
            Status = if ($LogAnalysis.ExtractRename.Exists) { "Completed" } else { "Not Run" }
        },
        @{
            Name = "2. Face Processing"
            Input = $DirectoryStats.ProcessingRenamed.FileCount
            Output = $DirectoryStats.ProcessingCropped.FileCount
            LastRun = $LogAnalysis.FaceProcessing.LastRun
            Status = if ($LogAnalysis.FaceProcessing.Exists) { "Completed" } else { "Not Run" }
        },
        @{
            Name = "3. AD Import"
            Input = $DirectoryStats.ProcessingCropped.FileCount
            Output = $totalSuccessful
            LastRun = $LogAnalysis.ADImport.LastRun
            Status = if ($LogAnalysis.ADImport.Exists) { "Completed" } else { "Not Run" }
        },
        @{
            Name = "4. Azure AD Sync"
            Input = "N/A"
            Output = "N/A"
            LastRun = $LogAnalysis.AADSync.LastRun
            Status = if ($LogAnalysis.AADSync.Exists) { "Completed" } else { "Not Run" }
        }
    )
    
    foreach ($stage in $stages) {
        $successRate = if ($stage.Input -gt 0 -and $stage.Output -ne "N/A") {
            [math]::Round(($stage.Output / $stage.Input) * 100, 2)
        } else { "N/A" }
        
        $statusClass = switch ($stage.Status) {
            "Completed" { "status-success" }
            "Not Run" { "status-warning" }
            default { "status-error" }
        }
        
        $lastRunText = if ($stage.LastRun) { $stage.LastRun.ToString("yyyy-MM-dd HH:mm") } else { "Never" }
        
        $htmlReport += @"
                    <tr>
                        <td>$($stage.Name)</td>
                        <td>$($stage.Input)</td>
                        <td>$($stage.Output)</td>
                        <td>$successRate%</td>
                        <td>$lastRunText</td>
                        <td class="$statusClass">$($stage.Status)</td>
                    </tr>
"@
    }
    
    $htmlReport += @"
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <h2>📊 Directory Analysis</h2>
            <table class="stats-table">
                <thead>
                    <tr>
                        <th>Directory</th>
                        <th>File Count</th>
                        <th>Total Size (KB)</th>
                        <th>Last Modified</th>
                        <th>Status</th>
                    </tr>
                </thead>
                <tbody>
"@

    foreach ($dirStat in $DirectoryStats.GetEnumerator()) {
        $status = if ($dirStat.Value.Exists) { "✅ Exists" } else { "❌ Missing" }
        $statusClass = if ($dirStat.Value.Exists) { "status-success" } else { "status-error" }
        $lastModified = if ($dirStat.Value.LastModified) { 
            $dirStat.Value.LastModified.ToString("yyyy-MM-dd HH:mm") 
        } else { "N/A" }
        
        $htmlReport += @"
                    <tr>
                        <td>$($dirStat.Value.Description)</td>
                        <td>$($dirStat.Value.FileCount)</td>
                        <td>$($dirStat.Value.TotalSizeKB)</td>
                        <td>$lastModified</td>
                        <td class="$statusClass">$status</td>
                    </tr>
"@
    }
    
    $htmlReport += @"
                </tbody>
            </table>
        </div>
"@

    # Add Azure AD validation section if available
    if ($AzureADValidation.Supported) {
        $azResults = $AzureADValidation.Results
        $azUsersWithPhotos = ($azResults | Where-Object { $_.HasPhoto }).Count
        $azUsersFound = ($azResults | Where-Object { $_.Found }).Count
        $azTotalUsers = $azResults.Count
        
        $htmlReport += @"
        <div class="section">
            <h2>☁️ Azure AD Validation</h2>
            <p>Validation of photos in Azure AD/Office 365:</p>
            <table class="stats-table">
                <tr>
                    <td><strong>Total Users Checked:</strong></td>
                    <td>$azTotalUsers</td>
                </tr>
                <tr>
                    <td><strong>Users Found in Azure AD:</strong></td>
                    <td>$azUsersFound</td>
                </tr>
                <tr>
                    <td><strong>Users with Photos:</strong></td>
                    <td>$azUsersWithPhotos</td>
                </tr>
                <tr>
                    <td><strong>Photo Sync Rate:</strong></td>
                    <td>$([math]::Round(($azUsersWithPhotos / $azTotalUsers) * 100, 2))%</td>
                </tr>
            </table>
        </div>
"@
    }
    elseif ($AzureADValidation.Error) {
        $htmlReport += @"
        <div class="section">
            <h2>☁️ Azure AD Validation</h2>
            <div class="status-warning">
                <p><strong>Note:</strong> $($AzureADValidation.Error)</p>
            </div>
        </div>
"@
    }
    
    # Add recommendations section
    $recommendations = @()
    
    if ($totalFailed -gt 0) {
        $recommendations += "Review failed photos in the processing/failed directory. Common issues include poor image quality or no face detected."
    }
    
    if ($overallSuccessRate -lt 80) {
        $recommendations += "Success rate is below 80%. Consider reviewing input photo quality and face detection parameters."
    }
    
    if (-not $LogAnalysis.AADSync.Exists) {
        $recommendations += "Azure AD Connect sync has not been triggered. Run script 4_sync_trigger.ps1 to complete the process."
    }
    
    if ($DirectoryStats.ProcessingCropped.FileCount -gt 0 -and $LogAnalysis.ADImport.ErrorCount -gt 0) {
        $recommendations += "Some photos failed during AD import. Check the AD import logs for specific user account issues."
    }
    
    if ($recommendations.Count -gt 0) {
        $htmlReport += @"
        <div class="section">
            <h2>💡 Recommendations</h2>
            <div class="recommendations">
                <ul>
"@
        foreach ($rec in $recommendations) {
            $htmlReport += "                    <li>$rec</li>`n"
        }
        
        $htmlReport += @"
                </ul>
            </div>
        </div>
"@
    }
    
    # Add report files section
    $htmlReport += @"
        <div class="section">
            <h2>📄 Generated Reports</h2>
            <p>The following detailed reports were generated during processing:</p>
            <ul>
"@

    if ($ReportFiles.ExtractRename.Count -gt 0) {
        $htmlReport += "                <li><strong>Extract & Rename:</strong> $($ReportFiles.ExtractRename[0].Name) ($(($ReportFiles.ExtractRename[0].LastWriteTime).ToString('yyyy-MM-dd HH:mm')))</li>`n"
    }
    
    if ($ReportFiles.FaceProcessing.Count -gt 0) {
        $htmlReport += "                <li><strong>Face Processing:</strong> $($ReportFiles.FaceProcessing[0].Name) ($(($ReportFiles.FaceProcessing[0].LastWriteTime).ToString('yyyy-MM-dd HH:mm')))</li>`n"
    }
    
    if ($ReportFiles.ADImport.Count -gt 0) {
        $htmlReport += "                <li><strong>AD Import:</strong> $($ReportFiles.ADImport[0].Name) ($(($ReportFiles.ADImport[0].LastWriteTime).ToString('yyyy-MM-dd HH:mm')))</li>`n"
    }
    
    if ($ReportFiles.AADSync.Count -gt 0) {
        $htmlReport += "                <li><strong>Azure AD Sync:</strong> $($ReportFiles.AADSync[0].Name) ($(($ReportFiles.AADSync[0].LastWriteTime).ToString('yyyy-MM-dd HH:mm')))</li>`n"
    }
    
    $htmlReport += @"
            </ul>
        </div>
        
        <div class="footer">
            <p>Generated by Gallagher Photo Sync Audit System | $timestamp</p>
        </div>
    </div>
</body>
</html>
"@

    # Save report
    if (-not $OutputPath) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $OutputPath = "logs/audit_report_$timestamp.html"
    }
    
    Set-Content -Path $OutputPath -Value $htmlReport -Encoding UTF8
    
    return $OutputPath
}

# Main execution
function Main {
    Write-Host "`n=== Gallagher Photo Sync - Audit Report ===" -ForegroundColor Cyan
    Write-Host "Generating comprehensive audit report...`n" -ForegroundColor White
    
    # Load configuration
    $config = Load-Config -Path $ConfigPath
    
    # Override config with parameters if provided
    $logPath = if ($LogPath) { $LogPath } else { $config.directories.logs }
    
    Write-Host "📊 Analyzing directories..." -ForegroundColor Yellow
    
    # Analyze all directories
    $directoryStats = @{
        InputGallagher = Get-DirectoryStats -Path $config.directories.input_gallagher -Description "Input Photos (Gallagher)"
        ProcessingRenamed = Get-DirectoryStats -Path $config.directories.processing_renamed -Description "Renamed Photos"
        ProcessingCropped = Get-DirectoryStats -Path $config.directories.processing_cropped -Description "Face Processed Photos"
        ProcessingFailed = Get-DirectoryStats -Path $config.directories.processing_failed -Description "Failed Photos"
        OutputSuccessful = Get-DirectoryStats -Path $config.directories.output_successful -Description "Successfully Imported"
        OutputADReady = Get-DirectoryStats -Path $config.directories.output_ad_ready -Description "AD Ready Photos"
    }
    
    Write-Host "📋 Analyzing log files..." -ForegroundColor Yellow
    
    # Analyze logs
    $logAnalysis = Get-LogAnalysis -LogDirectory $logPath
    
    # Get report files
    $reportFiles = Get-ReportFiles -LogDirectory $logPath
    
    # Azure AD validation (if requested)
    $azureADValidation = @{ Supported = $false; Error = "Not requested"; Results = @() }
    if ($ValidateAzureAD) {
        Write-Host "☁️ Validating Azure AD photos..." -ForegroundColor Yellow
        
        # Get list of users from successful imports
        $successfulUsers = @()
        if ($directoryStats.OutputSuccessful.Files.Count -gt 0) {
            $successfulUsers = $directoryStats.OutputSuccessful.Files | ForEach-Object { $_.BaseName }
        }
        
        if ($successfulUsers.Count -gt 0) {
            $azureADValidation = Test-AzureADPhotos -ExpectedUsers $successfulUsers
        }
        else {
            $azureADValidation.Error = "No successful photo imports found to validate"
        }
    }
    
    Write-Host "📄 Generating audit report..." -ForegroundColor Yellow
    
    # Generate comprehensive report
    $reportPath = Generate-AuditReport -DirectoryStats $directoryStats -LogAnalysis $logAnalysis -ReportFiles $reportFiles -AzureADValidation $azureADValidation -OutputPath $OutputPath -IncludeDetailedLogs $IncludeDetailedLogs
    
    # Display summary
    Write-Host "`n=== Audit Report Generated ===" -ForegroundColor Cyan
    Write-Host "Report saved to: $reportPath" -ForegroundColor Green
    
    # Display key statistics
    $totalOriginal = $directoryStats.InputGallagher.FileCount
    $totalSuccessful = $directoryStats.OutputSuccessful.FileCount
    $successRate = if ($totalOriginal -gt 0) { [math]::Round(($totalSuccessful / $totalOriginal) * 100, 2) } else { 0 }
    
    Write-Host "`nKey Statistics:" -ForegroundColor White
    Write-Host "  Original photos: $totalOriginal" -ForegroundColor Gray
    Write-Host "  Successfully processed: $totalSuccessful" -ForegroundColor Gray
    Write-Host "  Overall success rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { "Green" } elseif ($successRate -ge 60) { "Yellow" } else { "Red" })
    
    if ($azureADValidation.Supported) {
        $azPhotos = ($azureADValidation.Results | Where-Object { $_.HasPhoto }).Count
        $azTotal = $azureADValidation.Results.Count
        Write-Host "  Photos in Azure AD: $azPhotos / $azTotal" -ForegroundColor Gray
    }
    
    Write-Host "`nOpen the HTML report in your browser to view detailed results." -ForegroundColor Cyan
    
    # Optionally open the report
    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $openChoice = Read-Host "`nWould you like to open the report now? (y/n)"
        if ($openChoice -eq 'y' -or $openChoice -eq 'Y') {
            Start-Process $reportPath
        }
    }
}

# Execute main function
Main
