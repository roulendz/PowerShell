# File path: /home/ubuntu/Documents/PowerShell/Modules/FilesFmUploader/FilesFmUploader.psm1
<#
.SYNOPSIS
Provides functions to interact with the Files.fm API for uploading files and managing folders.

.DESCRIPTION
This module includes functions for logging in, creating/checking folders, checking/uploading files, 
and helper functions for filename parsing and clipboard operations related to Files.fm.

.NOTES
Author: Manus
Date: 2025-05-02
Version: 1.1 (Added ProgressCallback parameter)
Requires: PowerShell 7.3+
#> 

#Requires -Version 7.3
#Requires -Assembly System.Web
#Requires -Assembly System.Windows.Forms # For Set-ClipboardText fallback

#region Module State
# Private module state to store configuration and session information.
# Use Initialize-FilesFmConfiguration to set credentials.
[hashtable]$script:FilesFm = @{
    LoginApi         = "https://api.files.fm/api/login.php" # API endpoint for login
    GetUploadIdApi   = "https://api.files.fm/api/get_upload_id.php" # API endpoint to create folder
    SaveFileApi      = "https://api.files.fm/save_file.php" # API endpoint to upload file
    GetFileListApi   = "https://api.files.fm/api/get_file_list_for_upload.php" # API endpoint to list folder contents
    GetUploadKeysApi = "https://api.files.fm/api/get_upload_keys.php" # API endpoint to get folder keys
    Username         = $null # Store username in module state (set via Initialize-FilesFmConfiguration)
    Password         = $null # Store password in module state (set via Initialize-FilesFmConfiguration)
    Session          = $null # Will store the authenticated session
}
#endregion

#region Helper Functions

# Internal helper function to check if the module is configured
function Test-FilesFmConfiguration {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ([string]::IsNullOrEmpty($script:FilesFm.Username) -or [string]::IsNullOrEmpty($script:FilesFm.Password)) {
        Write-Error -Message "Files.fm credentials not configured. Use Initialize-FilesFmConfiguration first." -Category InvalidOperation
        return $false
    }
    return $true
}

# Internal helper function to check if the session is active
function Test-FilesFmSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -eq $script:FilesFm.Session) {
        Write-Error -Message "No active Files.fm session. Use Initialize-FilesFmSession first." -Category InvalidOperation
        return $false
    }
    return $true
}

#endregion

#region Public Functions

function Initialize-FilesFmConfiguration {
    <#
    .SYNOPSIS
    Configures the Files.fm module with user credentials.
    .DESCRIPTION
    Sets the username and password required for authenticating with the Files.fm API.
    This must be called before using functions that require authentication.
    .PARAMETER Username
    The Files.fm username (email address).
    .PARAMETER Password
    The Files.fm password.
    .EXAMPLE
    Initialize-FilesFmConfiguration -Username "user@example.com" -Password "secret"
    #> 
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()] # Validate username is not empty
        [string]$Username,
        
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()] # Validate password is not empty
        [string]$Password
    )
    
    # Store credentials in the private module state
    $script:FilesFm.Username = [string]$Username
    $script:FilesFm.Password = [string]$Password
    Write-Verbose "Files.fm configuration updated for user: $Username"
}

function Initialize-FilesFmSession {
    <#
    .SYNOPSIS
    Logs in to Files.fm using configured credentials and establishes a session.
    .DESCRIPTION
    Authenticates with the Files.fm API using the username and password set by 
    Initialize-FilesFmConfiguration and stores the session for subsequent API calls.
    .OUTPUTS
    [bool] Returns $true on successful login, $false otherwise.
    .EXAMPLE
    Initialize-FilesFmConfiguration -Username "user@example.com" -Password "secret"
    $sessionOk = Initialize-FilesFmSession
    if ($sessionOk) { Write-Host "Login successful!" }
    #> 
    [CmdletBinding()]
    [OutputType([bool])] # Explicitly define return type
    param()
    
    # Check if configured
    if (-not (Test-FilesFmConfiguration)) {
        return $false
    }
    
    # Encode credentials and create login URL
    # System.Web assembly is required via #Requires statement
    [string]$encodedUsername = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Username)
    [string]$encodedPassword = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Password)
    [string]$loginUrl = "$($script:FilesFm.LoginApi)?user=$encodedUsername&pass=$encodedPassword"
    
    try {
        # Make login request to get session
        Write-Verbose "Attempting login to Files.fm as $($script:FilesFm.Username)"
        $null = Invoke-RestMethod -Uri $loginUrl -Method Get -SessionVariable webSession -ErrorAction Stop
        $script:FilesFm.Session = $webSession # Store session in module state
        Write-Verbose "Login successful. Session established."
        return $true # Return success
    }
    catch {
        # Handle login failure with specific error
        Write-Error -Message "Login failed: $_" -Category AuthenticationError
        $script:FilesFm.Session = $null # Clear potentially invalid session
        return $false # Return failure
    }
}

