# Installer folder handling

Historical installer fix based on 0.1.10.

Setup defaults to `C:\Black Spirit Life` and lets the user choose another folder. Creating the protected default folder may need an admin prompt. The folder gets update access for the user; setup then runs as that user.

An existing registered folder is kept. If it is confirmed missing, setup offers reinstall. Cancelling keeps the registration and saves. An inaccessible, malformed, conflicting or redirected path is not treated as missing.

Recheck the folder before launch. On an early failure, cleanup may remove only the new empty folder created by this attempt. Never use recursive cleanup for this case.

## Checks

Run `NativeInstallerNativeTests`, CTest and `--verify-payload`. `--capture-preview` and `--preview-missing-install` check rendering only.

Registration tests need an isolated account or VM; never overwrite the user's installer registration. Unit and preview checks are not proof that installation succeeded.
