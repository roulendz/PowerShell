param (
    [string]$TargetPath
)

Write-Host "➡️ Uploading from context menu: $TargetPath"

# Load upload functions (adjust paths as needed)
. "F:\Documents\PowerShell\Modules\FilesFmTools\Functions\Public\Send-FilesFmUpload.ps1"
. "F:\Documents\PowerShell\Modules\FilesFmTools\Functions\Public\Send-FilesFmUploadFolder.ps1"

# Decide if it's a file or folder
if (Test-Path -Path $TargetPath -PathType Leaf) {
    Send-FilesFmUpload -FilePath $TargetPath
}
elseif (Test-Path -Path $TargetPath -PathType Container) {
    Send-FilesFmUploadFolder -FolderPath $TargetPath
}
else {
    Write-Error "❌ Invalid target path: $TargetPath"
}

Read-Host "Press Enter to close"
