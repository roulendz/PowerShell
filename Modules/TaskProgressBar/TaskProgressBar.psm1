# File Path: ./Modules/TaskProgressBar/TaskProgressBar.psm1

<#
.SYNOPSIS
Provides reusable functions for displaying progress using Write-Progress.

.DESCRIPTION
This module offers simplified wrapper functions around the standard Write-Progress cmdlet
to initialize, update, and complete progress bars for long-running tasks, including nested progress bars.

.NOTES
Designed for reuse across different PowerShell scripts and modules.
#>

#region Private State Variables

# Use script scope to maintain state for nested progress bars
$script:ProgressIdStack = [System.Collections.Generic.Stack[int]]::new()
$script:NextProgressId = 0

#endregion

#region Public Functions

<#
.SYNOPSIS
Initializes and displays a new progress bar.

.DESCRIPTION
Starts a new progress bar using Write-Progress. If called while another progress bar from this module is active,
it creates a nested progress bar.

.PARAMETER Activity
The main title or activity description for the progress bar.

.PARAMETER Status
The initial status message to display below the activity.

.PARAMETER TotalCount
(Optional) The total number of items or units of work. Used for calculating percentage if provided.

.EXAMPLE
Initialize-TaskProgress -Activity "Processing Files" -Status "Starting..." -TotalCount 100

.EXAMPLE
Initialize-TaskProgress -Activity "Downloading Data"

.RETURNS
An integer representing the ID of the newly created progress bar. This ID is needed for Update-TaskProgress and Complete-TaskProgress.
#>
function Initialize-TaskProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Activity,

        [Parameter(Mandatory=$false)]
        [string]$Status = "Initializing...",

        [Parameter(Mandatory=$false)]
        [int]$TotalCount = -1 # Use -1 to indicate no percentage calculation based on count
    )

    # Generate a unique ID for this progress bar instance
    $currentId = $script:NextProgressId++
    Write-Verbose "[TaskProgress] Initializing Progress ID: $currentId with Activity: 	'$Activity'"
    
    # Store Activity associated with this ID
    Set-Variable -Name "ProgressActivity_$currentId" -Value $Activity -Scope Script

    # Store TotalCount associated with this ID (if provided)
    if ($TotalCount -ge 0) {
        Set-Variable -Name "ProgressTotal_$currentId" -Value $TotalCount -Scope Script
    }

    # Determine ParentId if nesting
    $parentId = $null
    if ($script:ProgressIdStack.Count -gt 0) {
        $parentId = $script:ProgressIdStack.Peek()
        Write-Verbose "[TaskProgress] Nesting Progress ID: $currentId under Parent ID: $parentId"
    }

    # Push the new ID onto the stack
    $script:ProgressIdStack.Push($currentId)

    # Prepare Write-Progress parameters
    $progressParams = @{
        Activity = $Activity
        Status = $Status
        PercentComplete = if ($TotalCount -eq 0) { 100 } else { 0 } # Handle zero total count
        Id = $currentId
    }
    if ($parentId -ne $null) {
        $progressParams.ParentId = $parentId
    }

    # Display the progress bar
    Write-Progress @progressParams

    # Return the ID for future updates
    return $currentId
}

<#
.SYNOPSIS
Updates the status and percentage of an active progress bar.

.DESCRIPTION
Updates the specified progress bar with a new status message and optionally recalculates the percentage complete.

.PARAMETER ProgressId
The ID of the progress bar to update, obtained from Initialize-TaskProgress.

.PARAMETER Status
The new status message to display.

.PARAMETER CurrentItemIndex
(Optional) The index (0-based) or count of the item currently being processed. Used with TotalCount (from Initialize) to calculate percentage.

.PARAMETER PercentComplete
(Optional) Explicitly set the percentage complete (0-100). Overrides calculation based on CurrentItemIndex.

.EXAMPLE
Update-TaskProgress -ProgressId $taskId -Status "Processing file $i..." -CurrentItemIndex ($i - 1)

.EXAMPLE
Update-TaskProgress -ProgressId $downloadId -Status "Downloaded $bytes bytes" -PercentComplete $percentage

.NOTES
You must provide either CurrentItemIndex (if TotalCount was set during initialization) or PercentComplete to update the progress bar visually.
#>
function Update-TaskProgress {
    [CmdletBinding(DefaultParameterSetName = "ByIndex")]
    param(
        [Parameter(Mandatory=$true)]
        [int]$ProgressId,

        [Parameter(Mandatory=$true)]
        [string]$Status,

        [Parameter(ParameterSetName = "ByIndex", Mandatory=$false)]
        [int]$CurrentItemIndex,

        [Parameter(ParameterSetName = "ExplicitPercent", Mandatory=$true)]
        [ValidateRange(0,100)]
        [int]$PercentComplete
    )

    Write-Verbose "[TaskProgress] Updating Progress ID: $ProgressId with Status: 	'$Status'"

    # Prepare Write-Progress parameters
    $progressParams = @{
        Id = $ProgressId
        Status = $Status
    }

    # Calculate or set PercentComplete
    if ($PSCmdlet.ParameterSetName -eq "ExplicitPercent") {
        $progressParams.PercentComplete = $PercentComplete
        Write-Verbose "[TaskProgress] Using explicit PercentComplete: $($progressParams.PercentComplete)"
    } elseif ($PSCmdlet.ParameterSetName -eq "ByIndex") {
        # Check if TotalCount was stored for this ID
        $totalVarName = "ProgressTotal_$ProgressId"
        if (Get-Variable -Name $totalVarName -Scope Script -ErrorAction SilentlyContinue) {
            $totalCount = Get-Variable -Name $totalVarName -Scope Script -ValueOnly
            if ($totalCount -gt 0) {
                # Calculate percentage based on 0-based index
                $progressParams.PercentComplete = [math]::Min(100, [math]::Floor((($CurrentItemIndex + 1) / $totalCount) * 100))
                Write-Verbose "[TaskProgress] Calculated PercentComplete: $($progressParams.PercentComplete) from Index: $CurrentItemIndex / Total: $totalCount"
            } elseif ($totalCount -eq 0) {
                 $progressParams.PercentComplete = 100 # Handle zero total count
                 Write-Verbose "[TaskProgress] Setting PercentComplete to 100 (TotalCount is 0)"
            }
            # If totalCount is -1 or not set, percentage is not calculated by index
        } else {
            Write-Verbose "[TaskProgress] TotalCount variable 	'$totalVarName' not found for percentage calculation."
        }
    }
    # If PercentComplete is not set by either method, Write-Progress might not update the bar visually, only the status text.

    # Update the progress bar
    try {
        Write-Progress @progressParams -ErrorAction Stop
    } catch {
        Write-Warning "[TaskProgress] Failed to update progress bar $ProgressId: $_"
    }
}

