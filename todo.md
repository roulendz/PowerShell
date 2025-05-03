# Project Structure and TODO List

This document outlines the planned structure and tasks for refactoring the PowerShell script and adding files.fm upload functionality.

## Directory Structure

```
.
├── Modules
│   ├── FileUpload
│   │   └── FileUpload.psm1
│   ├── TaskProgressBar
│   │   └── TaskProgressBar.psm1
│   └── ContextMenuManager
│       └── ContextMenuManager.psm1
├── Scripts
│   ├── UploadHandler.ps1
│   ├── UploadGui.ps1
│   └── Main.ps1
├── config.json (Example)
├── README.md
├── .gitignore
└── todo.md
```

## TODO List

- [ ] 0. Create base directory structure.
- [ ] 1. **`FileUpload` Module (`Modules/FileUpload/FileUpload.psm1`)**
    - [x] 1.1. Define functions for files.fm API interaction (`Invoke-RestMethod`).
    - [x] 1.2. Implement authentication (parameter for API key initially).
    - [x] 1.3. Implement `Upload-FileToFilesFm` function (handle `multipart/form-data`).
    - [x] 1.4. Implement `New-FilesFmFolder` function.
    - [x] 1.5. Implement `Get-FilesFmFolderList` function (for GUI).
    - [x] 1.6. Implement recursive folder upload logic (wrapper around `Upload-FileToFilesFm`).
    - [x] 1.7. Add basic error handling and logging.
    - [x] 1.8. Export module functions (`Export-ModuleMember`).
    - [ ] 1.9. Create module manifest (`FileUpload.psd1`) - **Issue:** `pwsh` not found, will attempt later or manually create.
- [ ] 2. **`TaskProgressBar` Module (`Modules/TaskProgressBar/TaskProgressBar.psm1`)**
    - [x] 2.1. Define wrapper functions for `Write-Progress` (`Initialize-Progress`, `Update-Progress`, `Complete-Progress`).
    - [x] 2.2. Make functions generic for reuse.
    - [x] 2.3. Export module functions.
    - [ ] 2.4. Create module manifest (`TaskProgressBar.psd1`).
- [ ] 3. **`ContextMenuManager` Module (`Modules/ContextMenuManager/ContextMenuManager.psm1`)**
    - [x] 3.1. Define `Register-UploadContextMenu` function.
        - [x] 3.1.1. Target `HKCU\Software\Classes\*\shell` (Files).
        - [x] 3.1.2. Target `HKCU\Software\Classes\Directory\shell` (Folders).
        - [x] 3.1.3. Command should call `Scripts/UploadHandler.ps1` with `%1`.
    - [x] 3.2. Define `Unregister-UploadContextMenu` function.
    - [x] 3.3. Handle registry operations safely.
    - [x] 3.4. Add admin rights check/prompt if targeting HKLM (stick to HKCU for now).
    - [x] 3.5. Export module functions.
    - [ ] 3.6. Create module manifest (`ContextMenuManager.psd1`).
- [ ] 4. **`UploadHandler.ps1` Script (`Scripts/UploadHandler.ps1`)**
   - [x] 4.1. Add file path comment.
    - [x] 4.2. Parse input arguments (single file/folder path `%1`).
    - [x] 4.3. Import `FileUpload` module.
    - [x] 4.4. Load configuration (base folder, API key) from `config.json` (or prompt if missing).
    - [ ] 4.5. Implement multiple selections - **Skipped: Context menu passes single item.**
    - [ ] 4.6. Implement parallel upload logic (`ForEach-Object -Parallel -ThrottleLimit 2`) - **Skipped: Depends on multiple selections.**
    - [x] 4.7. Call appropriate upload function from `FileUpload` module (file or folder).
    - [x] 4.8. Add user feedback (e.g., console output, notifications). [ ] 5. **`UploadGui.ps1` Script (`Scripts/UploadGui.ps1`)**
    - [x] 5.1. Add file path comment.
    - [x] 5.2. Create GUI (WPF or WinForms).
    - [x] 5.3. Input field for files.fm API Key (consider secure storage later).
    - [ ] 5.4. Option to select/create base upload folder on files.fm (use `Get-FilesFmFolderList`, `New-FilesFmFolder` from `FileUpload` module) - **Skipped: Added complexity, requires API interaction in GUI.**
    - [ ] 5.5. Option to configure overwrite behavior (if API supports) - **Skipped: API support unclear.**
    - [x] 5.6. Save/Load configuration to `config.json`.
    - [x] 5.7. Button to save settings.
- [ ] 6. **`Main.ps1` Script (`Scripts/Main.ps1`)**
    - [x] 6.1. Add file path comment.
    - [x] 6.2. Add parameters for actions (`-Install`, `-Uninstall`, `-Configure`).
    - [x] 6.3. Import `ContextMenuManager` module.
    - [x] 6.4. Call `Register-UploadContextMenu` or `Unregister-UploadContextMenu`.
    - [x] 6.5. Launch `UploadGui.ps1` for configuration.- [ ] 7. **Supporting Files**
    - [x] 7.1. Create `README.md` with setup and usage instructions.
    - [x] 7.2. Create `.gitignore` file.
    - [x] 7.3. Create example `config.json`.- [ ] 8. **Packaging**
    - [ ] 8.1. Ensure all file path comments are added.
    - [ ] 8.2. Verify all TODOs are complete.
    - [ ] 8.3. Create the final `.zip` archive.
- [ ] 9. **Deliver**
    - [ ] 9.1. Send the `.zip` file to the user with explanations.

