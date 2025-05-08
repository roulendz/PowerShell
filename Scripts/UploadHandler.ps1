param (
    [string]$TargetPath
)

Write-Host "➡️ Uploading from context menu: $TargetPath"

# Get the folder where this script lives
$thisScriptPath = $MyInvocation.MyCommand.Path
$thisScriptDir = Split-Path -Path $thisScriptPath -Parent

# Construct relative paths to function scripts
$moduleRoot = Join-Path $thisScriptDir "..\Modules\FilesFmTools\Functions\Public" | Resolve-Path
. (Join-Path $moduleRoot "Send-FilesFmUpload.ps1")
. (Join-Path $moduleRoot "Send-FilesFmUploadFolder.ps1")

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
