# File Path: ./Scripts/UploadGui.ps1

<#
.SYNOPSIS
Provides a graphical user interface for configuring Files.fm uploader settings.

.DESCRIPTION
This script launches a GUI window allowing the user to input and save their Files.fm
username, password, and the target base folder hash for uploads. Settings are saved
to config.json in the parent directory.

.NOTES
Requires .NET Framework/Desktop Runtime for Windows Forms.
WARNING: Stores credentials in plain text in config.json. Consider using
Microsoft.PowerShell.SecretManagement for better security in production environments.
#>

#region Setup

# Load WinForms assembly
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}
catch {
    Write-Error "Failed to load Windows Forms assembly. This GUI requires a Windows environment with .NET Desktop Runtime."
    exit 1
}

# Determine paths
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Path $scriptPath -Parent
$rootDir = Split-Path -Path $scriptDir -Parent
$configFilePath = Join-Path -Path $rootDir -ChildPath "config.json"

#endregion

#region Load/Save Configuration

# Function to load configuration from JSON file
function Get-Configuration {
    param([string]$FilePath)
    if (Test-Path -Path $FilePath -PathType Leaf) {
        try {
            $configJson = Get-Content -Path $FilePath -Raw
            $config = $configJson | ConvertFrom-Json -ErrorAction Stop
            return $config
        }
        catch {
            Write-Warning "Failed to load or parse configuration file ${FilePath}: $_"
            return $null
        }
    }
    else {
        Write-Verbose "Configuration file not found: $FilePath"
        return $null
    }
}

# Function to save configuration to JSON file
function Save-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    try {
        $configJson = $Config | ConvertTo-Json -Depth 3
        # Ensure parent directory exists
        $parentDir = Split-Path -Path $FilePath -Parent
        if (-not (Test-Path -Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        Set-Content -Path $FilePath -Value $configJson -Encoding UTF8 -Force
        Write-Verbose "Configuration saved to $FilePath"
        return $true
    }
    catch {
        Write-Error "Failed to save configuration file ${FilePath}: $_"
        return $false
    }
}

#endregion

#region GUI Creation

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Files.fm Uploader Configuration"
$form.Size = New-Object System.Drawing.Size(400, 220)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# --- Username --- 
$labelUsername = New-Object System.Windows.Forms.Label
$labelUsername.Location = New-Object System.Drawing.Point(10, 15)
$labelUsername.Size = New-Object System.Drawing.Size(100, 20)
$labelUsername.Text = "Files.fm Username:"
$form.Controls.Add($labelUsername)

$textUsername = New-Object System.Windows.Forms.TextBox
$textUsername.Location = New-Object System.Drawing.Point(120, 12)
$textUsername.Size = New-Object System.Drawing.Size(250, 20)
$form.Controls.Add($textUsername)

# --- Password --- 
$labelPassword = New-Object System.Windows.Forms.Label
$labelPassword.Location = New-Object System.Drawing.Point(10, 45)
$labelPassword.Size = New-Object System.Drawing.Size(100, 20)
$labelPassword.Text = "Files.fm Password:"
$form.Controls.Add($labelPassword)

$textPassword = New-Object System.Windows.Forms.TextBox
$textPassword.Location = New-Object System.Drawing.Point(120, 42)
$textPassword.Size = New-Object System.Drawing.Size(250, 20)
$textPassword.PasswordChar = '*'
$form.Controls.Add($textPassword)

# --- Base Folder Hash --- 
$labelFolderHash = New-Object System.Windows.Forms.Label
$labelFolderHash.Location = New-Object System.Drawing.Point(10, 75)
$labelFolderHash.Size = New-Object System.Drawing.Size(110, 20)
$labelFolderHash.Text = "Base Folder Hash:"
$form.Controls.Add($labelFolderHash)

$textFolderHash = New-Object System.Windows.Forms.TextBox
$textFolderHash.Location = New-Object System.Drawing.Point(120, 72)
$textFolderHash.Size = New-Object System.Drawing.Size(250, 20)
$form.Controls.Add($textFolderHash)

# --- Warning --- 
$labelWarning = New-Object System.Windows.Forms.Label
$labelWarning.Location = New-Object System.Drawing.Point(10, 105)
$labelWarning.Size = New-Object System.Drawing.Size(360, 30)
$labelWarning.ForeColor = [System.Drawing.Color]::Red
$labelWarning.Text = "Warning: Credentials are saved in plain text in config.json. Use SecretManagement module for better security."
$form.Controls.Add($labelWarning)

# --- Save Button --- 
$buttonSave = New-Object System.Windows.Forms.Button
$buttonSave.Location = New-Object System.Drawing.Point(190, 145)
$buttonSave.Size = New-Object System.Drawing.Size(80, 25)
$buttonSave.Text = "Save"
$buttonSave.DialogResult = [System.Windows.Forms.DialogResult]::OK # Optional: Close on save
$form.AcceptButton = $buttonSave # Allow Enter key to trigger Save
$form.Controls.Add($buttonSave)

# --- Cancel Button --- 
$buttonCancel = New-Object System.Windows.Forms.Button
$buttonCancel.Location = New-Object System.Drawing.Point(290, 145)
$buttonCancel.Size = New-Object System.Drawing.Size(80, 25)
$buttonCancel.Text = "Cancel"
$buttonCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $buttonCancel # Allow Esc key to trigger Cancel
$form.Controls.Add($buttonCancel)

#endregion

#region Event Handlers and Logic

# Load existing configuration on form load
$form.Add_Load({
        $existingConfig = Get-Configuration -FilePath $configFilePath
        if ($existingConfig) {
            $textUsername.Text = $existingConfig.Username
            $textPassword.Text = $existingConfig.Password # Note: Loading plain text password
            $textFolderHash.Text = $existingConfig.BaseFolderHash
        }
    })

# Save configuration on Save button click
$buttonSave.Add_Click({
        $newConfig = [PSCustomObject]@{
            Username       = $textUsername.Text
            Password       = $textPassword.Text # Note: Saving plain text password
            BaseFolderHash = $textFolderHash.Text
        }
        if (Save-Configuration -Config $newConfig -FilePath $configFilePath) {
            [System.Windows.Forms.MessageBox]::Show("Configuration saved successfully.", "Save Configuration", "OK", "Information")
            # Form will close automatically due to DialogResult = OK
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("Failed to save configuration. Check console for errors.", "Save Error", "OK", "Error")
            # Prevent form from closing if save failed
            $form.DialogResult = [System.Windows.Forms.DialogResult]::None 
        }
    })

#endregion

#region Show Form

# Show the form modally
$form.TopMost = $true # Keep it on top
$result = $form.ShowDialog()

# Optional: Handle result if needed (e.g., check if saved or cancelled)
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "Configuration saved."
}
else {
    Write-Host "Configuration cancelled."
}

# Dispose of the form object
$form.Dispose()

#endregion