function Get-FilenameComponents {
    <#
    .SYNOPSIS
    Extracts date (YYYY-MM-DD) and day of the week from a specific filename format.
    .DESCRIPTION
    Parses a filename expected to be in the format 
*YYYY-MM-DD DayOfWeek*.*
 
    and returns the 
YYYY-MM-DD DayOfWeek
 part.
    .PARAMETER Filename
    The filename (including extension, path is optional) to extract components from.
    .OUTPUTS
    [string] The extracted 
YYYY-MM-DD DayOfWeek
 string, or $null if the pattern is not found.
    .EXAMPLE
    Get-FilenameComponents -Filename "MyRecording 2025-05-02 Friday.mp3"
    # Output: 2025-05-02 Friday
    .EXAMPLE
    Get-FilenameComponents -Filename "C:\Audio\Backup 2024-12-25 Wednesday.wav"
    # Output: 2024-12-25 Wednesday
    #> 
    [CmdletBinding()]
    [OutputType([string])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()] # Validate filename is not empty
        [string]$Filename # The filename to extract components from
    )
    
    # Extract just the filename without path
    [string]$filenameOnly = [System.IO.Path]::GetFileName($Filename)
    
    # Extract date and day of week using regex with type safety
    # Matches YYYY-MM-DD followed by whitespace and one or more word characters (DayOfWeek)
    if ($filenameOnly -match 
(\d { 4 }-\d { 2 }-\d { 2 })\s+(\w+)
    ) {
        Write-Verbose "Extracted date/day 
$($Matches[1]) $($Matches[2])
 from 
$filenameOnly
"
        return [string]"$($Matches[1]) $($Matches[2])" # Return the date and day of week
    }
    
    # Log warning if date extraction fails
    Write-Warning "Could not extract date and day of week from filename: $filenameOnly (Expected format: 
*YYYY-MM-DD DayOfWeek*.*
)"
    return $null
}

function Get-FilesFmFolder {
    <#
    .SYNOPSIS
    Checks if a folder exists within a parent folder in Files.fm and returns its details.
    .DESCRIPTION
    Searches for a folder by name within a specified parent folder hash. If found, 
    it retrieves and returns the folder
hash and keys (AddKey, DeleteKey).
    .PARAMETER ParentHash
    The hash of the parent folder to search within.
    .PARAMETER FolderName
    The exact name of the folder to search for.
    .OUTPUTS
    [PSCustomObject] A custom object with Hash, AddKey, and DeleteKey properties if the folder is found. Returns $null otherwise.
    .EXAMPLE
    $folderInfo = Get-FilesFmFolder -ParentHash "zxp3fh47ag" -FolderName "2025-05-02 Friday"
    if ($folderInfo) { Write-Host "Folder found with hash: $($folderInfo.Hash)" }
    #> 
    [CmdletBinding()]
    [OutputType([PSCustomObject])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$ParentHash, # Hash of the parent folder
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FolderName # Name of the folder to check
    )
    
    # Verify session exists
    if (-not (Test-FilesFmSession)) {
        return $null
    }
    
    # List parent folder contents API URL
    [string]$listUrl = "$($script:FilesFm.GetFileListApi)?hash=$ParentHash&include_folders=1"
    Write-Verbose "Checking for folder 
$FolderName
 in parent 
$ParentHash
 via $listUrl"
    
    try {
        # Get parent folder contents
        [PSCustomObject[]]$folderContents = Invoke-RestMethod -Uri $listUrl -Method Get -WebSession $script:FilesFm.Session -ErrorAction Stop
        
        # Check for our folder by name
        if ($folderContents -and $folderContents.Count -gt 0) {
            # Iterate through items in the parent folder
            foreach ($item in $folderContents) {
                # Check if the item is a folder and the name matches
                # Note: Files.fm API might return files too, ensure it
                is a folder if possible (API docs needed for certainty)
                # Assuming items with 
                name
                are folders based on 
                include_folders=1

                if ($item.name -eq $FolderName) {
                    Write-Verbose "Found existing folder: 
$FolderName
 with hash: $($item.hash)"
                    # If found, get its keys
                    return Get-FilesFmFolderKeys -FolderHash $item.hash
                }
            }
        }
        
        # Folder not found if loop completes without returning
        Write-Verbose "Folder not found: 
$FolderName
 in parent 
$ParentHash
"
        return $null
    }
    catch {
        Write-Error -Message "Failed to search for folder 
$FolderName
 in parent 
$ParentHash
: $_" -Category ObjectNotFound
        return $null
    }
}

