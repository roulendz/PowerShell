# Files.fm PowerShell Uploader

This project provides a set of PowerShell modules and scripts to upload files and folders to Files.fm via a context menu item in Windows Explorer.

## Features

*   **Modular Design:** Functionality is split into reusable modules:
    *   `FileUpload`: Handles interaction with the Files.fm API (creating folders, uploading files/folders).
    *   `TaskProgressBar`: Provides reusable functions for displaying nested progress bars.
    *   `ContextMenuManager`: Manages the registration/unregistration of the Windows Explorer context menu item.
*   **Context Menu Integration:** Easily upload files or folders by right-clicking them in Explorer.
*   **GUI Configuration:** A simple GUI allows setting up Files.fm credentials, the base upload folder hash, and its corresponding key.
*   **Recursive Folder Upload:** Uploads entire folder structures, creating corresponding subfolders on Files.fm using your credentials.

## Structure

```
.
├── Modules
│   ├── FileUpload
│   │   ├── FileUpload.psd1 (Manifest - Manual Creation Needed)
│   │   └── FileUpload.psm1 (Core API logic)
│   ├── TaskProgressBar
│   │   ├── TaskProgressBar.psd1 (Manifest - Manual Creation Needed)
│   │   └── TaskProgressBar.psm1 (Progress bar functions)
│   └── ContextMenuManager
│       ├── ContextMenuManager.psd1 (Manifest - Manual Creation Needed)
│       └── ContextMenuManager.psm1 (Registry management)
├── Scripts
│   ├── Main.ps1 (Entry point for install/uninstall/configure)
│   ├── UploadGui.ps1 (Configuration GUI)
│   └── UploadHandler.ps1 (Script executed by context menu)
├── config.json (Stores configuration - **WARNING: Plain text credentials/keys**)
├── README.md (This file)
├── .gitignore
└── todo.md (Development checklist)
```

## Requirements

*   Windows Operating System
*   PowerShell 6.0 or later (due to `Invoke-RestMethod -Form` usage in `FileUpload` module)
*   .NET Desktop Runtime (for the GUI)
*   A Files.fm account

## Setup

1.  **Extract:** Extract the contents of the zip file to a location on your computer (e.g., `C:\Tools\FilesFmUploader`).
2.  **Configure:**
    *   Open PowerShell.
    *   Navigate to the `Scripts` directory within the extracted folder (e.g., `cd C:\Tools\FilesFmUploader\Scripts`).
    *   Run the configuration GUI: `.\Main.ps1 -Configure`
    *   Enter the following details:
        *   **Files.fm Username:** Your account username.
        *   **Files.fm Password:** Your account password.
        *   **Base Folder Hash:** The hash of the *existing* base folder on Files.fm where you want uploads to go. You might need to manually create this base folder on files.fm first and get its hash from the URL (e.g., the `xxxxxxx` part in `https://files.fm/u/xxxxxxx`).
        *   **Folder Key:** The **AddKey** or **EditKey** specifically for the **Base Folder Hash** entered above. This key is required by the API (`save_file.php`) when uploading *single files* directly into this existing base folder. You can usually find this key in the folder details on Files.fm or via their API.
    *   Click **Save**. This will create/update the `config.json` file in the root directory.
    *   **Security Warning:** The `config.json` file stores your password and folder key in plain text. For better security, consider modifying the scripts to use the `Microsoft.PowerShell.SecretManagement` module.
3.  **Install Context Menu:**
    *   In the same PowerShell window (still in the `Scripts` directory), run: `.\Main.ps1 -Install`
    *   This registers the "Upload to Files.fm" option in the context menu for the current user.

## Usage

*   Right-click on any file or folder in Windows Explorer.
*   Select "Upload to Files.fm".
*   The `UploadHandler.ps1` script will run in the background, read the configuration, and perform the upload:
    *   **Single File:** Uploads the file directly into the configured `BaseFolderHash` using the provided `FolderKey`.
    *   **Folder:** Creates a new subfolder with the same name under the `BaseFolderHash` (using your Username/Password). It then recursively uploads the contents of the local folder into this newly created subfolder on Files.fm.
*   A notification message will appear upon completion or failure.

## Uninstallation

1.  Open PowerShell.
2.  Navigate to the `Scripts` directory.
3.  Run: `.\Main.ps1 -Uninstall`
4.  This removes the context menu item.
5.  You can then safely delete the extracted folder.

## Manual Manifest Creation (Optional but Recommended)

The automatic creation of module manifests (`.psd1` files) failed because `pwsh` was not found in the execution environment. You can create these manually for better module management:

1.  For each module in the `Modules` directory (`FileUpload`, `TaskProgressBar`, `ContextMenuManager`):
    *   Create a text file with the same name as the module and a `.psd1` extension (e.g., `FileUpload.psd1`) inside the module's folder.
    *   Paste the following template into the file, adjusting the `RootModule`, `GUID` (generate a new one using `[guid]::NewGuid()`), `FunctionsToExport`, and other details as needed.

```powershell
# Example Manifest Template (e.g., for FileUpload.psd1)
@{
    RootModule = 'FileUpload.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'YOUR_NEW_GUID_HERE' # Generate using [guid]::NewGuid()
    Author = 'Manus AI'
    CompanyName = 'N/A'
    Copyright = '(c) 2025 Manus AI'
    Description = 'Module for interacting with the Files.fm API.'
    PowerShellVersion = '6.0'
    FunctionsToExport = @(
        'New-FilesFmFolder',
        'Upload-FileToFilesFm',
        'Get-FilesFmFolderList',
        'Upload-FolderToFilesFmRecursive'
    )
    # Add other manifest keys as needed (e.g., RequiredModules, PrivateData)
}
```

Repeat for `TaskProgressBar.psd1` and `ContextMenuManager.psd1`, adjusting `RootModule`, `GUID`, `Description`, and `FunctionsToExport` accordingly.