<#
.SYNOPSIS
Completes and removes a progress bar.

.DESCRIPTION
Marks the specified progress bar as completed and removes it from the display.
If it was a nested progress bar, the parent bar becomes active again.

.PARAMETER ProgressId
The ID of the progress bar to complete, obtained from Initialize-TaskProgress.

.PARAMETER Activity
(Optional) The final activity message to display briefly upon completion. Defaults to the original activity.

.EXAMPLE
Complete-TaskProgress -ProgressId $taskId

.EXAMPLE
Complete-TaskProgress -ProgressId $taskId -Activity "File Processing Finished"
#>
function Complete-TaskProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [int]$ProgressId,

        [Parameter(Mandatory=$false)]
        [string]$Activity # Optional override for final message
    )

    Write-Verbose "[TaskProgress] Attempting to complete Progress ID: $ProgressId. Provided Activity override: 	'$Activity'"

    # Check if the ID exists on the stack before trying to peek/pop
    if ($script:ProgressIdStack.Count -eq 0) {
        Write-Warning "[TaskProgress] Progress stack is empty. Cannot complete Progress ID $ProgressId."
        return
    }
    
    # Check if the ID matches the top of the stack
    if ($script:ProgressIdStack.Peek() -ne $ProgressId) {
        Write-Warning "[TaskProgress] Progress ID $ProgressId does not match the currently active progress bar ($($script:ProgressIdStack.Peek())). Cannot complete."
        # Consider if we should attempt to remove it anyway or just return
        return
    }

    # Pop the completed ID from the stack
    $script:ProgressIdStack.Pop() | Out-Null
    Write-Verbose "[TaskProgress] Popped ID $ProgressId from stack."

    # Remove associated TotalCount variable if it exists
    $totalVarName = "ProgressTotal_$ProgressId"
    if (Get-Variable -Name $totalVarName -Scope Script -ErrorAction SilentlyContinue) {
        Remove-Variable -Name $totalVarName -Scope Script -Force
        Write-Verbose "[TaskProgress] Removed variable 	'$totalVarName'."
    }

    # Retrieve the stored Activity name
    $activityVarName = "ProgressActivity_$ProgressId"
    $storedActivity = $null
    if (Get-Variable -Name $activityVarName -Scope Script -ErrorAction SilentlyContinue) {
        $storedActivity = Get-Variable -Name $activityVarName -Scope Script -ValueOnly
        Write-Verbose "[TaskProgress] Retrieved stored activity: 	'$storedActivity' from variable 	'$activityVarName'."
    } else {
        Write-Verbose "[TaskProgress] Variable 	'$activityVarName' not found."
    }

    # Use provided Activity or fallback to stored one. Ensure it's not empty.
    $finalActivity = if ($Activity) { $Activity } else { $storedActivity }
    if ([string]::IsNullOrEmpty($finalActivity)) {
        $finalActivity = "Completed." # Provide a default non-empty string
        Write-Verbose "[TaskProgress] Final activity was empty, using default: 	'$finalActivity'."
    } else {
        Write-Verbose "[TaskProgress] Using final activity: 	'$finalActivity'."
    }

    # Remove associated Activity variable if it exists
    if (Get-Variable -Name $activityVarName -Scope Script -ErrorAction SilentlyContinue) {
        Remove-Variable -Name $activityVarName -Scope Script -Force
        Write-Verbose "[TaskProgress] Removed variable 	'$activityVarName'."
    }

    # Prepare Write-Progress parameters for completion
    # Always include Activity parameter for -Completed
    $progressParams = @{
        Id = $ProgressId
        Activity = $finalActivity
        Completed = $true
    }
    Write-Verbose "[TaskProgress] Final Write-Progress params for ID $ProgressId: $($progressParams | Out-String)"

    # Mark the progress bar as completed
    try {
        Write-Progress @progressParams -ErrorAction Stop
    } catch {
        # Catch potential errors if Write-Progress fails even with Activity set
        Write-Warning "[TaskProgress] Failed to complete progress bar $ProgressId with activity 	'$finalActivity': $_"
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function Initialize-TaskProgress, Update-TaskProgress, Complete-TaskProgress

#endregion

