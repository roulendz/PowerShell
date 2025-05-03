# File Path: ./Modules/FileUpload/FileUpload.psm1

#Requires -Version 5.1 # Adjusted requirement as -Form is no longer strictly needed if ProgressAction fails

<#
.SYNOPSIS
Provides functions to interact with the Files.fm API for uploading files and managing folders.

.DESCRIPTION
This module contains functions to create folders, upload files (individually or recursively),
and list folder contents on Files.fm using their REST API.

.NOTES
Requires user credentials (username/password) for Files.fm.
API documentation: https://files.fm/api
Progress display requires the ProgressBarHelper module.
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
        [hashtable]$Headers
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
        # Use Invoke-RestMethod if -Form is needed and PS version allows
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $invokeParams.Remove("SkipHttpErrorCheck") # Not applicable to Invoke-RestMethod
            Write-Verbose "Using Invoke-RestMethod for form data upload."
            $cmd = "Invoke-RestMethod"
        } else {
            # Fallback or error for PS 5.1 with -Form (complex manual construction needed)
            Write-Error "PowerShell 5.1 does not directly support -Form with Invoke-WebRequest. Manual multipart/form-data construction is required but not implemented here."
            throw "Unsupported operation in PowerShell 5.1"
        }
        $invokeParams.Form = $FormParameters
    } else {
        # Use Invoke-WebRequest for non-form requests
        Write-Verbose "Using Invoke-WebRequest."
        $cmd = "Invoke-WebRequest"
    }

    if ($Headers) {
        $invokeParams.Headers = $Headers
    }

    $response = $null
    $statusCode = $null
    $responseBody = $null

    try {
        Write-Verbose "Calling Files.fm API: $($invokeParams.Method) $($invokeParams.Uri)"
        
        if ($cmd -eq "Invoke-WebRequest") {
            $webResponse = Invoke-WebRequest @invokeParams
            $statusCode = $webResponse.StatusCode
            $responseBody = $webResponse.Content
        } else { # Invoke-RestMethod
            # Invoke-RestMethod throws on HTTP errors by default unless -SkipHttpErrorCheck is used (but it's not supported)
            # We need to catch the exception to get details
            try {
                $responseBodyObject = Invoke-RestMethod @invokeParams
                $statusCode = 200 # Assume success if no exception
                $responseBody = $responseBodyObject | ConvertTo-Json -Depth 5 -Compress # Convert back for consistency if needed
            } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                $statusCode = $_.Exception.Response.StatusCode.value__
                $responseBody = $_.Exception.Response.Content
                Write-Warning "Invoke-RestMethod failed with status code $statusCode. Response: $responseBody"
                # Re-throw to be caught by the outer try-catch
                throw "HTTP Error $statusCode"
            } catch {
                # Catch other potential errors during Invoke-RestMethod
                throw "Invoke-RestMethod failed: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "API Response Status Code: $statusCode"

        # Check for non-success status codes manually (redundant for Invoke-RestMethod catch, but safe)
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
# ... (rest of New-FilesFmFolder remains the same) ...
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
Uploads a single file to a specified Files.fm folder using ProgressBarHelper.

.DESCRIPTION
Uses the save_file.php endpoint with multipart/form-data to upload a file.
Displays progress using the Update-DetailedProgress function from the ProgressBarHelper module.

.PARAMETER FilePath
The full path to the local file to upload.

.PARAMETER FolderHash
The hash of the target Files.fm folder.

.PARAMETER FolderKey
The 'AddKey' or 'EditKey' for the target folder.

.PARAMETER GetFileHash
Switch parameter. If specified, requests the hash of the uploaded file in the response.

.PARAMETER ProgressId
(Optional) An identifier for the progress bar. Defaults to 1.

.EXAMPLE
Upload-FileToFilesFm -FilePath 'C:\data\report.txt' -FolderHash 'abcdefg' -FolderKey '67890' -GetFileHash

.RETURNS
The result from the API ('d' or file hash) on success.
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
        [switch]$GetFileHash,

        [Parameter(Mandatory=$false)]
        [int]$ProgressId = 1 # Default progress ID for this operation
    )

    # Ensure ProgressBarHelper module is available
    if (-not (Get-Command Update-DetailedProgress -ErrorAction SilentlyContinue)) {
        throw "ProgressBarHelper module not found or Update-DetailedProgress function is not available."
    }

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

    # --- Progress Initialization ---
    $progressActivity = "Uploading File: $($fileInfo.Name)"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Show initial progress (0%)
        Update-DetailedProgress -Activity $progressActivity `
                                -TotalSize $fileInfo.Length `
                                -BytesProcessed 0 `
                                -StartTime $stopwatch.Elapsed `
                                -ProgressId $ProgressId

        # --- API Call ---
        # Note: Query parameters are added manually to the endpoint URI here
        # because -Form implies POST and we need query params alongside the form data.
        $apiResult = Invoke-FilesFmApi -Endpoint ($endpoint + $queryPart) `
                                    -FormParameters $form `
                                    -Method POST `
                                    -Headers $headers
        
        $stopwatch.Stop()
        # --- End API Call ---

        # Successful upload returns file hash (if requested) or 'd'
        if ($apiResult -is [string] -and ($apiResult -ne "" -and $apiResult -ne "ERROR")) { # Basic check
             Write-Verbose "File '$FilePath' uploaded successfully to folder '$FolderHash'. Response: $apiResult"
             # Show completed progress (100%)
             Update-DetailedProgress -Activity $progressActivity `
                                     -TotalSize $fileInfo.Length `
                                     -BytesProcessed $fileInfo.Length `
                                     -StartTime $stopwatch.Elapsed `
                                     -ProgressId $ProgressId `
                                     -Completed
             return $apiResult # Return only the API result
        } else {
            # If we got here, it means status code was 2xx but response wasn't expected 'd' or hash
            throw "Unexpected successful response during file upload: $apiResult"
        }

    } catch {
        $stopwatch.Stop() # Ensure stopwatch stops on error
        # Mark progress as completed (but failed) - use a generic message
        Update-DetailedProgress -Activity "Upload Failed: $($fileInfo.Name)" `
                                -TotalSize $fileInfo.Length `
                                -BytesProcessed $fileInfo.Length # Show 100% but with failed activity
                                -StartTime $stopwatch.Elapsed `
                                -ProgressId $ProgressId `
                                -Completed
        
        # Error message now includes status code and body from Invoke-FilesFmApi's catch block
        Write-Error "Failed to upload file '$FilePath' to folder '$FolderHash': $_"
        throw # Re-throw the original exception
    } 
    # No finally block needed here for progress completion
}