function Get-FilesFmFolderKeys {
    <#
    .SYNOPSIS
    Retrieves the AddKey and DeleteKey for a given Files.fm folder hash.
    .DESCRIPTION
    Fetches the necessary keys for uploading files to or managing a specific folder using its hash.
    Requires authentication.
    .PARAMETER FolderHash
    The hash of the folder for which to retrieve keys.
    .OUTPUTS
    [PSCustomObject] A custom object with Hash, AddKey, and DeleteKey properties. Returns $null on failure.
    .EXAMPLE
    $keys = Get-FilesFmFolderKeys -FolderHash "abcdef1234"
    if ($keys) { Write-Host "Add Key: $($keys.AddKey)" }
    #> 
    [CmdletBinding()]
    [OutputType([PSCustomObject])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FolderHash # Hash of the folder
    )
    
    # Verify session and configuration exist
    if (-not (Test-FilesFmConfiguration) -or -not (Test-FilesFmSession)) {
        return $null
    }
    
    # Encode credentials and create URL
    # System.Web assembly is required via #Requires statement
    [string]$encodedUsername = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Username)
    [string]$encodedPassword = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Password)
    [string]$getKeysUrl = "$($script:FilesFm.GetUploadKeysApi)?hash=$FolderHash&user=$encodedUsername&pass=$encodedPassword"
    Write-Verbose "Getting keys for folder 
$FolderHash
 via $getKeysUrl"
    
    try {
        # Get folder keys via API call
        [PSCustomObject]$keysResponse = Invoke-RestMethod -Uri $getKeysUrl -Method Get -WebSession $script:FilesFm.Session -ErrorAction Stop
        
        # Return structured object if response is valid and contains expected keys
        if ($keysResponse -and $keysResponse.PSObject.Properties.Name -contains 
            AddFileKey
            -and $keysResponse.PSObject.Properties.Name -contains 
            DeleteKey
        ) {
            Write-Verbose "Successfully retrieved keys for folder 
$FolderHash
"
            return [PSCustomObject]@{
                Hash      = [string]$FolderHash # Hash of the folder
                AddKey    = [string]$keysResponse.AddFileKey # Add key for uploading files
                DeleteKey = [string]$keysResponse.DeleteKey # Delete key for managing the folder
            }
        }
        
        # Handle cases where the response is invalid or missing keys
        Write-Error -Message "Failed to get folder keys for 
$FolderHash
: Invalid response format or missing keys." -Category InvalidResult
        return $null
    }
    catch {
        # Handle API call errors
        Write-Error -Message "Failed to get folder keys for 
$FolderHash
: $_" -Category ReadError
        return $null
    }
}

