# File Path: ./Scripts/UploadHandler.ps1

<#
.SYNOPSIS
Handles the file/folder upload process triggered by the context menu.

.DESCRIPTION
This script is called by the context menu entry. It reads the configuration,
imports the necessary modules (FileUpload, ProgressBarHelper), and initiates the upload
to Files.fm for the selected file or folder.

.PARAMETER Path
The full path to the file or folder selected via the context menu. This is automatically
passed as '%1' by the registry command.

.NOTES
Requires the FileUpload and ProgressBarHelper modules to be available in the ../Modules directory.
Requires config.json to exist in the parent directory with Files.fm credentials and base folder hash/key.
Parallel upload for multiple selections is NOT implemented due to complexity with context menu argument passing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SelectedPath
)

#region Setup and Configuration

# Determine paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $scriptPath -Parent
$rootDir = Split-Path -Path $scriptDir -Parent
$modulesDir = Join-Path -Path $rootDir -ChildPath "Modules"
$configFilePath = Join-Path -Path $rootDir -ChildPath "config.json"

# Add Modules path to PSModulePath for this session if not already present
if ($env:PSModulePath -notlike "*$modulesDir*") {
    $env:PSModulePath = "$modulesDir;$($env:PSModulePath)"
    Write-Verbose "Added $modulesDir to PSModulePath for this session."
}

# Import required modules
try {
    Import-Module FileUpload -ErrorAction Stop -Verbose:$VerbosePreference
    # Import the user-provided ProgressBarHelper
    Import-Module ProgressBarHelper -ErrorAction Stop -Verbose:$VerbosePreference
    
    # Test progress bar - add this code here
    Write-Host "Testing basic progress bar..."
    1..10 | ForEach-Object {
        Write-Progress -Activity "Testing Basic Progress" -Status "$_% Complete" -PercentComplete ($_ * 10)
        Start-Sleep -Milliseconds 300
    }
    
    # Now test ProgressBarHelper
    Write-Host "Testing ProgressBarHelper..."
    $testStart = Get-Date
    1..10 | ForEach-Object {
        Update-DetailedProgress -Activity "Testing DetailedProgress" -TotalSize 10 -BytesProcessed $_ -StartTime $testStart -ProgressId 0
        Start-Sleep -Milliseconds 300
    }
    Update-DetailedProgress -Activity "Testing DetailedProgress" -TotalSize 10 -BytesProcessed 10 -StartTime $testStart -ProgressId 0 -Completed
} catch {
    Write-Error "Failed to import required modules (FileUpload, ProgressBarHelper) from $modulesDir. Ensure they exist and PSModulePath is correct. Error: $_"
    # Optional: Show a message box
    try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Error: Could not load required modules. See console.", "Module Load Error", "OK", "Error") } catch {}
    exit 1
}

# Load configuration
$config = $null
if (Test-Path -Path $configFilePath -PathType Leaf) {
    try {
        $configJson = Get-Content -Path $configFilePath -Raw
        $config = $configJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Error "Failed to load or parse configuration file ${configFilePath}: $_"
    }
}

if (-not $config -or -not $config.Username -or -not $config.Password -or -not $config.BaseFolderHash -or -not $config.FolderKey) {
    Write-Error "Configuration is missing or incomplete in ${configFilePath} (Username, Password, BaseFolderHash, FolderKey are required). Please run the configuration GUI (Main.ps1 -Configure)."
    # Optional: Show a message box
    try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Configuration missing or incomplete. Please run the configuration script.", "Configuration Error", "OK", "Error") } catch {}
    exit 1
}

#endregion

#region Main Upload Logic

Write-Host "Starting Files.fm upload for: ${SelectedPath}"

$item = Get-Item -Path $SelectedPath -ErrorAction SilentlyContinue

if (-not $item) {
    Write-Error "Selected path does not exist: ${SelectedPath}"
    try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Error: Selected path not found: $SelectedPath", "Upload Error", "OK", "Error") } catch {}
    exit 1
}

$uploadSuccess = $false
# Removed progressIdToComplete as ProgressBarHelper handles its own completion

try {
    if ($item.PSIsContainer) {
        # Handle Folder Upload
        $folderName = $item.Name
        # Upload-FolderToFilesFmRecursive now uses ProgressBarHelper internally
        
        # Use splatting for parameters
        $folderUploadParams = @{
            LocalFolderPath = $item.FullName
            ParentFolderHash = $config.BaseFolderHash
            Username = $config.Username
            Password = $config.Password
            ErrorAction = "Stop" # Stop if critical error like folder creation fails
            Verbose = $VerbosePreference
            # GetFileHashes = $true # Optional
        }
        $uploadResultObject = Upload-FolderToFilesFmRecursive @folderUploadParams
        Write-Verbose "[UploadHandler] Folder upload result object: $($uploadResultObject | Out-String)"
        
        # Check the Success property returned by the function
        if ($uploadResultObject.Success) {
            $uploadSuccess = $true
        } 
        # No explicit progress update needed here
        
    } else {
        # Handle File Upload
        $fileName = $item.Name
        # Upload-FileToFilesFm now uses ProgressBarHelper internally
        
        # Use splatting for parameters
        $fileUploadParams = @{
            FilePath = $item.FullName
            FolderHash = $config.BaseFolderHash
            FolderKey = $config.FolderKey # Use the configured FolderKey
            ErrorAction = "Stop"
            Verbose = $VerbosePreference
            # GetFileHash = $true # Optional
        }
        # Upload-FileToFilesFm now returns only the API result ('d' or hash) on success
        $apiResult = Upload-FileToFilesFm @fileUploadParams
        Write-Verbose "[UploadHandler] File upload API result: $apiResult"
                            
        # Check result (ApiResult contains 'd' or hash on success)
        if ($apiResult -is [string] -and $apiResult.Length -gt 0) {
            $uploadSuccess = $true
        }
        # No explicit progress update needed here
    }
} catch {
    # Error is written within the Upload functions or Invoke-FilesFmApi
    # ProgressBarHelper completion on error is handled within the Upload functions
    Write-Error "An error occurred during the upload process: $($_.Exception.Message | Out-String)"
    $uploadSuccess = $false # Ensure success is false if an exception occurred
} finally {
    # No progress completion logic needed here anymore
    Write-Verbose "[UploadHandler] Upload process finished. Success status: $uploadSuccess"
}

#endregion

#region Notification

# Simple notification (Consider using BurntToast module for better notifications)
$notifyTitle = "Files.fm Upload"
$notifyMessage = if ($uploadSuccess) { "Upload completed for: $($item.Name)" } else { "Upload failed for: $($item.Name)" }

Write-Host $notifyMessage

try {
    Add-Type -AssemblyName PresentationFramework
    $icon = if ($uploadSuccess) { [System.Windows.MessageBoxImage]::Information } else { [System.Windows.MessageBoxImage]::Error }
    # Ensure message box appears even if run hidden (might not work perfectly)
    [System.Windows.MessageBox]::Show($notifyMessage, $notifyTitle, "OK", $icon)
} catch {
    Write-Warning "Could not display GUI notification."
}

# Determine exit code
if ($uploadSuccess) {
    exit 0
} else {
    exit 1
}

#endregion