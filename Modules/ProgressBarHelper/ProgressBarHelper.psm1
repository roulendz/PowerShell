# File path: /home/ubuntu/Documents/PowerShell/Modules/ProgressBarHelper/ProgressBarHelper.psm1
<#
.SYNOPSIS
Provides a reusable function for displaying detailed progress bars during operations like file transfers.

.DESCRIPTION
This module contains the Update-DetailedProgress function, which wraps the standard Write-Progress cmdlet 
to provide a consistent and detailed progress display including percentage, speed, elapsed time, and remaining time.

.NOTES
Author: Manus
Date: 2025-05-02
Requires: PowerShell 5.1+
#> 

#Requires -Version 5.1

#region Public Functions

function Update-DetailedProgress {
    <#
    .SYNOPSIS
    Displays or updates a detailed progress bar.
    .DESCRIPTION
    Calculates and displays progress information including percentage, transfer speed, elapsed time, 
    and estimated remaining time. Wraps the standard Write-Progress cmdlet.
    .PARAMETER Activity
    A description of the activity for which progress is being reported (e.g., "Uploading file.txt").
    .PARAMETER TotalSize
    The total size of the operation (e.g., file size in bytes).
    .PARAMETER BytesProcessed
    The number of bytes processed so far.
    .PARAMETER StartTime
    A [datetime] object indicating when the operation started. Used to calculate elapsed time and speed.
    .PARAMETER ProgressId
    (Optional) An identifier for the progress bar. Use different IDs for concurrent operations. Defaults to 0.
    .EXAMPLE
    $startTime = Get-Date
    $totalSize = 100MB
    0..100 | ForEach-Object {
        Start-Sleep -Milliseconds 50
        $bytesDone = $_ * 1MB
        Update-DetailedProgress -Activity "Processing Data" -TotalSize $totalSize -BytesProcessed $bytesDone -StartTime $startTime
    }
    # Mark as complete
    Update-DetailedProgress -Activity "Processing Data" -TotalSize $totalSize -BytesProcessed $totalSize -StartTime $startTime -Completed
    .EXAMPLE
    # Using with a Stopwatch for potentially higher precision
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $totalSize = 50MB
    1..50 | ForEach-Object {
        Start-Sleep -Milliseconds 80
        $bytesDone = $_ * 1MB
        Update-DetailedProgress -Activity "Downloading Package" -TotalSize $totalSize -BytesProcessed $bytesDone -StartTime $stopwatch.Elapsed
    }
    $stopwatch.Stop()
    Update-DetailedProgress -Activity "Downloading Package" -TotalSize $totalSize -BytesProcessed $totalSize -StartTime $stopwatch.Elapsed -Completed
    .INPUTS
    None. You cannot pipe objects to this function.
    .OUTPUTS
    None. This function writes directly to the host using Write-Progress.
    .NOTES
    - To mark the progress as complete, call the function one last time with BytesProcessed equal to TotalSize and add the -Completed switch.
    - If using a [System.Diagnostics.Stopwatch] object, pass its Elapsed property ([timespan]) to the -StartTime parameter.
    #> 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Activity,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$TotalSize,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, [long]::MaxValue)]
        [long]$BytesProcessed,

        # Accept either DateTime or TimeSpan (from Stopwatch.Elapsed)
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$StartTime, # Can be [datetime] or [timespan]

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 0,

        [Parameter(Mandatory = $false)]
        [switch]$Completed
    )

    #region Input Validation and Time Calculation
    # Determine elapsed time based on input type
    [timespan]$elapsedTime
    if ($StartTime -is [datetime]) {
        $elapsedTime = (Get-Date) - $StartTime
    }
    elseif ($StartTime -is [timespan]) {
        $elapsedTime = $StartTime
    }
    else {
        Write-Error "Invalid type for StartTime. Expected [datetime] or [timespan]. Got [$($StartTime.GetType().FullName)]"
        return
    }

    # Ensure BytesProcessed does not exceed TotalSize (can happen due to timing)
    if ($BytesProcessed -gt $TotalSize) {
        $BytesProcessed = $TotalSize
    }
    #endregion

    #region Progress Calculation
    # Calculate percentage completion
    [int]$percentComplete = 0
    if ($TotalSize -gt 0) { # Avoid division by zero
        $percentComplete = [int](($BytesProcessed / $TotalSize) * 100)
    }

    # Calculate transfer speed
    [double]$bytesPerSecond = 0
    if ($elapsedTime.TotalSeconds -gt 0) { # Avoid division by zero
        $bytesPerSecond = $BytesProcessed / $elapsedTime.TotalSeconds
    }

    # Format speed string (B/s, KB/s, MB/s)
    [string]$speedString = "0 B/s" # Default for zero speed/time
    if ($bytesPerSecond -gt 0) {
        if ($bytesPerSecond -ge 1MB) {
            $speedString = "{0:N2} MB/s" -f ($bytesPerSecond / 1MB)
        } elseif ($bytesPerSecond -ge 1KB) {
            $speedString = "{0:N2} KB/s" -f ($bytesPerSecond / 1KB)
        } else {
            $speedString = "{0:N0} B/s" -f $bytesPerSecond
        }
    }

    # Calculate estimated remaining time
    [timespan]$remainingTime = [TimeSpan]::Zero
    if ($bytesPerSecond -gt 0 -and $BytesProcessed -lt $TotalSize) {
        [long]$remainingBytes = $TotalSize - $BytesProcessed
        [double]$remainingTimeSeconds = $remainingBytes / $bytesPerSecond
        # Use Ceiling to avoid showing 0 seconds remaining too early
        $remainingTime = [TimeSpan]::FromSeconds([math]::Ceiling($remainingTimeSeconds))
    }
    #endregion

    #region Display Progress
    # Construct the status string
    [string]$statusString = "$percentComplete% Complete - $speedString - Elapsed: $($elapsedTime.ToString(\'hh\:mm\:ss\'))"
    
    # Add remaining time if not completed and time is calculable
    if (-not $Completed.IsPresent -and $remainingTime.TotalSeconds -gt 0) {
        $statusString += " - Remaining: $($remainingTime.ToString(\'hh\:mm\:ss\'))"
    }
    elseif ($Completed.IsPresent) {
        $statusString = "100% Complete - Total Time: $($elapsedTime.ToString(\'hh\:mm\:ss\'))"
        $percentComplete = 100 # Ensure 100% on completion
    }

    # Prepare parameters for Write-Progress splatting
    $progressParams = @{
        Activity        = $Activity
        Status          = $statusString
        PercentComplete = $percentComplete
        Id              = $ProgressId
    }

    # Add -Completed switch if specified
    if ($Completed.IsPresent) {
        $progressParams.Add("Completed", $true)
    }

    # Call Write-Progress with calculated values
    Write-Progress @progressParams
    #endregion
}

#endregion

#region Module Export
# Export the function for use
Export-ModuleMember -Function Update-DetailedProgress
#endregion