function New-FilesFmFolder {
    <#
    .SYNOPSIS
    Creates a new folder in Files.fm under a specified parent folder.
    .DESCRIPTION
    Creates a new folder with the given name inside the parent folder identified by its hash. 
    Returns the details (Hash, AddKey, DeleteKey) of the newly created folder.
    Requires authentication.
    .PARAMETER ParentHash
    The hash of the parent folder where the new folder will be created.
    .PARAMETER FolderName
    The name for the new folder.
    .OUTPUTS
    [PSCustomObject] A custom object with Hash, AddKey, and DeleteKey properties for the new folder. Returns $null on failure.
    .EXAMPLE
    $newFolder = New-FilesFmFolder -ParentHash "zxp3fh47ag" -FolderName "My New Folder"
    if ($newFolder) { Write-Host "Created folder with hash: $($newFolder.Hash)" }
    #> 
    [CmdletBinding()]
    [OutputType([PSCustomObject])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$ParentHash, # Hash of the parent folder
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FolderName # Name of the folder to create
    )
    
    # Verify session and configuration exist
    if (-not (Test-FilesFmConfiguration) -or -not (Test-FilesFmSession)) {
        return $null
    }
    
    # Encode parameters and create URL
    # System.Web assembly is required via #Requires statement
    [string]$encodedUsername = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Username)
    [string]$encodedPassword = [System.Web.HttpUtility]::UrlEncode($script:FilesFm.Password)
    [string]$encodedFolderName = [System.Web.HttpUtility]::UrlEncode($FolderName)
    # Create folder with LINK access type by default
    [string]$createFolderUrl = "$($script:FilesFm.GetUploadIdApi)?user=$encodedUsername&pass=$encodedPassword&folder_name=$encodedFolderName&parent_hash=$ParentHash&access_type=LINK"
    Write-Verbose "Creating folder 
$FolderName
 in parent 
$ParentHash
 via $createFolderUrl"
    
    try {
        # Create folder via API call
        [PSCustomObject]$folderResponse = Invoke-RestMethod -Uri $createFolderUrl -Method Get -WebSession $script:FilesFm.Session -ErrorAction Stop
        
        # Return structured object if response is valid and contains expected properties
        if ($folderResponse -and $folderResponse.PSObject.Properties.Name -contains 
            hash
            -and $folderResponse.PSObject.Properties.Name -contains 
            add_key
            -and $folderResponse.PSObject.Properties.Name -contains 
            delete_key
        ) {
            Write-Verbose "Folder 
$FolderName
 created successfully with hash: $($folderResponse.hash)"
            return [PSCustomObject]@{
                Hash      = [string]$folderResponse.hash # Hash of the new folder
                AddKey    = [string]$folderResponse.add_key # Add key for uploading files
                DeleteKey = [string]$folderResponse.delete_key # Delete key for managing the folder
            }
        }
        
        # Handle invalid response format
        Write-Error -Message "Failed to create folder 
$FolderName
: Invalid response format from API." -Category InvalidResult
        return $null
    }
    catch {
        # Handle API call errors
        Write-Error -Message "Failed to create folder 
$FolderName
: $_" -Category WriteError
        return $null
    }
}

function Get-FilesFmFile {
    <#
    .SYNOPSIS
    Checks if a file exists within a specific Files.fm folder.
    .DESCRIPTION
    Searches for a file by its exact name within the folder specified by its hash.
    Returns file details (Hash, Name, Size) if found.
    Requires authentication.
    .PARAMETER FolderHash
    The hash of the folder to search within.
    .PARAMETER FileName
    The exact name of the file to search for.
    .OUTPUTS
    [PSCustomObject] A custom object with Hash, Name, and Size properties if the file is found. Returns $null otherwise.
    .EXAMPLE
    $fileInfo = Get-FilesFmFile -FolderHash "abcdef1234" -FileName "document.pdf"
    if ($fileInfo) { Write-Host "File found with hash: $($fileInfo.Hash)" }
    #> 
    [CmdletBinding()]
    [OutputType([PSCustomObject])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FolderHash, # Hash of the folder to search in
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FileName # Name of the file to check
    )
    
    # Verify session exists
    if (-not (Test-FilesFmSession)) {
        return $null
    }
    
    # List folder contents API URL (only files needed)
    [string]$listUrl = "$($script:FilesFm.GetFileListApi)?hash=$FolderHash"
    Write-Verbose "Checking for file 
$FileName
 in folder 
$FolderHash
 via $listUrl"
    
    try {
        # Get folder contents (files)
        [PSCustomObject[]]$fileContents = Invoke-RestMethod -Uri $listUrl -Method Get -WebSession $script:FilesFm.Session -ErrorAction Stop
        
        # Check for file by name
        if ($fileContents -and $fileContents.Count -gt 0) {
            # Iterate through items in the folder
            foreach ($item in $fileContents) {
                # Check if the item name matches the target filename
                if ($item.name -eq $FileName) {
                    Write-Verbose "Found existing file: 
$FileName
 with hash: $($item.hash)"
                    # Return file details
                    return [PSCustomObject]@{
                        Hash = [string]$item.hash # Hash of the file
                        Name = [string]$item.name # Name of the file
                        Size = [string]$item.Size # Size of the file (API returns it as string)
                    }
                }
            }
        }
        
        # File not found if loop completes without returning
        Write-Verbose "File not found: 
$FileName
 in folder 
$FolderHash
"
        return $null
    }
    catch {
        # Handle API call errors
        Write-Error -Message "Failed to search for file 
$FileName
 in folder 
$FolderHash
: $_" -Category ObjectNotFound
        return $null
    }
}

