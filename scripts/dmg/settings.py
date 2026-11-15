# dmgbuild settings for OldMacDoc's disk image: the app and an Applications shortcut standing on the
# glass shelf drawn in background.png, with nothing else in the window. scripts/release.sh runs
#   dmgbuild -s scripts/dmg/settings.py -D app=<path to OldMacDoc.app> OldMacDoc <out.dmg>
# from the repository root. The window size and icon positions must match background.swift.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
name = os.path.basename(app)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")  # the mounted volume's icon

background = "scripts/dmg/background.png"  # and background@2x.png beside it
window_rect = ((200, 200), (640, 452))  # 420 pt of content under a 32 pt title bar
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
label_pos = "bottom"
icon_locations = {name: (180, 236), "Applications": (460, 236)}
