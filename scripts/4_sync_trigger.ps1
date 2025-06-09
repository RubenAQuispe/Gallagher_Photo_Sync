<#
.SYNOPSIS
    Trigger Azure AD Connect synchronization on remote server

.DESCRIPTION
    This script remotely triggers Azure AD Connect synchronization after photos have been
    imported to Active Directory. Supports both Delta and Full sync modes with monitoring
    and comprehensive logging.

.PARAMETER ConfigPath
    Path to the JSON configuration file

.PARAMETER SyncServer
    Azure AD Connect server name (overrides config)

.PARAMETER SyncType
    Type of sync: Delta (default) or Full

.PARAMETER LogPath
    Path to log directory (overrides config)

.PARAMETER Credential
    PSCredential object for remote authentication (optional)

.PARAMETER WhatIf
    Show what would be done without actually triggering sync

.PARAMETER Monitor
    Monitor sync progress and wait for completion

.PARAMETER TimeoutMinutes
    Timeout for monitoring sync completion (default: 30 minutes)

.EXAMPLE
    .\4_sync_trigger.ps1
    
.EXAMPLE
    .\4_sync_trigger.ps1 -SyncType Full -Monitor
    
.EXAMPLE
    .\4_sync_trigger.ps1 -SyncServer "aadconnect01.domain.com" -Credential (Get-Credential) -WhatIf
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config/config.json",
    [string]$SyncServer = "",
    [ValidateSet("Delta", "Full")]
    [string]$SyncType = "Delta",
    [string]$LogPath = "",
    [System.Management.Automation.PSCredential]$Credential = $null,
    [switch]$WhatIf,
    [switch]$Monitor,
    [int]$TimeoutMinutes = 30
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

