# FilesFm PowerShell Uploader

A PowerShell module that makes uploading files and folders to Files.fm quick and easy. Features Windows Explorer context menu integration for seamless uploads.

![Files.fm PowerShell Uploader Banner](https://failiem.lv/api/placeholder/460/215)

## Features

- ✅ Upload files directly from Windows Explorer context menu
- 📁 Upload entire folders with automatic recreation of folder structure
- 🔄 Smart handling of duplicate files (skip, replace, or upload as copy)
- 📋 Automatic copying of sharing links to clipboard
- 🔐 Secure credential storage

## Installation

1. Clone this repository:

```powershell
git clone https://github.com/roulendz/PowerShell
cd Documents\PowerShell
```

2. Create a configuration file with your Files.fm credentials:

```powershell
# Copy the example file
Copy-Item files.fm.json.example files.fm.json

# Edit the file with your credentials
notepad files.fm.json
```

3. Register the context menu (requires administrative privileges):

```powershell
# Import the module
Import-Module .\Modules\ContextMenuManager\ContextMenuManager.psm1

# Register the context menu
Register-UploadContextMenu
```
# Unregister the context menu
Unregister-UploadContextMenu
```
## Usage

### Context Menu

After installation, simply right-click on any file or folder in Windows Explorer and select "Upload to Files.fm".

### PowerShell Commands

The module provides two main functions:

#### Upload a single file

```powershell
Import-Module .\Modules\FilesFmTools\FilesFmTools.psm1
Send-FilesFmUpload -FilePath "C:\path\to\your\file.mp3"
```

#### Upload an entire folder

```powershell
Import-Module .\Modules\FilesFmTools\FilesFmTools.psm1
Send-FilesFmUploadFolder -FolderPath "C:\path\to\your\folder"
```

## Configuration

The module requires a configuration file named `files.fm.json` in the root directory with the following structure:

```json
{
  "Username": "your_filesfm_username",
  "Password": "your_filesfm_password",
  "BaseFolderHash": "your_folder_hash"
}
```

- **Username**: Your Files.fm account username/email
- **Password**: Your Files.fm account password
- **BaseFolderHash**: The hash of the folder where files should be uploaded

If the configuration file is not present, you will be prompted to enter these details when running a command.

## Security Notes

- The configuration file contains sensitive information. Add it to `.gitignore` to prevent accidental commits.
- The module securely handles credentials during API interactions.

## Uninstallation

To remove the context menu integration:

```powershell
Import-Module .\Modules\ContextMenuManager\ContextMenuManager.psm1
Unregister-UploadContextMenu
```

## Project Structure

```
filesfm-powershell-uploader/
├── .gitignore                  # Git ignore file
├── files.fm.json.example       # Example configuration
├── Modules/
│   ├── ContextMenuManager/     # Windows Explorer integration
│   │   └── ContextMenuManager.psm1
│   └── FilesFmTools/           # Core upload functionality
│       ├── FilesFmTools.psd1
│       ├── FilesFmTools.psm1
│       └── Functions/
│           └── Public/
│               ├── Send-FilesFmUpload.ps1
│               └── Send-FilesFmUploadFolder.ps1
└── Scripts/
    └── UploadHandler.ps1       # Context menu handler
```

## License

[MIT License](LICENSE)

## Credits

Created by AI with 💙