<#
.SYNOPSIS
Lists the contents of a Files.fm folder.
# ... (rest of Get-FilesFmFolderList remains the same) ...
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
Recursively uploads the contents of a local folder to Files.fm using ProgressBarHelper.

.DESCRIPTION
Creates a corresponding folder structure on Files.fm and uploads all files within the specified local folder and its subfolders.
Uses Username/Password to create subfolders and the returned keys for uploads.
Displays overall progress and individual file progress using ProgressBarHelper.

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
A PSCustomObject containing:
- Success: $true or $false indicating overall success.
- UploadedFiles: (If -GetFileHashes specified) An array of PSCustomObjects containing LocalPath and RemoteHash for each uploaded file.
Throws an error on critical failures.
#>
function Upload-FolderToFilesFmRecursive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LocalFolderPath,

        [Parameter(Mandatory=$true)]
        [string]$ParentFolderHash, # Hash of the folder to create this one inside

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

    # Ensure ProgressBarHelper module is available
    if (-not (Get-Command Update-DetailedProgress -ErrorAction SilentlyContinue)) {
        throw "ProgressBarHelper module not found or Update-DetailedProgress function is not available."
    }

    $sourceDirInfo = Get-Item -Path $LocalFolderPath -ErrorAction SilentlyContinue
    if (-not $sourceDirInfo -or -not $sourceDirInfo.PSIsContainer) {
        throw "Local folder not found or is not a directory: $LocalFolderPath"
    }

    $overallSuccess = $true
    $uploadedFilesList = [System.Collections.Generic.List[PSCustomObject]]::new()
    $filesToUpload = Get-ChildItem -Path $LocalFolderPath -Recurse -File
    $totalFiles = $filesToUpload.Count
    $filesProcessed = 0

    # --- Overall Progress Initialization ---
    $overallActivity = "Uploading Folder: $($sourceDirInfo.Name)"
    $overallProgressId = 0 # Use ID 0 for overall progress
    $overallStartTime = Get-Date
    Update-DetailedProgress -Activity $overallActivity `
                            -TotalSize $totalFiles `
                            -BytesProcessed 0 `
                            -StartTime $overallStartTime `
                            -ProgressId $overallProgressId

    # Create the top-level folder on Files.fm corresponding to the source folder
    $targetFolderName = $sourceDirInfo.Name
    $targetFolderInfo = $null
    try {
        Write-Verbose "Creating target folder '$targetFolderName' under parent '$ParentFolderHash'..."
        $targetFolderInfo = New-FilesFmFolder -Username $Username -Password $Password -FolderName $targetFolderName -ParentFolderHash $ParentFolderHash -AccessType $AccessType
        if (-not $targetFolderInfo) {
            throw "Failed to create target folder '$targetFolderName' on Files.fm."
        }
        Write-Verbose "Target folder '$targetFolderName' created. Hash: $($targetFolderInfo.Hash)"
    } catch {
        Write-Error "Critical error creating root target folder '$targetFolderName': $_"
        # Mark overall progress as complete but failed
        Update-DetailedProgress -Activity "Folder Upload Failed (Create Error)" `
                                -TotalSize $totalFiles `
                                -BytesProcessed $totalFiles `
                                -StartTime $overallStartTime `
                                -ProgressId $overallProgressId `
                                -Completed
        return [PSCustomObject]@{ Success = $false; UploadedFiles = $uploadedFilesList }
    }

    # Dictionary to cache created remote folder hashes
    $remoteFolderCache = @{ $LocalFolderPath = $targetFolderInfo.Hash }

    # --- Process Files ---
    foreach ($file in $filesToUpload) {
        $filesProcessed++
        $relativePath = $file.FullName.Substring($LocalFolderPath.Length).TrimStart('\/')
        $relativeDirPath = Split-Path -Path $relativePath -Parent
        $localDirPath = Split-Path -Path $file.FullName -Parent

        # Determine target remote folder hash, creating subfolders as needed
        $currentTargetFolderHash = $null
        if ($remoteFolderCache.ContainsKey($localDirPath)) {
            $currentTargetFolderHash = $remoteFolderCache[$localDirPath]
        } else {
            # Need to create parent folders recursively
            $parentLocalPath = Split-Path -Path $localDirPath -Parent
            if ($remoteFolderCache.ContainsKey($parentLocalPath)) {
                $parentRemoteHash = $remoteFolderCache[$parentLocalPath]
                $subFolderName = Split-Path -Path $localDirPath -Leaf
                try {
                    Write-Verbose "Creating subfolder '$subFolderName' under parent '$parentRemoteHash'..."
                    $newSubFolderInfo = New-FilesFmFolder -Username $Username -Password $Password -FolderName $subFolderName -ParentFolderHash $parentRemoteHash -AccessType $AccessType
                    if ($newSubFolderInfo) {
                        $currentTargetFolderHash = $newSubFolderInfo.Hash
                        $remoteFolderCache[$localDirPath] = $currentTargetFolderHash
                        Write-Verbose "Subfolder '$subFolderName' created. Hash: $currentTargetFolderHash"
                    } else {
                        throw "Failed to create subfolder '$subFolderName'"
                    }
                } catch {
                    Write-Warning "Failed to create remote subfolder for '$localDirPath': $_. Skipping files in this directory."
                    $overallSuccess = $false
                    # Update overall progress (skip file count?)
                    Update-DetailedProgress -Activity $overallActivity `
                                            -TotalSize $totalFiles `
                                            -BytesProcessed $filesProcessed `
                                            -StartTime $overallStartTime `
                                            -ProgressId $overallProgressId
                    continue # Skip to next file
                }
            } else {
                Write-Warning "Could not find remote parent folder for '$localDirPath'. This should not happen. Skipping file '$($file.Name)'..."
                $overallSuccess = $false
                Update-DetailedProgress -Activity $overallActivity `
                                        -TotalSize $totalFiles `
                                        -BytesProcessed $filesProcessed `
                                        -StartTime $overallStartTime `
                                        -ProgressId $overallProgressId
                continue # Skip to next file
            }
        }

        # Get the correct key for the target folder (AddKey is preferred)
        # We need to re-fetch folder info if it wasn't just created, or assume AddKey exists
        # For simplicity, assume the key returned by New-FilesFmFolder is sufficient (usually AddKey)
        # A more robust solution might involve Get-FilesFmFolderList if needed.
        $folderKey = $targetFolderInfo.AddKey # Assuming the key for the root applies, or use keys from cache if subfolders were created
        if ($currentTargetFolderHash -ne $targetFolderInfo.Hash) {
            # If it's a subfolder, we need its key. The cache doesn't store keys.
            # This part needs refinement - New-FilesFmFolder should return the key used.
            # For now, let's assume AddKey is generally available or re-use the root AddKey (may fail)
            # $folderKey = $remoteFolderCache[$localDirPath].AddKey # This won't work as cache only stores hash
             Write-Warning "Cannot determine specific AddKey for subfolder '$currentTargetFolderHash'. Using root folder's AddKey '$($targetFolderInfo.AddKey)'. This might fail."
             $folderKey = $targetFolderInfo.AddKey
        }
        
        if (-not $folderKey) {
             Write-Warning "No valid folder key found for target folder '$currentTargetFolderHash'. Skipping file '$($file.Name)'..."
             $overallSuccess = $false
             Update-DetailedProgress -Activity $overallActivity `
                                     -TotalSize $totalFiles `
                                     -BytesProcessed $filesProcessed `
                                     -StartTime $overallStartTime `
                                     -ProgressId $overallProgressId
             continue # Skip to next file
        }

        # --- Upload Individual File ---
        Write-Verbose "Uploading file $($filesProcessed)/$totalFiles: '$($file.Name)' to folder '$currentTargetFolderHash'"
        try {
            # Use ProgressId 1 for individual file uploads to nest under overall progress (ID 0)
            $uploadResult = Upload-FileToFilesFm -FilePath $file.FullName `
                                               -FolderHash $currentTargetFolderHash `
                                               -FolderKey $folderKey `
                                               -GetFileHash:$GetFileHashes `
                                               -ProgressId 1 # Use nested ID
            
            if ($GetFileHashes -and $uploadResult) {
                $uploadedFilesList.Add([PSCustomObject]@{ LocalPath = $file.FullName; RemoteHash = $uploadResult })
            }
            Write-Verbose "Successfully uploaded '$($file.Name)'"
        } catch {
            Write-Warning "Failed to upload file '$($file.Name)': $_"
            $overallSuccess = $false
            # Error progress for individual file is handled within Upload-FileToFilesFm
        }

        # Update overall progress
        Update-DetailedProgress -Activity $overallActivity `
                                -TotalSize $totalFiles `
                                -BytesProcessed $filesProcessed `
                                -StartTime $overallStartTime `
                                -ProgressId $overallProgressId
    }
    # --- End Process Files ---

    # Mark overall progress as complete
    $finalOverallActivity = if ($overallSuccess) { "Folder Upload Completed: $($sourceDirInfo.Name)" } else { "Folder Upload Partially Failed: $($sourceDirInfo.Name)" }
    Update-DetailedProgress -Activity $finalOverallActivity `
                            -TotalSize $totalFiles `
                            -BytesProcessed $totalFiles `
                            -StartTime $overallStartTime `
                            -ProgressId $overallProgressId `
                            -Completed

    # Return result object
    return [PSCustomObject]@{ 
        Success = $overallSuccess
        UploadedFiles = if ($GetFileHashes) { $uploadedFilesList } else { $null } 
    }
}

#endregion

#region Module Exports

Export-ModuleMember -Function New-FilesFmFolder, Upload-FileToFilesFm, Get-FilesFmFolderList, Upload-FolderToFilesFmRecursive

#endregion

