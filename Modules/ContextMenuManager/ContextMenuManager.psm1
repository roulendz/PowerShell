# File Path: ./Modules/ContextMenuManager/ContextMenuManager.psm1

<#
.SYNOPSIS
Manages the Windows Explorer context menu for uploading to Files.fm.
#>

#region Private Constants
[string]$script:baseRegPathFiles = "Registry::HKEY_CURRENT_USER\Software\Classes\*\shell"
[string]$script:baseRegPathFolders = "Registry::HKEY_CURRENT_USER\Software\Classes\Directory\shell"
[string]$script:menuKeyName = "UploadToFilesFM"
[string]$script:menuDisplayName = "Upload to Files.fm"
#endregion

#region Private Helper Functions
function Get-HandlerScriptPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    try {
        $modulePath = $PSScriptRoot
        $scriptsDir = Join-Path -Path (Split-Path -Path (Split-Path -Path $modulePath -Parent) -Parent) -ChildPath "Scripts"
        $handlerScript = Join-Path -Path $scriptsDir -ChildPath "UploadHandler.ps1"

        if (-not (Test-Path -Path $handlerScript -PathType Leaf)) {
            Write-Warning "Handler script not found at expected location: $handlerScript"
            return $null
        }

        return $handlerScript
    }
    catch {
        Write-Error "Error determining handler script path: $_"
        return $null
    }
}
#endregion

#region Public Functions

function Unregister-UploadContextMenu {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
    $regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName

    $successFiles = $false
    $successFolders = $false

    try {
        if (Test-Path -Path $regPathFiles) {
            Remove-Item -Path $regPathFiles -Recurse -Force
            Write-Verbose "Removed context menu for files."
        }
        else {
            Write-Verbose "No file context menu key found."
        }
        $successFiles = $true
    }
    catch {
        Write-Error "Error removing file context menu: $_"
    }

    try {
        if (Test-Path -Path $regPathFolders) {
            Remove-Item -Path $regPathFolders -Recurse -Force
            Write-Verbose "Removed context menu for folders."
        }
        else {
            Write-Verbose "No folder context menu key found."
        }
        $successFolders = $true
    }
    catch {
        Write-Error "Error removing folder context menu: $_"
    }

    if ($successFiles -and $successFolders) {
        Write-Host "'$script:menuDisplayName' context menu unregistered."
        return $true
    }
    else {
        return $false
    }
}

function Register-UploadContextMenu {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    $handlerScriptPath = Get-HandlerScriptPath
    if (-not $handlerScriptPath) {
        Write-Error "Handler script path not found."
        return $false
    }

    $commandValue = "pwsh.exe -NoExit -ExecutionPolicy Bypass -NoProfile -Command `"& '$handlerScriptPath' '%1'; Read-Host 'Press Enter to close'`""

    $regPathFiles = Join-Path -Path $script:baseRegPathFiles -ChildPath $script:menuKeyName
    $regPathFolders = Join-Path -Path $script:baseRegPathFolders -ChildPath $script:menuKeyName

    $commandPathFiles = Join-Path -Path $regPathFiles -ChildPath "command"
    $commandPathFolders = Join-Path -Path $regPathFolders -ChildPath "command"

    $successFiles = $false
    $successFolders = $false

    try {
        if (-not (Test-Path -Path $regPathFiles) -or $Force) {
            New-Item -Path $regPathFiles -Force | Out-Null
            Set-ItemProperty -Path $regPathFiles -Name "(Default)" -Value $script:menuDisplayName -Force
            Set-ItemProperty -Path $regPathFiles -Name "Icon" -Value "pwsh.exe,0" -Force
            New-Item -Path $commandPathFiles -Force | Out-Null
            Set-ItemProperty -Path $commandPathFiles -Name "(Default)" -Value $commandValue -Force
        }
        $successFiles = $true
    }
    catch {
        Write-Error "Failed to register file context menu: $_"
    }

    try {
        if (-not (Test-Path -Path $regPathFolders) -or $Force) {
            New-Item -Path $regPathFolders -Force | Out-Null
            Set-ItemProperty -Path $regPathFolders -Name "(Default)" -Value $script:menuDisplayName -Force
            Set-ItemProperty -Path $regPathFolders -Name "Icon" -Value "pwsh.exe,0" -Force
            New-Item -Path $commandPathFolders -Force | Out-Null
            Set-ItemProperty -Path $commandPathFolders -Name "(Default)" -Value $commandValue -Force
        }
        $successFolders = $true
    }
    catch {
        Write-Error "Failed to register folder context menu: $_"
    }

    if ($successFiles -and $successFolders) {
        Write-Host "'$script:menuDisplayName' context menu registered."
        return $true
    }
    else {
        return $false
    }
}

#endregion

#region Export
Export-ModuleMember -Function Register-UploadContextMenu, Unregister-UploadContextMenu
#endregion
