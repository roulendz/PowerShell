# FileUpload.psm1
# Description: PowerShell module for uploading files to Files.fm service

#Requires -Version 7.5

#region Module Configuration
# Ensures strict mode for better error handling
Set-StrictMode -Version Latest
#endregion

#region Constants and Variables
# Default path for configuration file
[string]$script:ConfigPath = Join-Path $PSScriptRoot "../../config.json"

# Base URI for Files.fm API
[string]$script:BaseUri = "https://api.files.fm"

# Object to store current session data
[hashtable]$script:SessionData = @{}
#endregion

#region Private Functions

function Test-SessionCookie {
    <#
    .SYNOPSIS
        Validates if current session is still active
    .DESCRIPTION
        Checks if the PHPSESSID cookie is present and valid by testing the session
    .OUTPUTS
        [bool] True if session is valid, False otherwise
    #>
    [OutputType([bool])]
    param()
    
    # Check if session data exists
    if (-not $script:SessionData -or -not $script:SessionData.ContainsKey('PHPSESSID')) {
        return $false
    }
    
    try {
        # Test the session by calling test_session.php
        $uri = "$($script:BaseUri)/api/test_session.php"
        $response = Invoke-WebRequest -Uri $uri -Method Get -WebSession $script:SessionData.WebSession -ErrorAction Stop
        
        # Check if the response is successful
        return $response.StatusCode -eq 200
    }
    catch {
        # Session is invalid or expired
        return $false
    }
}

function Set-SessionContext {
    <#
    .SYNOPSIS
        Establishes and maintains session context for Files.fm API
    .DESCRIPTION
        Creates a web session and stores session ID and credentials for subsequent API calls
    .PARAMETER Credentials
        Credentials for Files.fm account
    .OUTPUTS
        [void]
    #>
    [OutputType([void])]
    param(
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]$Credentials
    )
    
    # Check if session is already valid
    if (Test-SessionCookie) {
        Write-Verbose "Using existing valid session"
        return
    }
    
    # Create new session
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    
    try {
        # Login to Files.fm API
        $loginUri = "$($script:BaseUri)/api/login.php"
        $loginParams = @{
            user = $Credentials.UserName
            pass = $Credentials.GetNetworkCredential().Password
        }
        
        Write-Verbose "Logging in to Files.fm..."
        $response = Invoke-WebRequest -Uri $loginUri -Method Post -Body $loginParams -SessionVariable session -ErrorAction Stop
        
        # Parse the login response (format: cookie:PHPSESSID=...; user=...; hash=...; etc.)
        $responseContent = $response.Content
        $sessionID = $null
        $rootHash = $null
        $rootKey = $null
        
        # Extract values from response
        if ($responseContent -match "PHPSESSID=(.*?);") {
            $sessionID = $matches[1]
        }
        if ($responseContent -match "root_upload_hash=(.*?);") {
            $rootHash = $matches[1]
        }
        if ($responseContent -match "root_upload_key=(.*?)(?:;|$)") {
            $rootKey = $matches[1]
        }
        
        # Check if login was successful
        if ($sessionID -and $rootHash) {
            Write-Verbose "Login successful - Session ID: $sessionID"
            
            # Store session data
            $script:SessionData = @{
                WebSession     = $session
                PHPSESSID      = $sessionID
                RootFolderHash = $rootHash
                DeleteKey      = $rootKey
                AddKey         = $rootKey
            }
        }
        else {
            # Login failed
            throw "Login failed: Invalid credentials or server error"
        }
    }
    catch {
        # Handle login errors
        throw "Failed to login to Files.fm: $_"
    }
}

