APP = OldMacDoc
DERIVED = build/DerivedData
SPM = build/spm

.PHONY: project build run test release clean icon

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug \
	  -derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM) build | xcbeautify 2>/dev/null || \
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -configuration Debug \
	  -derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM) -quiet build

# Runs the dock. Apple's Dock is parked while it runs and restored when it quits.
run: build
	open $(DERIVED)/Build/Products/Debug/$(APP).app

test: project
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) -derivedDataPath $(DERIVED) \
	  -clonedSourcePackagesDirPath $(SPM) -quiet test

release: project
	scripts/release.sh $(VERSION)

clean:
	rm -rf build $(APP).xcodeproj

# Redraws the app icon from the dock's own shelf art (the PNGs are committed; run after changing the art).
ICON_SOURCES = scripts/icon/render.swift Sources/App/ShelfArt.swift \
  Sources/App/ShelfLook.swift Sources/Core/DockLayout.swift Sources/Core/Bitmap.swift Sources/Core/Support.swift
icon:
	mkdir -p build
	swiftc -O -o build/render-icon $(ICON_SOURCES)
	build/render-icon Resources/Assets.xcassets