function Send-FileToFilesFm {
    <#
    .SYNOPSIS
    Uploads a local file to a specified Files.fm folder with optional progress callback.
    .DESCRIPTION
    Uploads the file specified by FilePath to the Files.fm folder identified by FolderHash, 
    using the provided AddKey for authorization. Displays upload progress using Write-Progress by default, 
    or invokes a custom script block provided via ProgressCallback.
    Requires authentication and a valid session.
    .PARAMETER FilePath
    The full path to the local file to upload.
    .PARAMETER FolderHash
    The hash of the destination folder on Files.fm.
    .PARAMETER AddKey
    The 
Add Key
 for the destination folder, obtained via Get-FilesFmFolderKeys or New-FilesFmFolder.
    .PARAMETER ProgressCallback
    (Optional) A script block to call for progress updates instead of the internal Write-Progress.
    The script block will receive a PSCustomObject with properties: Activity (string), TotalSize (long), 
    BytesProcessed (long), StartTime (datetime), Completed (switch), ProgressId (int).
    .PARAMETER ProgressId
    (Optional) An identifier for the progress bar, passed to Write-Progress or the ProgressCallback. Defaults to 0.
    .OUTPUTS
    [string] The hash of the uploaded file if successful. Returns $null on failure.
    .EXAMPLE
    # Basic usage (internal progress)
    $uploadHash = Send-FileToFilesFm -FilePath "C:\report.docx" -FolderHash "abcdef" -AddKey "xyz789"
    .EXAMPLE
    # Usage with ProgressBarHelper module
    Import-Module ProgressBarHelper
    $callback = {
        param($progressData)
        Update-DetailedProgress -Activity $progressData.Activity `
                                -TotalSize $progressData.TotalSize `
                                -BytesProcessed $progressData.BytesProcessed `
                                -StartTime $progressData.StartTime `
                                -ProgressId $progressData.ProgressId `
                                -Completed:$progressData.Completed
    }
    $uploadHash = Send-FileToFilesFm -FilePath "C:\archive.zip" -FolderHash "abcdef" -AddKey "xyz789" -ProgressCallback $callback
    #> 
    [CmdletBinding()]
    [OutputType([string])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path $_ -PathType Leaf })][string]$FilePath, # Path to the file to upload
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$FolderHash, # Hash of the folder to upload to
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()][string]$AddKey, # Add key for the folder
        
        [Parameter(Mandatory = $false)]
        [scriptblock]$ProgressCallback = $null, # Optional script block for progress

        [Parameter(Mandatory = $false)]
        [int]$ProgressId = 0 # Progress ID for internal or external progress
    )
    
    # Verify session exists
    if (-not (Test-FilesFmSession)) {
        return $null
    }
    
    # Get local file info
    [System.IO.FileInfo]$fileInfo = Get-Item -Path $FilePath
    [long]$fileSize = $fileInfo.Length
    [string]$fileName = $fileInfo.Name
    Write-Verbose "Preparing to upload 
$fileName
 ($([Math]::Round($fileSize / 1MB, 2)) MB) to folder 
$FolderHash
"
    
    # Set upload parameters
    [int]$chunkSize = 1MB # Upload chunk size
    [string]$uploadUrl = "$($script:FilesFm.SaveFileApi)?up_id=$FolderHash&key=$AddKey&get_file_hash=1"
    Write-Verbose "Upload URL: $uploadUrl"
    
    # Declare variables for streams and response outside try block for finally block access
    [System.IO.Stream]$requestStream = $null
    [System.IO.FileStream]$fileStream = $null
    [System.Net.WebResponse]$response = $null
    [System.IO.Stream]$responseStream = $null
    [System.IO.StreamReader]$reader = $null
    [System.Diagnostics.Stopwatch]$sw = $null
    [datetime]$startTime = Get-Date # Record start time for callback

    try {
        # Start tracking upload time (Stopwatch for internal calculation if needed)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        
        # --- Construct multipart form data --- 
        [string]$boundary = [System.Guid]::NewGuid().ToString() # Unique boundary for multipart
        [string]$LF = "`r`n" # Line feed characters
        # Form data part for the file
        [string]$bodyStart = "--$boundary$LF" + 
        "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"$LF" +
        "Content-Type: application/octet-stream$LF$LF"
        # Form data closing boundary
        [string]$bodyEnd = "$LF--$boundary--$LF"
        
        # Calculate total content length for the request header
        [long]$contentLength = $bodyStart.Length + $fileSize + $bodyEnd.Length
        
        # --- Create and configure HttpWebRequest --- 
        [System.Net.HttpWebRequest]$request = [System.Net.WebRequest]::CreateHttp($uploadUrl)
        $request.Method = "POST"
        $request.ContentLength = $contentLength
        $request.AllowWriteStreamBuffering = $false # Important for large files
        $request.SendChunked = $false # We manage chunks manually
        $request.KeepAlive = $true
        $request.ContentType = "multipart/form-data; boundary=$boundary"
        $request.Timeout = 600000 # 10 minutes timeout for upload
        
        # Add cookies from the established session
        $request.CookieContainer = New-Object System.Net.CookieContainer
        foreach ($cookie in $script:FilesFm.Session.Cookies.GetCookies($uploadUrl)) {
            $request.CookieContainer.Add($cookie)
        }
        
        # --- Write request body (multipart form) --- 
        $requestStream = $request.GetRequestStream() # Get stream to write request data
        
        # Write the starting boundary and file headers
        [byte[]]$bodyStartBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyStart)
        $requestStream.Write($bodyStartBytes, 0, $bodyStartBytes.Length)
        
        # --- Stream file content in chunks with progress --- 
        $fileStream = [System.IO.File]::OpenRead($FilePath) # Open file for reading
        [byte[]]$buffer = New-Object byte[] $chunkSize # Buffer for reading chunks
        [long]$totalBytesRead = 0 # Track total bytes read/written
        [int]$bytesRead = 0 # Bytes read in current chunk
        [datetime]$lastUpdate = (Get-Date).AddSeconds(-1) # Ensure first progress update happens
        
        # Loop through file, reading chunks and writing to request stream
        while (($bytesRead = $fileStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $requestStream.Write($buffer, 0, $bytesRead) # Write chunk to request
            $totalBytesRead += $bytesRead # Update total bytes written
            
            # --- Update Progress Bar (every 100ms) --- 
            [datetime]$now = Get-Date
            if (($now - $lastUpdate).TotalMilliseconds -ge 100) {
                # If a callback is provided, use it
                if ($ProgressCallback -ne $null) {
                    $progressData = [PSCustomObject]@{
                        Activity       = "Uploading 
$fileName
 ($([Math]::Round($fileSize / 1MB, 2)) MB)"
                        TotalSize      = $fileSize
                        BytesProcessed = $totalBytesRead
                        StartTime      = $startTime # Pass the initial start time
                        Completed      = $false
                        ProgressId     = $ProgressId
                    }
                    # Invoke the callback script block with the progress data
                    & $ProgressCallback $progressData
                }
                # Otherwise, use internal Write-Progress
                else {
                    [int]$percentComplete = 0
                    if ($fileSize -gt 0) {
                        # Avoid division by zero for empty files
                        $percentComplete = [int](($totalBytesRead / $fileSize) * 100)
                    }
                    [timespan]$elapsedTime = $sw.Elapsed
                    [double]$bytesPerSecond = 0
                    if ($elapsedTime.TotalSeconds -gt 0) {
                        # Avoid division by zero
                        $bytesPerSecond = $totalBytesRead / $elapsedTime.TotalSeconds
                    }
                    
                    # Format speed string (B/s, KB/s, MB/s)
                    [string]$speedString = if ($bytesPerSecond -ge 1MB) {
                        "{0:N2} MB/s" -f ($bytesPerSecond / 1MB)
                    }
                    elseif ($bytesPerSecond -ge 1KB) {
                        "{0:N2} KB/s" -f ($bytesPerSecond / 1KB)
                    }
                    else {
                        "{0:N0} B/s" -f $bytesPerSecond
                    }
                    
                    # Calculate estimated remaining time
                    [long]$remainingBytes = $fileSize - $totalBytesRead
                    [double]$remainingTimeSeconds = 0
                    if ($bytesPerSecond -gt 0) {
                        # Avoid division by zero
                        $remainingTimeSeconds = $remainingBytes / $bytesPerSecond
                    }
                    [timespan]$remainingTime = [TimeSpan]::FromSeconds([math]::Ceiling($remainingTimeSeconds))
                    
                    # Display progress using Write-Progress
                    Write-Progress -Activity "Uploading 
$fileName
 ($([Math]::Round($fileSize / 1MB, 2)) MB)" `
                        -Status ("$percentComplete% Complete - {0} - Elapsed: {1} - Remaining: {2}" -f $speedString, $elapsedTime.ToString(
                            \hh\:mm\:ss
                        ), $remainingTime.ToString(
                            \hh\:mm\:ss
                        )) `
                        -PercentComplete $percentComplete `
                        -Id $ProgressId
                }
                $lastUpdate = $now # Update time of last progress display
            }
        }
        
        # --- Write closing boundary --- 
        [byte[]]$bodyEndBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyEnd)
        $requestStream.Write($bodyEndBytes, 0, $bodyEndBytes.Length)
        
        # Close request stream AFTER writing everything
        $requestStream.Close()
        $requestStream.Dispose()
        $requestStream = $null # Set to null after disposal
        
        # --- Get and process response --- 
        Write-Verbose "Upload stream sent. Waiting for response..."
        $response = $request.GetResponse() # Get the server
        response
        $responseStream = $response.GetResponseStream() # Get response stream
        $reader = New-Object System.IO.StreamReader($responseStream) # Reader for response content
        [string]$responseContent = $reader.ReadToEnd() # Read the entire response
        Write-Verbose "Received response: $responseContent"
        
        # --- Finalize Progress Bar --- 
        $sw.Stop() # Stop the timer
        if ($ProgressCallback -ne $null) {
            $progressData = [PSCustomObject]@{
                Activity       = "Uploading 
$fileName
"
                TotalSize      = $fileSize
                BytesProcessed = $fileSize # Mark as fully processed
                StartTime      = $startTime
                Completed      = $true # Set completed flag
                ProgressId     = $ProgressId
            }
            & $ProgressCallback $progressData
        }
        else {
            Write-Progress -Activity "Uploading 
$fileName
" -Status "100% Complete - Processing response..." -PercentComplete 100 -Completed -Id $ProgressId
        }
        
        # --- Extract file hash from response --- 
        [string]$fileHash = $null
        
        # Try parsing response as JSON first (common API practice)
        try {
            [PSCustomObject]$jsonResponse = $responseContent | ConvertFrom-Json -ErrorAction Stop
            
            # Look for expected hash property names
            if ($jsonResponse.PSObject.Properties.Name -contains 
                file_hash
            ) {
                $fileHash = [string]$jsonResponse.file_hash
            }
            elseif ($jsonResponse.PSObject.Properties.Name -contains 
                hash
            ) {
                $fileHash = [string]$jsonResponse.hash
            }
            else {
                # Fallback: Look for any string property that looks like a hash (alphanumeric, length 6+)
                Write-Warning "Could not find 
file_hash
 or 
hash
 in JSON response. Searching for hash-like properties."
                foreach ($prop in $jsonResponse.PSObject.Properties) {
                    if ($prop.Value -is [string] -and $prop.Value -match 
                        ^[a-zA-Z0-9] { 6, }$
                    ) {
                        Write-Verbose "Found potential hash in property 
$($prop.Name)
: $($prop.Value)"
                        $fileHash = [string]$prop.Value
                        break # Use the first one found
                    }
                }
            }
        }
        catch {
            # If response is not valid JSON, try regex extraction as a fallback
            Write-Warning "Response is not valid JSON. Attempting regex extraction for hash."
            if ($responseContent -match 
                "file_hash"\s*:\s*"([a-zA-Z0-9]{6,})"
            ) {
                $fileHash = [string]$Matches[1]
            }
            elseif ($responseContent -match 
                "hash"\s*:\s*"([a-zA-Z0-9]{6,})"
            ) {
                $fileHash = [string]$Matches[1]
            }
            elseif ($responseContent -match 
([a-zA-Z0 - 9] { 6, })
            ) { # More generic match as last resort
                $fileHash = [string]$Matches[1] # Use the first alphanumeric sequence found
            }
            else {
                # If no hash found via JSON or regex, use the trimmed response (unlikely to be correct)
                $fileHash = [string]$responseContent.Trim()
                Write-Warning "Could not extract hash via JSON or regex. Using trimmed response content: 
$fileHash
"
            }
        }
        
        # --- Validate and return hash --- 
        if ($fileHash -match '^[a-zA-Z0-9]{6,}$') {
            Write-Verbose "Successfully extracted file hash: $fileHash"
            return $fileHash # Return the validated hash
        }
        else {
            # If no valid hash could be extracted
            Write-Error -Message "Could not extract a valid file hash from the response. Response content: $responseContent" -Category InvalidResult
            return $null
        }
    }
    catch {
        # Catch any exceptions during the process
        Write-Error -Message "File upload failed for 
$fileName
: $_" -Category WriteError
        # Ensure progress bar is closed on error
        if ($sw -ne $null -and $sw.IsRunning) { $sw.Stop() }
        if ($ProgressCallback -ne $null) {
            $progressData = [PSCustomObject]@{
                Activity       = "Uploading 
$fileName
"
                TotalSize      = $fileSize
                BytesProcessed = $totalBytesRead # Use actual bytes read on error
                StartTime      = $startTime
                Completed      = $true # Mark as completed to close the bar
                ProgressId     = $ProgressId
            }
            # Try to call callback one last time to close it, ignore errors
            try { & $ProgressCallback $progressData -ErrorAction SilentlyContinue } catch {}
        }
        else {
            Write-Progress -Activity "Uploading 
$fileName
" -Status "Upload Failed" -PercentComplete 0 -Completed -Id $ProgressId
        }
        return $null
    }
    finally {
        # --- Cleanup Resources --- 
        # Ensure all streams and response objects are closed and disposed
        if ($reader -ne $null) { $reader.Close(); $reader.Dispose() }
        if ($responseStream -ne $null) { $responseStream.Close(); $responseStream.Dispose() }
        if ($response -ne $null) { $response.Close() }
        if ($requestStream -ne $null) { $requestStream.Close(); $requestStream.Dispose() } # Should be closed in try, but just in case
        if ($fileStream -ne $null) { $fileStream.Close(); $fileStream.Dispose() }
        Write-Verbose "Upload resources cleaned up for 
$fileName
."
    }
}

