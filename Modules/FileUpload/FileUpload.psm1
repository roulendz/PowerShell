# File Path: ./Modules/FileUpload/FileUpload.psm1

#Requires -Version 6.0 # For Invoke-RestMethod -Form parameter

<#
.SYNOPSIS
Provides functions to interact with the Files.fm API for uploading files and managing folders.

.DESCRIPTION
This module contains functions to create folders, upload files (individually or recursively),
and list folder contents on Files.fm using their REST API.

.NOTES
Requires PowerShell 6.0 or later due to the use of Invoke-RestMethod -Form.
Requires user credentials (username/password) for Files.fm.
API documentation: https://files.fm/api
#>

#region Private Helper Functions

# Helper function to handle API calls and basic error checking
function Invoke-FilesFmApi {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Endpoint,

        [Parameter(Mandatory=$false)]
        [hashtable]$QueryParameters,

        [Parameter(Mandatory=$false)]
        [hashtable]$FormParameters, # For POST with -Form

        [Parameter(Mandatory=$false)]
        [string]$Method = "GET",

        [Parameter(Mandatory=$false)]
        [hashtable]$Headers, # Optional headers

        # Parameters for real-time progress
        [Parameter(Mandatory=$false)]
        [int]$ProgressId = -1, # ID from TaskProgressBar module

        [Parameter(Mandatory=$false)]
        [string]$ProgressActivity # Activity string for progress bar
    )

    $baseUri = "https://api.files.fm"
    $uri = "$baseUri/$Endpoint"

    $invokeParams = @{
        Uri = $uri
        Method = $Method
        ErrorAction = "SilentlyContinue" # Handle errors manually
        SkipHttpErrorCheck = $true # Skip automatic error check to capture response body on 5xx errors
    }

    if ($QueryParameters) {
        # Properly encode query parameters
        $encodedQuery = $QueryParameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$([System.Web.HttpUtility]::UrlEncode($_.Value))" } | Join-String -Separator "&"
        $invokeParams.Uri = $uri + "?" + $encodedQuery
    }

    if ($FormParameters) {
        $invokeParams.Form = $FormParameters
    }

    if ($Headers) {
        $invokeParams.Headers = $Headers
    }

    # --- Progress Action Setup ---
    $lastProgressUpdateTime = [datetime]::MinValue
    $uploadStartTime = Get-Date

    if ($ProgressId -ge 0 -and $FormParameters -and $PSCmdlet.MyInvocation.MyCommand.Name -eq 'Upload-FileToFilesFm') { # Only for file uploads with progress ID
        $invokeParams.ProgressAction = {
            param($progressRecord)

            # Throttle updates to once per second
            $currentTime = Get-Date
            if (($currentTime - $using:lastProgressUpdateTime).TotalSeconds -lt 1 -and $progressRecord.PercentComplete -lt 100) {
                return
            }
            $using:lastProgressUpdateTime = $currentTime

            $bytesTransferred = $progressRecord.BytesTransferred
            $bytesTotal = $progressRecord.BytesTotal
            $percentComplete = $progressRecord.PercentComplete

            $elapsedTime = $currentTime - $using:uploadStartTime
            $statusMessage = "{0:N0} KB / {1:N0} KB ({2}%)" -f ($bytesTransferred / 1KB), ($bytesTotal / 1KB), $percentComplete

            if ($elapsedTime.TotalSeconds -gt 0 -and $bytesTransferred -gt 0) {
                $speedBytesPerSec = $bytesTransferred / $elapsedTime.TotalSeconds
                $statusMessage += " - {0:N1} KB/s" -f ($speedBytesPerSec / 1KB)

                if ($speedBytesPerSec -gt 0 -and $bytesTotal -gt $bytesTransferred) {
                    $remainingBytes = $bytesTotal - $bytesTransferred
                    $remainingSeconds = $remainingBytes / $speedBytesPerSec
                    $remainingTimeSpan = [timespan]::FromSeconds($remainingSeconds)
                    $statusMessage += " (ETA: {0:hh\:mm\:ss})" -f $remainingTimeSpan
                }
            }

            # Update the progress bar using the TaskProgressBar module function
            # Need to ensure Update-TaskProgress is available in this scope or call it differently
            # For simplicity, call Write-Progress directly here, assuming TaskProgressBar module handles nesting display
            Write-Progress -Activity $using:ProgressActivity -Id $using:ProgressId -Status $statusMessage -PercentComplete $percentComplete
        }
    }
    # --- End Progress Action Setup ---

    $response = $null
    $statusCode = $null
    $responseBody = $null

    try {
        Write-Verbose "Calling Files.fm API: $($invokeParams.Method) $($invokeParams.Uri)"
        # Use Invoke-WebRequest to get status code and response object easily
        $webResponse = Invoke-WebRequest @invokeParams
        $statusCode = $webResponse.StatusCode
        $responseBody = $webResponse.Content
        Write-Verbose "API Response Status Code: $statusCode"

        # Check for non-success status codes manually
        if ($statusCode -lt 200 -or $statusCode -ge 300) {
            throw "HTTP Error $statusCode"
        }

        # Try parsing response as JSON, fallback to raw content
        try {
            $response = $responseBody | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Verbose "Response was not valid JSON, returning raw content."
            $response = $responseBody
        }

        # Basic check for API-level errors if response structure is known/consistent
        if ($response -is [string] -and ($response -like "ERROR:*" -or $response -like "<!DOCTYPE html>*")) {
            throw "Files.fm API Error: $response"
        }
        if ($response -is [PSCustomObject] -and $response.PSObject.Properties.Name -contains 'error') {
             throw "Files.fm API Error: $($response.error)"
        }

        return $response

    } catch {
        # Construct detailed error message
        $errorMessage = "Failed to call Files.fm API '$Endpoint'."
        if ($statusCode) {
            $errorMessage += " Status Code: $statusCode."
        }
        if ($responseBody) {
            # Try to include the response body for debugging 500 errors
            $errorMessage += " Response Body: $responseBody"
        } elseif ($_.Exception.Message) {
             $errorMessage += " Exception: $($_.Exception.Message)"
        }
        
        Write-Error $errorMessage
        # Re-throw to allow calling function to handle failure
        throw $errorMessage 
    }
}

