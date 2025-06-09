<#
.SYNOPSIS
    Complete Gallagher Photo Sync Workflow

.DESCRIPTION
    Executes the complete photo synchronization workflow from Gallagher extraction
    through Azure AD Connect sync. This is the master script that orchestrates
    all processing steps.

.PARAMETER ConfigPath
    Path to the JSON configuration file (default: config/config.json)

.PARAMETER WhatIf
    Run in test mode without making actual changes

.PARAMETER SkipSteps
    Array of step numbers to skip (1-5)

.PARAMETER StopOnError
    Stop execution if any step fails (default: true)

.PARAMETER GenerateReportOnly
    Only generate the audit report (skip processing steps)

.EXAMPLE
    .\run_complete_sync.ps1

.EXAMPLE
    .\run_complete_sync.ps1 -WhatIf

.EXAMPLE
    .\run_complete_sync.ps1 -SkipSteps @(4,5)

.EXAMPLE
    .\run_complete_sync.ps1 -GenerateReportOnly
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = "config/config.json",
    [switch]$WhatIf,
    [array]$SkipSteps = @(),
    [bool]$StopOnError = $true,
    [switch]$GenerateReportOnly
)

# Initialize workflow tracking
$WorkflowStart = Get-Date
$StepResults = @()
$OverallSuccess = $true

function Write-WorkflowLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "STEP" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry -ForegroundColor White }
    }
    
    # Also log to file
    $logFile = "logs/workflow_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    if (-not (Test-Path "logs")) { New-Item -ItemType Directory -Path "logs" -Force | Out-Null }
    Add-Content -Path $logFile -Value $logEntry
}

