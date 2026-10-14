# Screenshotee

A tiny macOS background app that watches your screenshot folder and copies every new
screenshot to the clipboard. No Dock icon, no dependencies, one Swift file.

- Reads the destination from the system setting (`com.apple.screencapture` `location`) at startup, so it follows
  whatever you chose in Screenshot options (defaults to `~/Desktop`).
- Works with cloud-synced folders (OneDrive, Dropbox, iCloud, Google Drive) by combining kernel
  notifications with a 2-second poll, since File Provider folders don't reliably deliver events.
- Only files created after launch are copied.

## Build & run

Requires Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
open build/Screenshotee.app
build/Screenshotee.app/Contents/MacOS/screenshotee --install   # start at login
```

`--uninstall` removes the login item. Restart the app after changing the screenshot location.

## Why an app bundle and not a launchd script?

macOS privacy protection (TCC) guards cloud-storage folders (`~/Library/CloudStorage`),
Desktop, Documents, and Downloads. A launchd job running a shell script is attributed to the
interpreter (`/bin/bash`), which has no stable identity, can't show a permission prompt, and
fails silently. A signed `.app` with its own bundle ID gets its own prompt and its own entry in
System Settings > Privacy & Security > Files and Folders (or Full Disk Access).

If the folder can't be read, grant access there, or add `Screenshotee.app` to Full Disk Access, then relaunch.

## Signing note

`build.sh` signs ad-hoc by default, so macOS may ask for permission again after each rebuild.
Set `SIGN_ID="Apple Development: Your Name (TEAMID)"` for a stable identity.

## License

MIT