#endregion

#region Public Functions

<#
.SYNOPSIS
Creates a new folder on Files.fm.

.DESCRIPTION
Uses the get_upload_id.php endpoint to create a new folder. Can create a root folder or a subfolder.

.PARAMETER Username
Your Files.fm username.

.PARAMETER Password
Your Files.fm password.

.PARAMETER FolderName
The desired name for the new folder.

.PARAMETER ParentFolderHash
(Optional) The hash of the parent folder under which to create this new folder. If omitted, creates a root folder.

.PARAMETER AccessType
Access control for the folder. Valid values: 'LINK' (publicly accessible via hash) or 'PRIVATE'. Defaults to 'LINK'.

.EXAMPLE
# Create a root folder
New-FilesFmFolder -Username 'myuser' -Password 'mypass' -FolderName 'MyRootUploads'

.EXAMPLE
# Create a subfolder
New-FilesFmFolder -Username 'myuser' -Password 'mypass' -FolderName 'MySubFolder' -ParentFolderHash 'parentHash123'

.RETURNS
A PSCustomObject containing the new folder's Hash, EditKey, and AddKey on success.
Throws an error on failure.
#>
function New-FilesFmFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$true)]
        [string]$FolderName,

        [Parameter(Mandatory=$false)]
        [string]$ParentFolderHash, # Optional parent hash

        [Parameter(Mandatory=$false)]
        [ValidateSet('LINK', 'PRIVATE')]
        [string]$AccessType = 'LINK'
    )

    $endpoint = "api/get_upload_id.php"
    $params = @{
        user = $Username
        pass = $Password
        folder_name = $FolderName
        access_type = $AccessType
    }
    if ($ParentFolderHash) {
        $params.parent_folder_hash = $ParentFolderHash
    }

    try {
        $result = Invoke-FilesFmApi -Endpoint $endpoint -QueryParameters $params -Method GET
        
        # The API returns JSON like: {"hash":"abcdefg","edit_key":"12345","add_key":"67890"}
        if ($result -is [PSCustomObject] -and $result.hash -and ($result.edit_key -or $result.add_key)) {
            Write-Verbose "Folder '$FolderName' created successfully. Hash: $($result.hash)"
            return [PSCustomObject]@{
                Hash = $result.hash
                EditKey = $result.edit_key
                AddKey = $result.add_key
            }
        } else {
            throw "Unexpected response format from get_upload_id.php: $result"
        }
    } catch {
        Write-Error "Failed to create folder '$FolderName': $_"
        throw # Re-throw the exception
    }
}

<#
.SYNOPSIS
Uploads a single file to a specified Files.fm folder with real-time progress.

.DESCRIPTION
Uses the save_file.php endpoint with multipart/form-data to upload a file.
Displays real-time progress including speed and ETA.

.PARAMETER FilePath
The full path to the local file to upload.

.PARAMETER FolderHash
The hash of the target Files.fm folder (obtained from New-FilesFmFolder or Get-FilesFmFolderList).

.PARAMETER FolderKey
The 'AddKey' or 'EditKey' for the target folder.

.PARAMETER GetFileHash
Switch parameter. If specified, requests the hash of the uploaded file in the response.