function Execute-Step {
    param(
        [int]$StepNumber,
        [string]$StepName,
        [string]$ScriptPath,
        [array]$Arguments = @(),
        [bool]$Required = $true
    )
    
    if ($StepNumber -in $SkipSteps) {
        Write-WorkflowLog "SKIP Step $StepNumber ($StepName) - SKIPPED" "WARN"
        return @{ Success = $true; Skipped = $true; Message = "Step skipped by user request" }
    }
    
    Write-WorkflowLog "START Step $StepNumber - $StepName" "STEP"
    $stepStart = Get-Date
    
    try {
        if ($ScriptPath -like "*.py") {
            # Python script
            $command = "python"
            $allArgs = @($ScriptPath) + $Arguments
        }
        else {
            # PowerShell script
            $command = "PowerShell.exe"
            $allArgs = @("-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments
        }
        
        Write-WorkflowLog "Executing command - $command $($allArgs -join ' ')"
        
        $process = Start-Process -FilePath $command -ArgumentList $allArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput "logs/step$StepNumber-output.log" -RedirectStandardError "logs/step$StepNumber-error.log"
        
        $stepEnd = Get-Date
        $duration = ($stepEnd - $stepStart).TotalMinutes
        
        if ($process.ExitCode -eq 0) {
            Write-WorkflowLog "SUCCESS Step $StepNumber completed successfully (Duration: $([math]::Round($duration, 1)) minutes)" "SUCCESS"
            return @{ Success = $true; Skipped = $false; Duration = $duration; ExitCode = $process.ExitCode }
        }
        else {
            $errorOutput = Get-Content "logs/step$StepNumber-error.log" -ErrorAction SilentlyContinue
            Write-WorkflowLog "ERROR Step $StepNumber failed with exit code $($process.ExitCode)" "ERROR"
            if ($errorOutput) {
                Write-WorkflowLog "Error details: $($errorOutput -join '; ')" "ERROR"
            }
            return @{ Success = $false; Skipped = $false; Duration = $duration; ExitCode = $process.ExitCode; Error = $errorOutput }
        }
    }
    catch {
        $stepEnd = Get-Date
        $duration = ($stepEnd - $stepStart).TotalMinutes
        Write-WorkflowLog "ERROR Step $StepNumber failed with exception: $_" "ERROR"
        return @{ Success = $false; Skipped = $false; Duration = $duration; Error = $_.Exception.Message }
    }
}

function Show-WorkflowSummary {
    param([array]$Results)
    
    $totalDuration = ((Get-Date) - $WorkflowStart).TotalMinutes
    
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                    WORKFLOW SUMMARY" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    Write-Host "`nExecution Details:" -ForegroundColor White
    Write-Host "  Start Time: $($WorkflowStart.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host "  End Time: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
    Write-Host "  Total Duration: $([math]::Round($totalDuration, 1)) minutes" -ForegroundColor Gray
    Write-Host "  What-If Mode: $WhatIf" -ForegroundColor Gray
    
    Write-Host "`nStep Results:" -ForegroundColor White
    foreach ($result in $Results) {
        $status = if ($result.Skipped) { "SKIPPED" }
                 elseif ($result.Success) { "SUCCESS" }
                 else { "FAILED" }
        
        $statusColor = if ($result.Skipped) { "Yellow" }
                      elseif ($result.Success) { "Green" }
                      else { "Red" }
        
        $durationText = if ($result.Duration) { " ($([math]::Round($result.Duration, 1))m)" } else { "" }
        
        Write-Host "  $($result.StepName): " -NoNewline -ForegroundColor Gray
        Write-Host $status -ForegroundColor $statusColor -NoNewline
        Write-Host $durationText -ForegroundColor Gray
        
        if ($result.Error) {
            Write-Host "    Error: $($result.Error)" -ForegroundColor Red
        }
    }
    
    $successCount = ($Results | Where-Object { $_.Success -and -not $_.Skipped }).Count
    $failedCount = ($Results | Where-Object { -not $_.Success -and -not $_.Skipped }).Count
    $skippedCount = ($Results | Where-Object { $_.Skipped }).Count
    
    Write-Host "`nOverall Statistics:" -ForegroundColor White
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failedCount" -ForegroundColor Red
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
    
    $overallStatus = if ($failedCount -eq 0) { "SUCCESS" } else { "FAILED" }
    $overallColor = if ($failedCount -eq 0) { "Green" } else { "Red" }
    
    Write-Host "`nWorkflow Status: " -NoNewline -ForegroundColor White
    Write-Host $overallStatus -ForegroundColor $overallColor
    
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

# Main execution
function Main {
    Write-Host "`n"
    Write-Host "███████╗██████╗ ██╗  ██╗ ██████╗ ████████╗ ██████╗     ███████╗██╗   ██╗███╗   ██╗ ██████╗" -ForegroundColor Cyan
    Write-Host "██╔════╝██╔══██╗██║  ██║██╔═══██╗╚══██╔══╝██╔═══██╗    ██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝" -ForegroundColor Cyan
    Write-Host "██║     ██████╔╝███████║██║   ██║   ██║   ██║   ██║    ███████╗ ╚████╔╝ ██╔██╗ ██║██║     " -ForegroundColor Cyan
    Write-Host "██║     ██╔═══╝ ██╔══██║██║   ██║   ██║   ██║   ██║    ╚════██║  ╚██╔╝  ██║╚██╗██║██║     " -ForegroundColor Cyan
    Write-Host "███████╗██║     ██║  ██║╚██████╔╝   ██║   ╚██████╔╝    ███████║   ██║   ██║ ╚████║╚██████╗" -ForegroundColor Cyan
    Write-Host "╚══════╝╚═╝     ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝     ╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "                           Gallagher Photo Sync - Complete Workflow" -ForegroundColor White
    Write-Host "                                Version 2.0.0 - Enterprise Edition" -ForegroundColor Gray
    Write-Host ""
    
    Write-WorkflowLog "START Starting Gallagher Photo Sync Complete Workflow"
    Write-WorkflowLog "Configuration: $ConfigPath"
    Write-WorkflowLog "What-If Mode: $WhatIf"
    Write-WorkflowLog "Skip Steps: $($SkipSteps -join ', ')"
    Write-WorkflowLog "Stop on Error: $StopOnError"
    
    # Verify configuration exists
    if (-not (Test-Path $ConfigPath)) {
        Write-WorkflowLog "ERROR Configuration file not found: $ConfigPath" "ERROR"
        exit 1
    }
    
    # Create necessary directories
    $directories = @("logs", "input/gallagher_photos", "processing/renamed", "processing/cropped", "processing/failed", "output/successful", "output/ad_ready")
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-WorkflowLog "CREATE Created directory: $dir"
        }
    }
    
    if ($GenerateReportOnly) {
        Write-WorkflowLog "REPORT Generating audit report only (skipping processing steps)" "WARN"
        
        $reportArgs = @("--config", $ConfigPath)
        if ($WhatIf) { $reportArgs += "-WhatIf" }
        $reportArgs += @("-ValidateAzureAD", "-IncludeDetailedLogs")
        
        $reportResult = Execute-Step -StepNumber 5 -StepName "Generate Audit Report" -ScriptPath "scripts/5_audit_report.ps1" -Arguments $reportArgs
        $StepResults += @{ StepNumber = 5; StepName = "Generate Audit Report" } + $reportResult
        
        Show-WorkflowSummary -Results $StepResults
        return
    }
    
    # Define workflow steps
    $steps = @(
        @{
            Number = 1
            Name = "Extract and Rename Photos"
            Script = "scripts/1_extract_and_rename.ps1"
            Args = @("-ConfigPath", $ConfigPath) + $(if ($WhatIf) { @("-WhatIf") } else { @() })
            Required = $true
        },
        @{
            Number = 2
            Name = "Face Processing"
            Script = "scripts/2_face_crop_resize.py"
            Args = @("--config", $ConfigPath) + $(if ($WhatIf) { @() } else { @() })  # Python script doesn't have WhatIf
            Required = $true
        },
        @{
            Number = 3
            Name = "Active Directory Import"
            Script = "scripts/3_ad_import.ps1"
            Args = @("-ConfigPath", $ConfigPath) + $(if ($WhatIf) { @("-WhatIf") } else { @() })
            Required = $true
        },
        @{
            Number = 4
            Name = "Azure AD Connect Sync"
            Script = "scripts/4_sync_trigger.ps1"
            Args = @("-ConfigPath", $ConfigPath, "-Monitor") + $(if ($WhatIf) { @("-WhatIf") } else { @() })
            Required = $false
        },
        @{
            Number = 5
            Name = "Generate Audit Report"
            Script = "scripts/5_audit_report.ps1"
            Args = @("-ConfigPath", $ConfigPath, "-ValidateAzureAD", "-IncludeDetailedLogs") + $(if ($WhatIf) { @() } else { @() })
            Required = $false
        }
    )
    
    # Execute steps
    foreach ($step in $steps) {
        $result = Execute-Step -StepNumber $step.Number -StepName $step.Name -ScriptPath $step.Script -Arguments $step.Args -Required $step.Required
        
        $StepResults += @{ StepNumber = $step.Number; StepName = $step.Name } + $result
        
        if (-not $result.Success -and -not $result.Skipped -and $step.Required -and $StopOnError) {
            Write-WorkflowLog "STOP Stopping workflow due to failed required step" "ERROR"
            $OverallSuccess = $false
            break
        }
        
        if (-not $result.Success -and -not $result.Skipped) {
            $OverallSuccess = $false
        }
        
        # Brief pause between steps
        if ($step.Number -lt 5 -and -not $result.Skipped) {
            Write-WorkflowLog "PAUSE Pausing 5 seconds before next step..."
            Start-Sleep -Seconds 5
        }
    }
    
    Write-WorkflowLog "COMPLETE Workflow execution completed"
    Show-WorkflowSummary -Results $StepResults
    
    # Exit with appropriate code
    if ($OverallSuccess) {
        Write-WorkflowLog "SUCCESS Workflow completed successfully" "SUCCESS"
        exit 0
    }
    else {
        Write-WorkflowLog "ERROR Workflow completed with errors" "ERROR"
        exit 1
    }
}

# Execute main function
Main
