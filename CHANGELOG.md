# Changelog

## 1.2.4

- **Maximised windows stop above the dock.** With Hide automatically off, a window you zoomed, filled (Window > Fill, or a double-click on its title bar) or tiled to a side or a bottom corner ran under the dock: Apple's parked Dock leaves macOS thinking the bottom of the screen is free. Now the window steps up to end above the dock, as it would with Apple's Dock, and windows that were already maximised step up when you turn hiding off. Zoom it again and it goes back where it was. It needs Accessibility, the permission the menus already use.

## 1.2.3

Fixes from a full review of 1.2:

- Apple's hidden Dock menu can no longer be left open at the edge of the screen when an app is slow to answer.
- A busy app can no longer freeze the dock for seconds when you open its menu.
- A login item on a disk that isn't connected no longer makes a menu try to mount it or show a dialog.
- With two copies of an app (Xcode and Xcode beta), Open at Login, Assign To and Show All Windows act on the one you clicked.
- Open at Login shows its new state straight away after you change it.
- A Grid for a folder with one or two items keeps its title, Back and Open in Finder readable.
- A big Downloads folder no longer slows the dock each time an app opens or quits.
- Folders whose names start the same (Doc and Documents) keep their own sort order in a List.
- A folder in the dock that's renamed or deleted is followed properly.

## 1.2.2

- **Open at Login and Assign To are always current.** The menu now reads them from macOS every time it opens, so a change made anywhere else shows up at once.
- **Fewer flickers.** Only an app's own items (like New Window) and its recent files are copied from Apple's hidden Dock, once per app. When you choose one of them, the copy is refreshed in the same step, with no extra flicker.
- **A new switch: Items from Apple's Dock.** Turn it off in the settings panel and Apple's Dock never flickers at the edge of the screen; menus then leave out apps' own items and recent files.

## 1.2.1

- **Menus and stacks follow the pointer at once.** In 1.2.0 the highlight in the right-click menu, and in Fan and Grid stacks, could lag seconds behind the pointer. It now moves with it.

## 1.2.0

- **The original Dock's menus, pointer and all.** Right-click, Control-click or click and hold an icon: its menu hangs above it with the pointer aimed at it, light on Clear Glass and charcoal on Frosted and Smoke, as in Leopard and Snow Leopard. It lists the app's windows, the app's own items (Safari's New Window, Music's controls), Options with Keep in Dock, Open at Login, Show in Finder and Assign To, then Show All Windows, Hide and Quit; hold Option for Hide Others and Force Quit. Finder, the Trash and the separator have theirs too. Press, drag and release, arrow keys and typing all work.
- **Folders, as Leopard's Stacks.** Drop a folder on the dock. Click it for a Fan or a Grid (or a List), drag items out, drop files on it to move them in, and choose how it's sorted and shown from its menu. Downloads hops when a download finishes.
- **Badges.** The red counts apps put on their icons now show on the dock, in Leopard's glossy style.
- **One permission, asked once: Accessibility.** It lets menus show each app's windows and its own items. Everything else works without it, and the settings panel shows how to allow it later.
- **Launchpad no longer closes OldMacDoc.** Clicking Launchpad (Apps on macOS 26 and later), Mission Control, or an app that quits as soon as it opens made the dock quit. They now open without a bounce, as in Apple's Dock, and an app that quits or crashes while opening stops bouncing at once.
- **The settings panel can't crash** when every display goes away while it's open.

## 1.1.0

- **Choose where Mission Control's + goes.** A new Mission Control section in the settings panel puts the Add Desktop button on the left (as before) or on the right.

## 1.0.0

The first release.

- **The 3D glass Dock, back on your Mac.** Three shelves: Clear Glass from Leopard, Frosted from Mountain Lion, and Smoke, a darker take. Icons stand on the glass with their reflections, lights glow under open apps, and the Trash sits past a separator.
- **Magnification** that follows the pointer the way the original did, from a gentle swell to 128 points.
- **One finish for every icon:** gloss, a soft bevel and richer colour, at Off, Subtle or Full. It's applied on your Mac; your apps are never changed. Any app can have an image of your own (right-click → Icon).
- **Works like a Dock:** click to open or switch, drag to rearrange, drag off to remove, drop files on an app to open them, drop apps to add them, and click and hold for each app's menu. Apps that open grow into the dock and those that quit shrink away.
- **Hides automatically** if you want it to, starting the way your Dock was set. Push the pointer into the bottom edge and it's there at once.
- **Settings under the menu bar icon,** in a panel that stays open while you try things: shelf, finish, size, magnification, hiding, lights and Open at Login. The dock stays up while the panel is open, so every change shows straight away.
- **Apple's Dock steps aside** while OldMacDoc runs and comes back exactly as it was when you quit, even if OldMacDoc crashes.
- **Mission Control and App Exposé** show OldMacDoc at the bottom of the screen.
- **Automatic updates,** checked once a day.
- **No permissions needed.** Requires macOS 14 Sonoma or later, on Apple silicon or Intel.