.EXAMPLE
Upload-FileToFilesFm -FilePath 'C:\data\report.txt' -FolderHash 'abcdefg' -FolderKey '67890' -GetFileHash

.RETURNS
If -GetFileHash is specified, returns the hash of the uploaded file as a string.
Otherwise, returns 'd' on success (as per API docs).
Throws an error on failure.
#>
function Upload-FileToFilesFm {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [string]$FolderHash,

        [Parameter(Mandatory=$true)]
        [string]$FolderKey,

        [Parameter(Mandatory=$false)]
        [switch]$GetFileHash
    )

    $fileInfo = Get-Item -Path $FilePath -ErrorAction SilentlyContinue
    if (-not $fileInfo -or $fileInfo.PSIsContainer) {
        throw "File not found or is a directory: $FilePath"
    }

    $endpoint = "save_file.php"
    # Encode the key parameter
    $encodedKey = [System.Web.HttpUtility]::UrlEncode($FolderKey)
    $queryPart = "?up_id=$FolderHash&key=$encodedKey"
    if ($GetFileHash) {
        $queryPart += "&get_file_hash"
    }

    $form = @{
        file = $fileInfo # Pass the FileInfo object
    }
    
    $headers = $null # Let -Form handle the Content-Type

    Write-Verbose "Uploading file '$FilePath' to folder '$FolderHash' using key '$FolderKey'. Target URL part: $queryPart"

    # Initialize Progress Bar
    $progressActivity = "Uploading File: $($fileInfo.Name)"
    $progressId = Initialize-TaskProgress -Activity $progressActivity -Status "Initiating upload..." -TotalCount $fileInfo.Length # Use file length for total

    try {
        # Note: Query parameters are added manually to the endpoint URI here
        # because -Form implies POST and we need query params alongside the form data.
        $result = Invoke-FilesFmApi -Endpoint ($endpoint + $queryPart) `
                                    -FormParameters $form `
                                    -Method POST `
                                    -Headers $headers `
                                    -ProgressId $progressId `
                                    -ProgressActivity $progressActivity

        # Successful upload returns file hash (if requested) or 'd'
        if ($result -is [string] -and ($result -ne "" -and $result -ne "ERROR")) { # Basic check
             Write-Verbose "File '$FilePath' uploaded successfully to folder '$FolderHash'. Response: $result"
             # Ensure progress shows 100% on success
             Update-TaskProgress -ProgressId $progressId -Status "Upload Complete." -PercentComplete 100
             return $result
        } else {
            # If we got here, it means status code was 2xx but response wasn't expected 'd' or hash
            throw "Unexpected successful response during file upload: $result"
        }

    } catch {
        # Error message now includes status code and body from Invoke-FilesFmApi's catch block
        Write-Error "Failed to upload file '$FilePath' to folder '$FolderHash': $_"
        throw # Re-throw the exception
    } finally {
        # Ensure progress bar is completed regardless of success or failure
        Complete-TaskProgress -ProgressId $progressId
    }
}

<#
.SYNOPSIS
Lists the contents of a Files.fm folder.

.DESCRIPTION
Uses the get_file_list_for_upload.php endpoint to retrieve file and subfolder information.

.PARAMETER FolderHash
The hash of the target Files.fm folder.

.EXAMPLE
Get-FilesFmFolderList -FolderHash 'abcdefg'

.RETURNS
A PSCustomObject representing the folder contents (structure may vary based on API response).
Throws an error on failure.
#>
function Get-FilesFmFolderList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderHash
    )

    $endpoint = "api/get_file_list_for_upload.php"
    $params = @{
        hash = $FolderHash
    }

    try {
        $result = Invoke-FilesFmApi -Endpoint $endpoint -QueryParameters $params -Method GET
        # The API response structure needs inspection. Assuming it returns an object/array.
        Write-Verbose "Retrieved folder list for hash '$FolderHash'."
        return $result
    } catch {
        Write-Error "Failed to get folder list for hash '$FolderHash': $_"
        throw # Re-throw the exception
    }
}

<#
.SYNOPSIS
Recursively uploads the contents of a local folder to Files.fm.

.DESCRIPTION
Creates a corresponding folder structure on Files.fm and uploads all files within the specified local folder and its subfolders.
Uses Username/Password to create subfolders and the returned keys for uploads.

.PARAMETER LocalFolderPath
The full path to the local folder to upload.

.PARAMETER ParentFolderHash
The hash of the parent Files.fm folder where the new folder structure will be created.

.PARAMETER Username
Your Files.fm username (required to create subfolders).

.PARAMETER Password
Your Files.fm password (required to create subfolders).

.PARAMETER AccessType
Access control for newly created subfolders. Valid values: 'LINK' or 'PRIVATE'. Defaults to 'LINK'.

.PARAMETER GetFileHashes
Switch parameter. If specified, requests and returns the hashes of all uploaded files.

.EXAMPLE
Upload-FolderToFilesFmRecursive -LocalFolderPath 'C:\MyProject' -ParentFolderHash 'baseHash123' -Username 'myuser' -Password 'mypass'

.RETURNS
If -GetFileHashes is specified, returns an array of PSCustomObjects containing LocalPath and RemoteHash for each uploaded file.
Otherwise, returns $true on success, $false on failure.
Throws an error on critical failures.
#>
function Upload-FolderToFilesFmRecursive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFolderPath,

        [Parameter(Mandatory=$true)]
        [string]$ParentFolderHash, # Hash of the folder to create this one inside

        # No ParentFolderKey needed here, we use user/pass to create subfolders

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [ValidateSet('LINK', 'PRIVATE')]
        [string]$AccessType = 'LINK',

        [Parameter(Mandatory=$false)]
        [switch]$GetFileHashes
    )

    $localFolder = Get-Item -Path $LocalFolderPath -ErrorAction SilentlyContinue
    if (-not $localFolder -or -not $localFolder.PSIsContainer) {
        throw "Invalid local folder path: $LocalFolderPath"
    }

    $folderName = $localFolder.Name
    Write-Verbose "Processing folder: $LocalFolderPath"

    # 1. Create the corresponding folder on Files.fm under the ParentFolderHash
    $newFolderInfo = $null
    try {
        Write-Verbose "Creating remote folder '$folderName' under parent '$ParentFolderHash'..."
        # Pass ParentFolderHash to New-FilesFmFolder
        $newFolderInfo = New-FilesFmFolder -Username $Username -Password $Password -FolderName $folderName -ParentFolderHash $ParentFolderHash -AccessType $AccessType
        if (-not $newFolderInfo) {
            throw "Failed to create remote folder '$folderName'."
        }
        Write-Verbose "Remote folder '$folderName' created with hash '$($newFolderInfo.Hash)'"
    } catch {
        Write-Error "Error creating remote folder '$folderName': $_"
        # Decide if this is fatal. For now, let's assume it is.
        throw "Could not create remote folder '$folderName'. Aborting upload for this branch."
    }

    # Determine the key to use for uploads into the NEWLY created folder
    $currentFolderKey = if ($newFolderInfo.AddKey) { $newFolderInfo.AddKey } else { $newFolderInfo.EditKey }
    if (-not $currentFolderKey) {
         throw "Could not get a valid AddKey or EditKey for the newly created folder '$($newFolderInfo.Hash)'."
    }

    $uploadResults = @()
    $overallSuccess = $true

    # 2. Upload files in the current local folder to the NEWLY created remote folder
    $files = Get-ChildItem -Path $LocalFolderPath -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        Write-Verbose "Uploading file '$($file.FullName)' to NEW remote folder '$($newFolderInfo.Hash)'..."
        try {
            # Use the NEW folder's hash and key
            $uploadResult = Upload-FileToFilesFm -FilePath $file.FullName -FolderHash $newFolderInfo.Hash -FolderKey $currentFolderKey -GetFileHash:$GetFileHashes
            if ($GetFileHashes) {
                $uploadResults += [PSCustomObject]@{
                    LocalPath = $file.FullName
                    RemoteHash = $uploadResult
                }
            }
            Write-Verbose "Successfully uploaded '$($file.Name)'. Response/Hash: $uploadResult"
        } catch {
            Write-Error "Failed to upload file '$($file.FullName)': $_"
            $overallSuccess = $false
            # Continue with other files/folders even if one fails
        }
    }

    # 3. Recursively process subfolders
    $subfolders = Get-ChildItem -Path $LocalFolderPath -Directory -ErrorAction SilentlyContinue
    foreach ($subfolder in $subfolders) {
        try {
            # Recursive call: Parent for the next level is the folder we just created
            $subResult = Upload-FolderToFilesFmRecursive -LocalFolderPath $subfolder.FullName `
                -ParentFolderHash $newFolderInfo.Hash ` # Pass the NEW hash as the parent for the next level
                -Username $Username `
                -Password $Password `
                -AccessType $AccessType `
                -GetFileHashes:$GetFileHashes
            
            if ($GetFileHashes -and $subResult -is [array]) {
                $uploadResults += $subResult
            }
            if (-not $subResult) {
                $overallSuccess = $false # Propagate failure up
            }
        } catch {
            Write-Error "Failed to process subfolder '$($subfolder.FullName)': $_"
            $overallSuccess = $false
            # Continue with other subfolders
        }
    }

    if ($GetFileHashes) {
        return $uploadResults
    } else {
        return $overallSuccess
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function New-FilesFmFolder, Upload-FileToFilesFm, Get-FilesFmFolderList, Upload-FolderToFilesFmRecursive

#endregion

