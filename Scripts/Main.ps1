# File Path: ./Scripts/Main.ps1

<#
.SYNOPSIS
Main script for managing the Files.fm Uploader context menu and configuration.

.DESCRIPTION
This script allows installing or uninstalling the context menu item and launching
the configuration GUI.

.PARAMETER Install
Switch parameter. Registers the context menu item for the current user.

.PARAMETER Uninstall
Switch parameter. Unregisters the context menu item for the current user.

.PARAMETER Configure
Switch parameter. Launches the GUI for configuring Files.fm credentials and settings.

.EXAMPLE
.\Main.ps1 -Install

.EXAMPLE
.\Main.ps1 -Uninstall

.EXAMPLE
.\Main.ps1 -Configure

.NOTES
Requires the ContextMenuManager module to be available in the ../Modules directory.
Requires the UploadGui.ps1 script to be available in the current directory.
#>

[CmdletBinding(DefaultParameterSetName = "Help")]
param(
    [Parameter(ParameterSetName = "InstallAction", Mandatory = $true)]
    [switch]$Install,

    [Parameter(ParameterSetName = "UninstallAction", Mandatory = $true)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "ConfigureAction", Mandatory = $true)]
    [switch]$Configure
)

#region Setup

# Determine paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $scriptPath -Parent
$rootDir = Split-Path -Path $scriptDir -Parent
$modulesDir = Join-Path -Path $rootDir -ChildPath "Modules"
$guiScriptPath = Join-Path -Path $scriptDir -ChildPath "UploadGui.ps1"

# Add Modules path to PSModulePath for this session if not already present
if ($env:PSModulePath -notlike "*$modulesDir*") {
    $env:PSModulePath = "$modulesDir;$($env:PSModulePath)"
    Write-Verbose "Added $modulesDir to PSModulePath for this session."
}

# Function to display help
function Show-MainHelp {
    Write-Output "Files.fm Uploader Management Script"
    Write-Output "-----------------------------------"
    Write-Output "Usage:"
    Write-Output "  .\Main.ps1 -Install      # Registers the context menu item (Current User)"
    Write-Output "  .\Main.ps1 -Uninstall    # Unregisters the context menu item (Current User)"
    Write-Output "  .\Main.ps1 -Configure    # Opens the configuration GUI"
    Write-Output ""
    Write-Output "If no parameter is provided, this help message is shown."
}

#endregion

#region Main Logic

switch ($PSCmdlet.ParameterSetName) {
    "InstallAction" {
        Write-Host "Attempting to register context menu..."
        try {
            Import-Module ContextMenuManager -ErrorAction Stop
            Register-UploadContextMenu -Force # Use -Force to ensure it's set
        } catch {
            Write-Error "Failed to register context menu: $_"
            # Optional: Show message box
            try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Error registering context menu. See console.", "Install Error", "OK", "Error") } catch {}
            exit 1
        }
        exit 0
    }
    "UninstallAction" {
        Write-Host "Attempting to unregister context menu..."
        try {
            Import-Module ContextMenuManager -ErrorAction Stop
            Unregister-UploadContextMenu
        } catch {
            Write-Error "Failed to unregister context menu: $_"
            # Optional: Show message box
            try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Error unregistering context menu. See console.", "Uninstall Error", "OK", "Error") } catch {}
            exit 1
        }
        exit 0
    }
    "ConfigureAction" {
        Write-Host "Launching configuration GUI..."
        if (-not (Test-Path -Path $guiScriptPath -PathType Leaf)) {
            Write-Error "Configuration GUI script not found at: $guiScriptPath"
            # Optional: Show message box
            try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Configuration GUI script not found.", "Launch Error", "OK", "Error") } catch {}
            exit 1
        }
        try {
            # Execute the GUI script
            & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $guiScriptPath
        } catch {
            Write-Error "Failed to launch configuration GUI: $_"
            # Optional: Show message box
            try { Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show("Failed to launch configuration GUI. See console.", "Launch Error", "OK", "Error") } catch {}
            exit 1
        }
        exit 0
    }
    default {
        # Show help if no valid parameter set is matched
        Show-MainHelp
        exit 0
    }
}

#endregion

