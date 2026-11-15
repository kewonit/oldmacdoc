# Contributing to OldMacDoc

Thanks for helping. Bug reports, fixes, performance work, accessibility improvements and anything that brings the dock closer to the original 3D glass Dock are all welcome.

For anything bigger than a small fix, please open an issue first so we can agree on the approach before you spend time on it.

## Ground rules

These keep the project safe to publish and pleasant to run:

- **No third-party or Apple artwork in the app.** App icons are restyled only on the user's Mac, at runtime. The shelf, Trash, indicators and other art are drawn in code. Don't commit app icons or images extracted from macOS. The one exception is the website: its screenshots show a real dock, so they include real apps' icons as they appear on a Mac.
- **No new permissions.** The app needs no Accessibility, Screen Recording or Full Disk Access, and it should stay that way. If a feature truly needs one, it must be optional and off by default; discuss it in an issue first.
- **Apple's Dock must always come back.** Anything that touches `com.apple.dock` must be backed up and restored on quit, on crash (the watchdog) and from older backups. Add a test for it.
- **Private APIs need a fallback.** The app uses a few private SkyLight calls, loaded at runtime. New ones must fail safely when the symbols are missing, and the reason must be documented in the code.
- **Idle is free.** With the pointer away from the dock, the app should use effectively 0% CPU. Timers and display links must stop when nothing is moving.
- **Be kind.** Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Setting up

You need macOS 14 Sonoma or later, Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
git clone https://github.com/kewonit/oldmacdoc.git
cd oldmacdoc
make project   # generates OldMacDoc.xcodeproj from project.yml
make test      # unit tests
make run       # builds and runs the app (Debug, signed ad hoc)
make icon      # redraws the app icon from the shelf art (only after changing that art)
make dmg-background  # redraws the disk image window the same way
```

The Xcode project is generated and isn't checked in. Edit `project.yml` for target, build-setting and resource changes, then run `make project` again.

### Your own Dock while developing

Running the app parks Apple's Dock (auto-hide, a very long reveal delay, no bouncing, and on a free side edge at its smallest size) and restores it when you quit from the menu bar icon. If a debugging session leaves it parked, run:

```sh
defaults delete com.apple.dock autohide-delay
defaults delete com.apple.dock no-bouncing
defaults delete com.apple.dock orientation
defaults delete com.apple.dock tilesize
defaults delete com.apple.dock magnification
killall Dock
```

That puts it back at the bottom at the default size; set your own size in System Settings.

Your original values are saved in `~/Library/Application Support/OldMacDoc/apple-dock-backup.json` until the app restores them.

### Driving the dock without the mouse

Debug builds accept commands through a distributed notification, so visual changes can be tested without moving your real pointer. See [docs/TESTING.md](docs/TESTING.md).

## Project layout

- `Sources/Core`: logic with no UI. This includes Dock parking, the icon engine, plate detection, layout maths and shelf geometry, and it is compiled into the unit tests. Put new logic here when you can, with a test.
- `Sources/App`: the dock window and view, the model, the menu bar item (which holds the settings) and the WindowServer monitor.
- `Tests`: XCTest unit tests (`make test`).
- `docs`: design notes, testing notes and the release process.
- `website`: the project website, plain HTML and CSS with no build step. Its screenshots are of the running app, your own dock on a transparent background; regenerate them with `scripts/website/capture.sh` while a Debug build runs (`make run`). It needs `cwebp` (`brew install webp`).
- `research_notes` and `reports`: the research behind the design, with sources. These only reference other projects; no third-party code is included in the app.

## Code style

- Swift, 4-space indentation, lines up to about 130 characters (see `.editorconfig`).
- Match the surrounding code. Prefer small, focused types, and keep platform calls out of `Sources/Core` so they stay testable.
- Comments explain *why*, not what. Doc comments go on anything non-obvious, especially workarounds for macOS behaviour; note the macOS version you saw it on.
- Avoid force unwraps outside places where failure is a programming error.
- New warnings are treated as bugs: the build should stay warning-free.

## Tests

Run `make test` before opening a pull request. CI runs the same tests plus a universal Release build on every push and pull request.

UI behaviour that can't be unit-tested, such as Mission Control or the auto-hide slide, should be described in the pull request. Include the macOS version and what you checked; screenshots or a short screen recording help a lot for visual changes.

## Commits and pull requests

- Keep each pull request to one topic.
- Write descriptive commit messages: a short imperative subject (up to about 72 characters), a blank line, then a body that explains what changed and why.
- Update `CHANGELOG.md` under the unreleased version for user-visible changes, and the docs if behaviour changes.
- Fill in the pull request template, including how you tested.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE) that covers this project.
