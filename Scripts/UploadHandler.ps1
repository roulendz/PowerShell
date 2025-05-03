# File Path: ./Scripts/UploadHandler.ps1

<#
.SYNOPSIS
Handles the file/folder upload process triggered by the context menu.

.DESCRIPTION
This script is called by the context menu entry. It reads the configuration,
imports the necessary modules (FileUpload, TaskProgressBar), and initiates the upload
to Files.fm for the selected file or folder.

.PARAMETER Path
The full path to the file or folder selected via the context menu. This is automatically
passed as 	'%1' by the registry command.

.NOTES
Requires the FileUpload and TaskProgressBar modules to be available in the ../Modules directory.
Requires config.json to exist in the parent directory with Files.fm credentials and base folder hash.
Parallel upload for multiple selections is NOT implemented due to complexity with context menu argument passing.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
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
    Import-Module FileUpload -ErrorAction Stop
    Import-Module TaskProgressBar -ErrorAction Stop
}
catch {
    Write-Error "Failed to import required modules (FileUpload, TaskProgressBar) from 	${modulesDir}. Ensure they exist and PSModulePath is correct. Error: $_"
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
    }
    catch {
        Write-Error "Failed to load or parse configuration file 	${configFilePath}: $_"
    }
}

if (-not $config -or -not $config.Username -or -not $config.Password -or -not $config.BaseFolderHash -or -not $config.FolderKey) {
    Write-Error "Configuration is missing or incomplete in $configFilePath (Username, Password, BaseFolderHash, FolderKey are required). Please run the configuration GUI (Main.ps1 -Configure)."
    # Optional: Show a message box
    try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Configuration missing or incomplete. Please run the configuration script.", "Configuration Error", "OK", "Error") } catch {}
    exit 1
}

#endregion

#region Main Upload Logic

Write-Host "Starting Files.fm upload for: $SelectedPath"

$item = Get-Item -Path $SelectedPath -ErrorAction SilentlyContinue

if (-not $item) {
    Write-Error "Selected path does not exist: $SelectedPath"
    try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Error: Selected path not found: $SelectedPath", "Upload Error", "OK", "Error") } catch {}
    exit 1
}

$uploadSuccess = $false
$mainTask = $null

try {
    if ($item.PSIsContainer) {
        # Handle Folder Upload
        $folderName = $item.Name
        $mainTask = Initialize-TaskProgress -Activity "Uploading Folder: $folderName" -Status "Starting recursive upload..."
        
        # Use splatting for parameters to avoid line continuation issues
        $folderUploadParams = @{
            LocalFolderPath  = $item.FullName
            ParentFolderHash = $config.BaseFolderHash
            Username         = $config.Username
            Password         = $config.Password
            ErrorAction      = "Stop" # Stop if critical error like folder creation fails
            # GetFileHashes = $true # Optional: Uncomment if you want to track individual file hashes
        }
        $uploadResult = Upload-FolderToFilesFmRecursive @folderUploadParams
        
        # Upload-FolderToFilesFmRecursive returns $true/$false or hash list
        if ($uploadResult -is [boolean] -and $uploadResult) {
            $uploadSuccess = $true
            Update-TaskProgress -ProgressId $mainTask -Status "Folder upload completed successfully."
        }
        elseif ($uploadResult -is [array]) {
            $uploadSuccess = $true # Assume success if we got hashes back
            Update-TaskProgress -ProgressId $mainTask -Status "Folder upload completed. $($uploadResult.Count) files processed."
        }
        else {
            Update-TaskProgress -ProgressId $mainTask -Status "Folder upload failed or partially failed."
        }
        
    }
    else {
        # Handle File Upload
        $fileName = $item.Name
        $mainTask = Initialize-TaskProgress -Activity "Uploading File: $fileName" -Status "Initiating upload..." -TotalCount 1
        
        # Use splatting for parameters
        $fileUploadParams = @{
            FilePath    = $item.FullName
            FolderHash  = $config.BaseFolderHash
            FolderKey   = $config.FolderKey # Use the configured FolderKey
            ErrorAction = "Stop"
            # GetFileHash = $true # Optional
        }
        $uploadResult = Upload-FileToFilesFm @fileUploadParams
                            
        # Check result (returns 'd' or hash on success)
        if ($uploadResult -is [string] -and $uploadResult.Length -gt 0) {
            $uploadSuccess = $true
            Update-TaskProgress -ProgressId $mainTask -Status "File uploaded successfully. Result: $uploadResult" -PercentComplete 100
        }
        else {
            Update-TaskProgress -ProgressId $mainTask -Status "File upload failed. Result: $uploadResult"
        }
    }
}
catch {
    Write-Error "An error occurred during upload: $_"
    if ($mainTask -ne $null) {
        Update-TaskProgress -ProgressId $mainTask -Status "Upload failed: $($_.Exception.Message)"
    }
}
finally {
    if ($mainTask -ne $null) {
        Complete-TaskProgress -ProgressId $mainTask
    }
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
    [System.Windows.MessageBox]::Show($notifyMessage, $notifyTitle, "OK", $icon)
}
catch {
    Write-Warning "Could not display GUI notification."
}

# Keep console open briefly if run directly (won't happen via context menu)
# Start-Sleep -Seconds 5

# Determine exit code
if ($uploadSuccess) {
    exit 0
}
else {
    exit 1
}

#endregion