function Get-ConfigurationData {
    <#
    .SYNOPSIS
        Loads configuration data from JSON file
    .DESCRIPTION
        Reads and parses the configuration file containing credentials and settings
    .PARAMETER ConfigPath
        Path to configuration file
    .OUTPUTS
        [PSCustomObject] Configuration data object
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ConfigPath = $script:ConfigPath
    )
    
    # Check if configuration file exists
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found at: $ConfigPath"
    }
    
    try {
        # Read and parse the configuration file
        $config = Get-Content $ConfigPath | ConvertFrom-Json -ErrorAction Stop
        
        # Validate required properties
        if (-not $config.Username -or -not $config.Password) {
            throw "Configuration file missing required properties (Username, Password)"
        }
        
        return $config
    }
    catch {
        throw "Failed to load configuration: $_"
    }
}

function Initialize-Session {
    <#
    .SYNOPSIS
        Initializes session using configuration data
    .DESCRIPTION
        Sets up connection to Files.fm API using credentials from configuration
    .PARAMETER Config
        Configuration object containing credentials
    .OUTPUTS
        [void]
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Config = $null
    )
    
    # Load configuration if not provided
    if (-not $Config) {
        $Config = Get-ConfigurationData
    }
    
    # Convert to secure credentials
    $securePassword = ConvertTo-SecureString $Config.Password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential($Config.Username, $securePassword)
    
    # Establish session
    Set-SessionContext -Credentials $credentials
}

function Get-FolderKeys {
    <#
    .SYNOPSIS
        Retrieves add and delete keys for a specified folder
    .DESCRIPTION
        Gets the required keys to perform operations on a folder
    .PARAMETER FolderHash
        Hash of the folder to get keys for
    .OUTPUTS
        [PSCustomObject] Object containing AddFileKey and DeleteKey
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderHash
    )
    
    try {
        # Ensure session is valid
        if (-not (Test-SessionCookie)) {
            Initialize-Session
        }
        
        # Get folder keys
        $uri = "$($script:BaseUri)/api/get_upload_keys.php"
        $params = @{
            hash = $FolderHash
            user = (Get-ConfigurationData).Username
            pass = (Get-ConfigurationData).Password
        }
        
        Write-Verbose "Getting keys for folder: $FolderHash"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Body $params -WebSession $script:SessionData.WebSession -ErrorAction Stop
        $keys = $response.Content | ConvertFrom-Json -ErrorAction Stop
        
        return $keys
    }
    catch {
        throw "Failed to get folder keys: $_"
    }
}

#endregion

#region Public Functions

function Send-FileToFilesFm {
    <#
    .SYNOPSIS
        Uploads a single file to Files.fm
    .DESCRIPTION
        Uploads a specified file to a Files.fm folder using the API
    .PARAMETER FilePath
        Path to the file to upload
    .PARAMETER FolderHash
        Hash of the destination folder
    .PARAMETER Config
        Optional configuration object
    .OUTPUTS
        [PSCustomObject] Upload result containing FileHash and Success status
    #>
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$FilePath,
        
        [Parameter(Mandatory = $false)]
        [string]$FolderHash = "",
        
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Config = $null
    )
    
    # Load config if not provided
    if (-not $Config) {
        $Config = Get-ConfigurationData
    }
    
    # Use BaseFolderHash from config if FolderHash not provided
    if (-not $FolderHash -and $Config.BaseFolderHash) {
        $FolderHash = $Config.BaseFolderHash
    }
    
    # Validate FolderHash
    if (-not $FolderHash) {
        throw "FolderHash must be provided either as parameter or in config file"
    }
    
    try {
        # Ensure session is valid
        if (-not (Test-SessionCookie)) {
            Initialize-Session -Config $Config
        }
        
        # Get folder keys
        $keys = Get-FolderKeys -FolderHash $FolderHash
        
        # Prepare file for upload
        $file = Get-Item $FilePath
        $fileName = $file.Name
        
        # Upload the file
        $uploadUri = "$($script:BaseUri)/save_file.php?up_id=$FolderHash&key=$($keys.AddFileKey)&get_file_hash=1"
        
        Write-Verbose "Uploading file: $fileName"
        $response = Invoke-WebRequest -Uri $uploadUri -Method Post -InFile $FilePath -ContentType "multipart/form-data" -WebSession $script:SessionData.WebSession -ErrorAction Stop
        
        # Parse response
        $fileHash = $response.Content.Trim()
        
        # Check if upload was successful
        if ($fileHash -ne 'd' -and $fileHash -ne '') {
            Write-Verbose "Successfully uploaded: $fileName (Hash: $fileHash)"
            return [PSCustomObject]@{
                Success   = $true
                FileHash  = $fileHash
                FileName  = $fileName
                FileUrl   = "https://files.fm/f/$fileHash"
                FolderUrl = "https://files.fm/u/$FolderHash"
            }
        }
        else {
            throw "Upload failed: Invalid response from server"
        }
        
    }
    catch {
        Write-Error "Failed to upload file: $_"
        return [PSCustomObject]@{
            Success  = $false
            FileHash = $null
            FileName = $fileName
            Error    = $_.Exception.Message
        }
    }
}

