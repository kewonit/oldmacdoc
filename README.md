# OldMacDoc

[![CI](https://github.com/kewonit/oldmacdoc/actions/workflows/ci.yml/badge.svg)](https://github.com/kewonit/oldmacdoc/actions/workflows/ci.yml)

The 3D glass Dock, back on your Mac. Free and open source. [oldmacdoc.edbn.me](https://oldmacdoc.edbn.me)

![OldMacDoc on the Clear Glass shelf](website/assets/shelf-clear.webp)

![OldMacDoc on the Frosted shelf](website/assets/shelf-frosted.webp)

![OldMacDoc on the Smoke shelf](website/assets/shelf-smoke.webp)

- Clear Glass, Frosted and Smoke shelves, with reflections and lights under open apps.
- Magnification, auto-hide, drag to rearrange, and one glossy finish for every icon.
- The original Dock's menus, with the pointer: each app's windows and its own items, Options, Show All Windows, Hide and Quit.
- Folders as Leopard Stacks (Fan, Grid or List), and the red badges apps put on their icons.
- Every setting is in a panel under the menu bar icon, and changes show on the dock as you make them.

## Install

Needs macOS 14 Sonoma or later, on Apple silicon or Intel.

1. Download [OldMacDoc.dmg](https://github.com/kewonit/oldmacdoc/releases/latest/download/OldMacDoc.dmg).
2. Drag OldMacDoc to Applications and open it.

While OldMacDoc runs, Apple's Dock steps aside. Choose **Quit** in the panel under the menu bar icon and Apple's Dock comes back exactly as it was. It comes back even if OldMacDoc crashes.

OldMacDoc updates itself; it checks once a day. It asks for one permission, Accessibility, so its menus can show each app's windows and its own items, and so maximised windows stop above the dock while it doesn't hide; everything else works without it.

## Build

```sh
brew install xcodegen
make run
```

- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)
- [Security](SECURITY.md)
- [Design notes](docs/DESIGN.md)
- [MIT License](LICENSE)

Mac, macOS and Dock are trademarks of Apple Inc. OldMacDoc is not affiliated with Apple.
