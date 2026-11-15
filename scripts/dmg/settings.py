# dmgbuild settings for OldMacDoc's disk image: the app and an Applications shortcut standing on the
# glass shelf drawn in background.png, with nothing else in the window. scripts/dmg/build.sh runs
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to OldMacDoc.app> OldMacDoc <out.dmg>
# from the repository root. The window size and icon positions must match background.swift; the
# rest (no toolbar, sidebar or status bar; labels under the icons) is dmgbuild's default.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")  # the mounted volume's icon

background = "scripts/dmg/background.png"  # and background@2x.png beside it
window_rect = ((200, 200), (640, 452))  # 420 pt of content under a 32 pt title bar
icon_size = 128  # what the shelf is drawn for
text_size = 13
icon_locations = {
    name: (180, 236),
    "Applications": (460, 236),
    # Well below the window, so they stay off the picture for anyone who shows hidden files.
    ".background.tiff": (100, 900),
    ".VolumeIcon.icns": (220, 900),
    ".DS_Store": (340, 900),
    ".fseventsd": (460, 900),
    ".Trashes": (580, 900),
}
