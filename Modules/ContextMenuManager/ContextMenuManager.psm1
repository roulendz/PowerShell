# File Path: ./Modules/ContextMenuManager/ContextMenuManager.psm1

<#
.SYNOPSIS
Provides functions to register and unregister the Files.fm Uploader context menu item in Windows Explorer.

.DESCRIPTION
This module manages the necessary registry entries to add or remove a right-click menu option
for uploading files and folders to Files.fm using the associated handler script.

.NOTES
Operates within the HKEY_CURRENT_USER registry hive to avoid requiring administrator privileges by default.
Requires the UploadHandler.ps1 script to be present at the expected location for the context menu to function.
#>

#region Private Constants

# Using HKCU to avoid mandatory admin rights
[string]$script:baseRegPathFiles = "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell"
[string]$script:baseRegPathFolders = "Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shell"
[string]$script:menuKeyName = "UploadToFilesFM"
[string]$script:menuDisplayName = "Upload to Files.fm"

#endregion

#region Private Helper Functions

# Helper to get the full path to the handler script
function Get-HandlerScriptPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    
    # Assume the handler script is in a specific location relative to this module
    try {
        # Get the directory of the current module
        [string]$modulePath = $PSScriptRoot
        
        # Navigate up two levels (from Modules/ContextMenuManager to the root) and then into Scripts
        [string]$scriptsDir = Join-Path -Path (Split-Path -Path (Split-Path -Path $modulePath -Parent) -Parent) -ChildPath "Scripts"
        [string]$handlerScript = Join-Path -Path $scriptsDir -ChildPath "UploadHandler.ps1"

        if (-not (Test-Path -Path $handlerScript -PathType Leaf)) {
            Write-Warning "Handler script not found at expected location: $handlerScript"
            return $null
        }

<#
.SYNOPSIS
Unregisters the "Upload to Files.fm" context menu item.

.DESCRIPTION
Removes the registry keys created by Register-UploadContextMenu from HKEY_CURRENT_USER for both files and folders.

.EXAMPLE
Unregister-UploadContextMenu

.OUTPUTS
System.Boolean. Returns $true if unregistration was successful or keys were not found, $false if an error occurred during removal.
#>
function Unregister-UploadContextMenu {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    [bool]$successFiles = $false
    [bool]$successFolders = $false

    # --- Unregister for Files (*\shell) ---
    [string]$regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
    Write-Verbose "Attempting to unregister context menu for files at $regPathFiles"
    try {
        if (Test-Path -Path $regPathFiles) {
            Remove-Item -Path $regPathFiles -Recurse -Force
            Write-Verbose "Successfully removed context menu key for files."
            $successFiles = $true
        } else {
            Write-Verbose "Context menu key for files not found. Nothing to remove."
            $successFiles = $true # Not finding it is also a success state for unregistration
        }
    } catch {
        Write-Error "Failed to remove context menu key for files: $_"
        $successFiles = $false
    }

    # --- Unregister for Folders (Directory\shell) ---
    [string]$regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName
    Write-Verbose "Attempting to unregister context menu for folders at $regPathFolders"
    try {
        if (Test-Path -Path $regPathFolders) {
            Remove-Item -Path $regPathFolders -Recurse -Force
            Write-Verbose "Successfully removed context menu key for folders."
            $successFolders = $true
        } else {
            Write-Verbose "Context menu key for folders not found. Nothing to remove."
            $successFolders = $true # Not finding it is also a success state
        }
    } catch {
        Write-Error "Failed to remove context menu key for folders: $_"
        $successFolders = $false
    }

    # Return success status
    if ($successFiles -and $successFolders) {
        Write-Host "'$script:menuDisplayName' context menu unregistered successfully (Current User)."
        return $true
    } else {
        Write-Error "Failed to fully unregister context menu."
        return $false
    }
}

#endregion

#region Module Exports

# Export only the public functions
Export-ModuleMember -Function Register-UploadContextMenu, Unregister-UploadContextMenu

#endregion
        return $handlerScript
    } catch {
        Write-Error "Error determining handler script path: $_"
        return $null
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
Registers the "Upload to Files.fm" context menu item for files and folders.

.DESCRIPTION
Creates the necessary registry keys under HKEY_CURRENT_USER\Software\Classes for both files (*)
and directories (Directory) to add the context menu item.
The menu item will execute the UploadHandler.ps1 script, passing the selected item's path.

.PARAMETER Force
Switch parameter. If specified, overwrites existing registry keys if they exist.

.EXAMPLE
Register-UploadContextMenu

.EXAMPLE
Register-UploadContextMenu -Force

.OUTPUTS
System.Boolean. Returns $true if registration was successful for both file and folder entries, $false otherwise.
#>
function Register-UploadContextMenu {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    [string]$handlerScriptPath = Get-HandlerScriptPath
    if (-not $handlerScriptPath) {
        Write-Error "Cannot register context menu because the handler script path could not be determined or found."
        return $false
    }

    # Command to execute. Using pwsh.exe for PowerShell 7+ compatibility.
    # -WindowStyle Hidden prevents flashing console window.
    # -Command parameter ensures script is executed properly with path in quotes.
    # Wrap the entire command to ensure spaces are handled correctly.
    [string]$commandValue = "pwsh.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -Command `"& '$handlerScriptPath' '%1'`""

    [bool]$successFiles = $false
    [bool]$successFolders = $false

    # --- Register for Files (*\shell) ---
    [string]$regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
    [string]$commandPathFiles = Join-Path -Path $regPathFiles -ChildPath "command"

    Write-Verbose "Registering context menu for files at $regPathFiles"
    try {
        if (-not (Test-Path -Path $regPathFiles) -or $Force) {
            # Create the main menu key for files
            New-Item -Path $regPathFiles -Force | Out-Null
            Set-ItemProperty -Path $regPathFiles -Name "(Default)" -Value $script:menuDisplayName -Force | Out-Null
            # Add an icon (PowerShell icon)
            Set-ItemProperty -Path $regPathFiles -Name "Icon" -Value "pwsh.exe,0" -Force | Out-Null

            # Create the command key and set the command
            New-Item -Path $commandPathFiles -Force | Out-Null
            Set-ItemProperty -Path $commandPathFiles -Name "(Default)" -Value $commandValue -Force | Out-Null
            
            Write-Verbose "Successfully registered context menu for files."
            $successFiles = $true
        } else {
            Write-Warning "Context menu key for files already exists at $regPathFiles. Use -Force to overwrite."
            # Consider it a success if it already exists and not forcing
            $successFiles = $true 
        }
    } catch {
        Write-Error "Failed to register context menu for files: $_"
        $successFiles = $false
    }

    # --- Register for Folders (Directory\shell) ---
    [string]$regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName
    [string]$commandPathFolders = Join-Path -Path $regPathFolders -ChildPath "command"

    Write-Verbose "Registering context menu for folders at $regPathFolders"
    try {
        if (-not (Test-Path -Path $regPathFolders) -or $Force) {
            # Create the main menu key for folders
            New-Item -Path $regPathFolders -Force | Out-Null
            Set-ItemProperty -Path $regPathFolders -Name "(Default)" -Value $script:menuDisplayName -Force | Out-Null
            # Add an icon (PowerShell icon)
            Set-ItemProperty -Path $regPathFolders -Name "Icon" -Value "pwsh.exe,0" -Force | Out-Null

            # Create the command key and set the command
            New-Item -Path $commandPathFolders -Force | Out-Null
            Set-ItemProperty -Path $commandPathFolders -Name "(Default)" -Value $commandValue -Force | Out-Null
            
            Write-Verbose "Successfully registered context menu for folders."
            $successFolders = $true
        } else {
            Write-Warning "Context menu key for folders already exists at $regPathFolders. Use -Force to overwrite."
            # Consider it a success if it already exists and not forcing
            $successFolders = $true
        }
    } catch {
        Write-Error "Failed to register context menu for folders: $_"
        $successFolders = $false
    }

    # Return success status
    if ($successFiles -and $successFolders) {
        Write-Host "'$script:menuDisplayName' context menu registered successfully for files and folders (Current User)."
        return $true
    } else {
        Write-Error "Failed to fully register context menu."
        return $false
    }
}