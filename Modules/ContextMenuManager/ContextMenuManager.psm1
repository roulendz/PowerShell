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
$script:baseRegPathFiles = "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell"
$script:baseRegPathFolders = "Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shell"
$script:menuKeyName = "UploadToFilesFM"
$script:menuDisplayName = "Upload to Files.fm"

#endregion

#region Private Helper Functions

# Helper to get the full path to the handler script
function Get-HandlerScriptPath {
    # Assume the handler script is in a specific location relative to this module
    # Adjust this path if the final structure differs
    try {
        # Get the directory of the current module
        $modulePath = $PSScriptRoot
        # Navigate up two levels (from Modules/ContextMenuManager to the root) and then into Scripts
        $scriptsDir = Join-Path -Path (Split-Path -Path (Split-Path -Path $modulePath -Parent) -Parent) -ChildPath "Scripts"
        $handlerScript = Join-Path -Path $scriptsDir -ChildPath "UploadHandler.ps1"

        if (-not (Test-Path -Path $handlerScript -PathType Leaf)) {
            Write-Warning "Handler script not found at expected location: $handlerScript"
            return $null
        }
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

.RETURNS
$true if registration was successful for both file and folder entries, $false otherwise.
#>
function Register-UploadContextMenu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [switch]$Force
    )

    $handlerScriptPath = Get-HandlerScriptPath
    if (-not $handlerScriptPath) {
        Write-Error "Cannot register context menu because the handler script path could not be determined or found."
        return $false
    }

    # Command to execute. Use powershell.exe to ensure compatibility.
    # -WindowStyle Hidden prevents flashing console window.
    # %1 passes the selected file/folder path.
    $commandValue = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$handlerScriptPath`" `"%1`""

    $successFiles = $false
    $successFolders = $false

    # --- Register for Files (*\shell) ---
    $regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
    $commandPathFiles = Join-Path -Path $regPathFiles -ChildPath "command"

    Write-Verbose "Registering context menu for files at $regPathFiles"
    try {
        if (-not (Test-Path -Path $regPathFiles) -or $Force) {
            # Create the main menu key
            New-Item -Path $regPathFiles -Force | Out-Null
            Set-ItemProperty -Path $regPathFiles -Name "(Default)" -Value $script:menuDisplayName -Force | Out-Null
            # Optional: Add an icon (e.g., PowerShell icon or a custom one)
            # Set-ItemProperty -Path $regPathFiles -Name "Icon" -Value "powershell.exe,0" -Force | Out-Null

            # Create the command key and set the command
            New-Item -Path $commandPathFiles -Force | Out-Null
            Set-ItemProperty -Path $commandPathFiles -Name "(Default)" -Value $commandValue -Force | Out-Null
            
            Write-Verbose "Successfully registered context menu for files."
            $successFiles = $true
        } else {
            Write-Warning "Context menu key for files already exists at 	$regPathFiles. Use -Force to overwrite."
            # Consider it a success if it already exists and not forcing
            $successFiles = $true 
        }
    } catch {
        Write-Error "Failed to register context menu for files: $_"
        $successFiles = $false
    }

    # --- Register for Folders (Directory\shell) ---
    $regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName
    $commandPathFolders = Join-Path -Path $regPathFolders -ChildPath "command"

    Write-Verbose "Registering context menu for folders at $regPathFolders"
    try {
        if (-not (Test-Path -Path $regPathFolders) -or $Force) {
            # Create the main menu key
            New-Item -Path $regPathFolders -Force | Out-Null
            Set-ItemProperty -Path $regPathFolders -Name "(Default)" -Value $script:menuDisplayName -Force | Out-Null
            # Optional: Add an icon
            # Set-ItemProperty -Path $regPathFolders -Name "Icon" -Value "powershell.exe,0" -Force | Out-Null

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

    if ($successFiles -and $successFolders) {
        Write-Host "'$script:menuDisplayName' context menu registered successfully for files and folders (Current User)."
        return $true
    } else {
        Write-Error "Failed to fully register context menu."
        return $false
    }
}

<#
.SYNOPSIS
Unregisters the "Upload to Files.fm" context menu item.

.DESCRIPTION
Removes the registry keys created by Register-UploadContextMenu from HKEY_CURRENT_USER for both files and folders.

.EXAMPLE
Unregister-UploadContextMenu

.RETURNS
$true if unregistration was successful or keys were not found, $false if an error occurred during removal.
#>
function Unregister-UploadContextMenu {
    [CmdletBinding()]
    param()

    $successFiles = $false
    $successFolders = $false

    # --- Unregister for Files (*\shell) ---
    $regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
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
    $regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName
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

Export-ModuleMember -Function Register-UploadContextMenu, Unregister-UploadContextMenu

#endregion

