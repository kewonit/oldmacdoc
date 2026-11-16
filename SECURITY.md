# Security policy

## Supported versions

Security fixes go into the latest release and the `main` branch. Please make sure you're on the latest release before reporting.

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Report them privately instead:

1. Preferred: use GitHub's private vulnerability reporting. On the repository's **Security** tab, choose **Report a vulnerability**.
2. Or email the maintainer at kew@edbn.me with "OldMacDoc security" in the subject.

Please include what you found, the steps to reproduce it, the macOS and app versions, and the impact you expect. You'll get an acknowledgement within 7 days and an update on the plan within 14 days. Once a fix is released you'll be credited, unless you'd rather not be.

## Security model

Knowing what the app does helps you judge what counts as a vulnerability.

- **Distribution and updates:** released builds are signed with a Developer ID, use the hardened runtime and are notarized by Apple. Updates go through Sparkle 2 over HTTPS, and each update must carry a valid EdDSA signature matching the public key in the app.
- **No sandbox; Accessibility only:** the app isn't sandboxed, because it has to change Apple's Dock preferences. It asks for Accessibility (once, on first launch) and never for Screen Recording or Full Disk Access. With Accessibility it reads the windows of the app whose menu you open (titles and minimized state, to list and raise them), and it opens, reads and closes that app's menu in Apple's parked Dock to show the app's own items and replay the one you choose. It reads nothing else and sends nothing anywhere.
- **Apple's Dock:** it writes `autohide`, `autohide-delay` and `no-bouncing` in `com.apple.dock`, and, when a side of the main display is free, `orientation`, `tilesize` and `magnification`. It restarts the Dock with `killall Dock`, and keeps the original values in `~/Library/Application Support/OldMacDoc/apple-dock-backup.json`.
- **Crash recovery:** a detached watchdog (`/bin/sh` with a fixed script, `/dev/null` for stdio and no inherited file descriptors) restores the backup if the app dies.
- **Window information:** it reads the window list (owners, levels and sizes, never window contents or titles) and receives WindowServer window events through private SkyLight calls. These are read-only.
- **Badges:** it reads each running app's Dock badge from LaunchServices through private calls, read-only.
- **Files:** it moves files dropped on the Trash to the Trash with `FileManager.trashItem`. Files dropped on a folder in the dock are moved into it (copied from another disk, or with Option), and never replace anything already there. It lists the folders you put in the dock to show their contents. It copies images you choose as icons into Application Support and caches rendered icons in `~/Library/Caches/OldMacDoc`.
- **Automation:** only when you choose **Empty Trash…**, it runs `osascript` to ask Finder to empty the Trash. macOS asks for permission the first time.
- **Network:** the only connections are Sparkle's update checks. There is no telemetry, no analytics and no account.

Examples of what we'd treat as a vulnerability:
- a way to make the app run or load code it shouldn't;
- a way to make it change preferences other than the three Dock keys above;
- tampering with an update so it gets accepted;
- reading or leaking data the app shouldn't.