# Setup logging
function Setup-Logging {
    param(
        [string]$LogDirectory,
        [string]$LogName = "aad_sync"
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

# Test remote server connectivity
function Test-RemoteConnection {
    param(
        [string]$ServerName,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$LogFile
    )
    
    Write-Log -Message "Testing connectivity to Azure AD Connect server: $ServerName" -LogFile $LogFile
    
    try {
        $testParams = @{
            ComputerName = $ServerName
            Count = 1
            Quiet = $true
        }
        
        $pingResult = Test-Connection @testParams
        
        if (-not $pingResult) {
            throw "Server is not reachable via ping"
        }
        
        # Test WinRM connectivity
        $sessionParams = @{
            ComputerName = $ServerName
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $sessionParams.Credential = $Credential
        }
        
        $testSession = New-PSSession @sessionParams
        Remove-PSSession $testSession
        
        Write-Log -Message "✓ Remote connectivity verified" -Level "SUCCESS" -LogFile $LogFile
        return $true
    }
    catch {
        Write-Log -Message "✗ Remote connectivity failed: $_" -Level "ERROR" -LogFile $LogFile
        return $false
    }
}

# Get Azure AD Connect sync status
function Get-AADSyncStatus {
    param(
        [string]$ServerName,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$LogFile
    )
    
    Write-Log -Message "Getting Azure AD Connect sync status..." -LogFile $LogFile
    
    try {
        $sessionParams = @{
            ComputerName = $ServerName
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $sessionParams.Credential = $Credential
        }
        
        $syncStatus = Invoke-Command @sessionParams -ScriptBlock {
            Import-Module ADSync -ErrorAction SilentlyContinue
            
            $status = @{
                ModuleLoaded = $false
                ConnectorStatus = @()
                LastSyncTime = $null
                SyncInProgress = $false
                Error = ""
            }
            
            try {
                # Check if ADSync module is available
                $adSyncModule = Get-Module ADSync
                if ($adSyncModule) {
                    $status.ModuleLoaded = $true
                    
                    # Get connector status
                    $connectors = Get-ADSyncConnector
                    foreach ($connector in $connectors) {
                        $status.ConnectorStatus += @{
                            Name = $connector.Name
                            Type = $connector.Type
                            State = $connector.State
                        }
                    }
                    
                    # Get last sync time
                    $syncHistory = Get-ADSyncRunProfileResult | Sort-Object StartDate -Descending | Select-Object -First 1
                    if ($syncHistory) {
                        $status.LastSyncTime = $syncHistory.StartDate
                    }
                    
                    # Check if sync is in progress
                    $runningSyncs = Get-ADSyncRunProfileResult | Where-Object { $_.Result -eq "in-progress" }
                    $status.SyncInProgress = ($runningSyncs.Count -gt 0)
                }
                else {
                    $status.Error = "ADSync module not found or not loaded"
                }
            }
            catch {
                $status.Error = $_.Exception.Message
            }
            
            return $status
        }
        
        if ($syncStatus.Error) {
            Write-Log -Message "Error getting sync status: $($syncStatus.Error)" -Level "ERROR" -LogFile $LogFile
        }
        else {
            Write-Log -Message "✓ Retrieved Azure AD Connect status" -Level "SUCCESS" -LogFile $LogFile
            if ($syncStatus.LastSyncTime) {
                Write-Log -Message "Last sync: $($syncStatus.LastSyncTime)" -LogFile $LogFile
            }
            Write-Log -Message "Sync in progress: $($syncStatus.SyncInProgress)" -LogFile $LogFile
        }
        
        return $syncStatus
    }
    catch {
        Write-Log -Message "Failed to get sync status: $_" -Level "ERROR" -LogFile $LogFile
        throw
    }
}

# Trigger Azure AD Connect sync
function Start-AADSync {
    param(
        [string]$ServerName,
        [string]$SyncType,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$LogFile,
        [switch]$WhatIf
    )
    
    Write-Log -Message "Triggering Azure AD Connect sync (Type: $SyncType)..." -LogFile $LogFile
    
    try {
        $sessionParams = @{
            ComputerName = $ServerName
            ErrorAction = 'Stop'
        }
        
        if ($Credential) {
            $sessionParams.Credential = $Credential
        }
        
        if ($WhatIf) {
            Write-Log -Message "WHATIF: Would trigger $SyncType sync on $ServerName" -LogFile $LogFile
            return @{
                Success = $true
                Message = "WHATIF: Sync would be triggered"
                WhatIf = $true
            }
        }
        
        $syncResult = Invoke-Command @sessionParams -ArgumentList $SyncType -ScriptBlock {
            param($SyncType)
            
            Import-Module ADSync -ErrorAction Stop
            
            $result = @{
                Success = $false
                Message = ""
                Error = ""
                StartTime = Get-Date
            }
            
            try {
                # Trigger the appropriate sync type
                switch ($SyncType) {
                    "Delta" {
                        $syncCommand = Start-ADSyncSyncCycle -PolicyType Delta
                        $result.Message = "Delta sync cycle started successfully"
                    }
                    "Full" {
                        $syncCommand = Start-ADSyncSyncCycle -PolicyType Initial
                        $result.Message = "Full sync cycle started successfully"
                    }
                }
                
                $result.Success = $true
            }
            catch {
                $result.Error = $_.Exception.Message
            }
            
            return $result
        }
        
        if ($syncResult.Success) {
            Write-Log -Message "✓ $($syncResult.Message)" -Level "SUCCESS" -LogFile $LogFile
        }
        else {
            Write-Log -Message "✗ Sync trigger failed: $($syncResult.Error)" -Level "ERROR" -LogFile $LogFile
        }
        
        return $syncResult
    }
    catch {
        Write-Log -Message "Failed to trigger sync: $_" -Level "ERROR" -LogFile $LogFile
        throw
    }
}

# Monitor sync progress
function Watch-SyncProgress {
    param(
        [string]$ServerName,
        [System.Management.Automation.PSCredential]$Credential,
        [int]$TimeoutMinutes,
        [string]$LogFile
    )
    
    Write-Log -Message "Monitoring sync progress (timeout: $TimeoutMinutes minutes)..." -LogFile $LogFile
    
    $startTime = Get-Date
    $timeout = $startTime.AddMinutes($TimeoutMinutes)
    $lastUpdate = $startTime
    
    try {
        do {
            Start-Sleep -Seconds 30
            
            $currentTime = Get-Date
            
            # Get current status
            $status = Get-AADSyncStatus -ServerName $ServerName -Credential $Credential -LogFile $LogFile
            
            # Log progress every 2 minutes
            if (($currentTime - $lastUpdate).TotalMinutes -ge 2) {
                if ($status.SyncInProgress) {
                    $elapsed = ($currentTime - $startTime).TotalMinutes
                    Write-Log -Message "Sync still in progress (elapsed: $([math]::Round($elapsed, 1)) minutes)" -LogFile $LogFile
                }
                $lastUpdate = $currentTime
            }
            
            # Check for timeout
            if ($currentTime -gt $timeout) {
                Write-Log -Message "Sync monitoring timed out after $TimeoutMinutes minutes" -Level "WARN" -LogFile $LogFile
                return @{
                    Completed = $false
                    TimedOut = $true
                    ElapsedMinutes = $TimeoutMinutes
                }
            }
            
        } while ($status.SyncInProgress)
        
        $totalElapsed = ($currentTime - $startTime).TotalMinutes
        Write-Log -Message "✓ Sync completed (total time: $([math]::Round($totalElapsed, 1)) minutes)" -Level "SUCCESS" -LogFile $LogFile
        
        return @{
            Completed = $true
            TimedOut = $false
            ElapsedMinutes = [math]::Round($totalElapsed, 1)
        }
    }
    catch {
        Write-Log -Message "Error monitoring sync progress: $_" -Level "ERROR" -LogFile $LogFile
        throw
    }
}

# Generate sync report
function Generate-SyncReport {
    param(
        [hashtable]$SyncResult,
        [hashtable]$MonitorResult,
        [string]$SyncType,
        [string]$ServerName,
        [string]$LogPath,
        [string]$LogFile,
        [bool]$WhatIfMode
    )
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $prefix = if ($WhatIfMode) { "whatif_" } else { "" }
    $reportPath = Join-Path $LogPath "${prefix}aad_sync_report_${timestamp}.txt"
    
    $modeText = if ($WhatIfMode) { " (WHAT-IF MODE)" } else { "" }
    
    $report = @"
=== Azure AD Connect Sync Report${modeText} ===
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

=== Sync Details ===
Server: $ServerName
Sync Type: $SyncType
Trigger Success: $($SyncResult.Success)
"@

    if ($SyncResult.Error) {
        $report += "`nError: $($SyncResult.Error)"
    }
    
    if ($SyncResult.Message) {
        $report += "`nMessage: $($SyncResult.Message)"
    }
    
    if ($MonitorResult) {
        $report += @"

=== Monitoring Results ===
Completed: $($MonitorResult.Completed)
Timed Out: $($MonitorResult.TimedOut)
Elapsed Time: $($MonitorResult.ElapsedMinutes) minutes
"@
    }
    
    $report += @"

=== Log Files ===
Detailed log: $LogFile

=== Next Steps ===
"@

    if ($WhatIfMode) {
        $report += @"
1. Review the sync trigger details above
2. Run without -WhatIf to perform actual sync
3. Monitor Azure AD Connect Health for sync results
"@
    }
    else {
        $report += @"
1. Verify sync completed successfully in Azure AD Connect
2. Check Azure AD Connect Health dashboard
3. Validate photos appear in Azure AD/Office 365
4. Run audit report: .\5_audit_report.ps1
"@
    }
    
    Set-Content -Path $reportPath -Value $report -Encoding UTF8
    
    Write-Log -Message "Sync report generated: $reportPath" -LogFile $LogFile
    
    return $reportPath
}

# Main execution
function Main {
    $modeText = if ($WhatIf) { " (WHAT-IF MODE)" } else { "" }
    Write-Host "`n=== Azure AD Connect Sync Trigger${modeText} ===" -ForegroundColor Cyan
    Write-Host "Starting sync trigger process...`n" -ForegroundColor White
    
    # Load configuration
    $config = Load-Config -Path $ConfigPath
    
    # Override config with parameters if provided
    $syncServer = if ($SyncServer) { $SyncServer } else { $config.azure_ad_connect.server }
    $logPath = if ($LogPath) { $LogPath } else { $config.directories.logs }
    
    # Validate required parameters
    if (-not $syncServer) {
        Write-Error "Azure AD Connect server not specified in config or parameters"
        exit 1
    }
    
    # Setup logging
    $logFile = Setup-Logging -LogDirectory $logPath -LogName "aad_sync"
    
    Write-Log -Message "=== Starting Azure AD Connect Sync Trigger${modeText} ===" -LogFile $logFile
    Write-Log -Message "Configuration: $ConfigPath" -LogFile $logFile
    Write-Log -Message "Sync server: $syncServer" -LogFile $logFile
    Write-Log -Message "Sync type: $SyncType" -LogFile $logFile
    Write-Log -Message "Monitor progress: $Monitor" -LogFile $logFile
    Write-Log -Message "WhatIf mode: $WhatIf" -LogFile $logFile
    
    try {
        # Test remote connectivity
        if (-not (Test-RemoteConnection -ServerName $syncServer -Credential $Credential -LogFile $logFile)) {
            throw "Cannot connect to Azure AD Connect server: $syncServer"
        }
        
        # Get initial sync status
        $initialStatus = Get-AADSyncStatus -ServerName $syncServer -Credential $Credential -LogFile $logFile
        
        if ($initialStatus.SyncInProgress -and -not $WhatIf) {
            Write-Log -Message "Warning: Sync already in progress. Waiting for completion before triggering new sync..." -Level "WARN" -LogFile $logFile
            
            $waitResult = Watch-SyncProgress -ServerName $syncServer -Credential $Credential -TimeoutMinutes $TimeoutMinutes -LogFile $logFile
            
            if (-not $waitResult.Completed) {
                Write-Log -Message "Previous sync did not complete within timeout. Proceeding anyway..." -Level "WARN" -LogFile $logFile
            }
        }
        
        # Trigger sync
        $syncResult = Start-AADSync -ServerName $syncServer -SyncType $SyncType -Credential $Credential -LogFile $logFile -WhatIf:$WhatIf
        
        $monitorResult = $null
        if ($Monitor -and $syncResult.Success -and -not $WhatIf) {
            Write-Log -Message "Monitoring sync progress..." -LogFile $logFile
            $monitorResult = Watch-SyncProgress -ServerName $syncServer -Credential $Credential -TimeoutMinutes $TimeoutMinutes -LogFile $logFile
        }
        
        # Generate report
        $reportPath = Generate-SyncReport -SyncResult $syncResult -MonitorResult $monitorResult -SyncType $SyncType -ServerName $syncServer -LogPath $logPath -LogFile $logFile -WhatIfMode $WhatIf
        
        # Display summary
        Write-Host "`n=== Sync Trigger Complete${modeText} ===" -ForegroundColor Cyan
        Write-Host "Server: $syncServer" -ForegroundColor White
        Write-Host "Sync Type: $SyncType" -ForegroundColor White
        Write-Host "Trigger Success: $($syncResult.Success)" -ForegroundColor $(if ($syncResult.Success) { "Green" } else { "Red" })
        
        if ($syncResult.Message) {
            Write-Host "Message: $($syncResult.Message)" -ForegroundColor White
        }
        
        if ($syncResult.Error) {
            Write-Host "Error: $($syncResult.Error)" -ForegroundColor Red
        }
        
        if ($monitorResult) {
            Write-Host "Monitoring: $($monitorResult.Completed)" -ForegroundColor $(if ($monitorResult.Completed) { "Green" } else { "Yellow" })
            Write-Host "Duration: $($monitorResult.ElapsedMinutes) minutes" -ForegroundColor White
        }
        
        Write-Host "`nReport generated: $reportPath" -ForegroundColor Gray
        Write-Host "Log file: $logFile" -ForegroundColor Gray
        
        Write-Log -Message "=== Sync trigger process completed successfully ===" -Level "SUCCESS" -LogFile $logFile
        
        if (-not $syncResult.Success) {
            exit 1
        }
    }
    catch {
        Write-Log -Message "Sync trigger process failed: $_" -Level "ERROR" -LogFile $logFile
        Write-Host "`nSync trigger process failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Execute main function
Main
