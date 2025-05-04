# Script: UploadHandler.ps1
# Description: Handles file/folder uploads to Files.fm triggered by the context menu.

#Requires -Version 7.2 # For Write-Progress features and potentially newer cmdlet behavior

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputPath
)

# Import the FileUpload module from the standard PowerShell Modules location
# Update the path to point to your actual module location
$modulePath = "F:\Documents\PowerShell\Modules\FileUpload\FileUpload.psm1"

# Check if the module file exists
if (-not (Test-Path $modulePath)) {
    Write-Error "FileUpload.psm1 module not found at: $modulePath"
    Write-Host "`nPlease ensure FileUpload.psm1 is in the correct location."
    Write-Host "Press Enter to close."
    Read-Host
    exit 1
}

# Import the module
Write-Verbose "Loading module from: $modulePath"
Import-Module $modulePath -Force

# Use the simplified upload function
try {
    # Call the new Upload-FileToFilesFm function which handles everything
    Upload-FileToFilesFm -Path $InputPath -Verbose
    
    Write-Host "`nPress Enter to close."
    Read-Host
}
catch {
    Write-Error "Upload failed: $_"
    Write-Host "`nPress Enter to close."
    Read-Host
    exit 1
}

exit 0