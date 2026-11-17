# Throne Download Manager for Firefox

On Windows, run these commands from the fork's repository:

```powershell
cargo build --locked -p mdm-app -p mdm-nmhost
.\tools\extension\pack.ps1
.\target\debug\misterdownloadmanager-nmhost.exe --register-firefox
```

Open **about:debugging → This Firefox → Load Temporary Add-on** and select
`target/extension/mdm-firefox.xpi`. Open the extension's toolbar popup and check
its connection status. The temporary add-on lasts until Firefox restarts.
A permanent install in standard Firefox requires signing through Mozilla.

If you run the desktop app with `MDM_DATA_DIR`, launch Firefox with that same
environment variable so the native helper reaches that profile. For development,
use a separate Firefox profile to test download capture.

To remove the Windows native messaging registration, run
`misterdownloadmanager-nmhost.exe --unregister-firefox`.