function Set-ClipboardText {
    <#
    .SYNOPSIS
    Copies the provided text to the system clipboard.
    .DESCRIPTION
    Attempts to copy the given text to the clipboard using the native Set-Clipboard cmdlet if available,
    otherwise falls back to using .NET Windows Forms (requires GUI environment).
    .PARAMETER Text
    The text string to copy to the clipboard.
    .OUTPUTS
    [bool] Returns $true if successful, $false otherwise.
    .EXAMPLE
    Set-ClipboardText -Text "Hello, Clipboard!"
    #> 
    [CmdletBinding()]
    [OutputType([bool])] # Explicitly define return type
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text # Text to copy to clipboard (Allow empty string)
    )
    
    try {
        # Try using the built-in Set-Clipboard cmdlet first (preferred method)
        if (Get-Command -Name Set-Clipboard -ErrorAction SilentlyContinue) {
            Write-Verbose "Using Set-Clipboard cmdlet."
            Set-Clipboard -Value $Text -ErrorAction Stop
            return $true
        }
        else {
            # Fallback to using .NET Windows Forms (requires GUI session and assembly)
            Write-Verbose "Set-Clipboard not found. Falling back to System.Windows.Forms.Clipboard."
            # System.Windows.Forms assembly is required via #Requires statement
            [System.Windows.Forms.Clipboard]::SetText($Text)
            return $true
        }
    }
    catch {
        # Catch errors from either method
        Write-Warning "Failed to copy text to clipboard: $_"
        return $false
    }
}

#endregion

#region Module Export
# Export the functions intended for public use
Export-ModuleMember -Function Initialize-FilesFmConfiguration, `
    Initialize-FilesFmSession, `
    Get-FilenameComponents, `
    Get-FilesFmFolder, `
    Get-FilesFmFolderKeys, `
    New-FilesFmFolder, `
    Get-FilesFmFile, `
    Send-FileToFilesFm, `
    Set-ClipboardText
#endregion