# Create a simplified version of Invoke-FileUploadToFilesFm that handles the parameter set issue
function Upload-FileToFilesFm {
    <#
    .SYNOPSIS
        Uploads file(s) to Files.fm service
    .DESCRIPTION
        Helper function to handle file uploads without parameter set conflicts
    .PARAMETER Path
        Path to file to upload
    .OUTPUTS
        [void] Displays summary and copies to clipboard
    #>
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        # Load configuration
        $config = Get-ConfigurationData
        
        Write-Host "Uploading file: $Path"
        $result = Send-FileToFilesFm -FilePath $Path -Config $config
        
        # Convert single file result to summary format
        $uploadResult = [PSCustomObject]@{
            TotalFiles        = 1
            SuccessfulUploads = if ($result.Success) { 1 } else { 0 }
            FailedUploads     = if ($result.Success) { 0 } else { 1 }
            UploadedFiles     = if ($result.Success) { @{ $result.FileName = $result.FileHash } } else { @{} }
            FolderHash        = $config.BaseFolderHash
            FolderUrl         = "https://files.fm/u/$($config.BaseFolderHash)"
            DetailedResults   = @([PSCustomObject]@{
                    FileName = $result.FileName
                    Result   = $result
                })
        }
        
        # Display summary
        Write-Host "`n--- Upload Summary ---"
        Write-Host "Target Files.fm Folder: $($uploadResult.FolderUrl)"
        Write-Host "Total files attempted: $($uploadResult.TotalFiles)"
        Write-Host "Successfully uploaded: $($uploadResult.SuccessfulUploads)"
        Write-Host "Upload errors: $($uploadResult.FailedUploads)"
        
        # Prepare clipboard content
        $clipboardContent = @()
        
        if ($uploadResult.SuccessfulUploads -gt 0) {
            Write-Host "`nSuccessfully uploaded files:"
            $clipboardContent += "Files uploaded to Files.fm:"
            $clipboardContent += "Folder: $($uploadResult.FolderUrl)"
            $clipboardContent += ""
            
            foreach ($file in $uploadResult.UploadedFiles.GetEnumerator()) {
                Write-Host " - $($file.Key) (Hash: $($file.Value))"
                Write-Host "   Link: https://files.fm/f/$($file.Value)"
                $clipboardContent += "$($file.Key): https://files.fm/f/$($file.Value)"
            }
            
            # Copy to clipboard
            $clipboardText = $clipboardContent -join "`r`n"
            Set-Clipboard -Value $clipboardText
            Write-Host "`nUpload links copied to clipboard!"
        }
        
        Write-Host "`nUpload process finished."
        
    }
    catch {
        Write-Error "Upload failed: $_"
        throw
    }
}

#endregion

#region Module Export
# Export public functions
Export-ModuleMember -Function Send-FileToFilesFm
Export-ModuleMember -Function Upload-FileToFilesFm
#endregion