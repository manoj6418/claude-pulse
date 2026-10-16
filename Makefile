VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
APP := build/ClaudePulse.app
DMG := build/ClaudePulse-$(VERSION).dmg
DEST := $(HOME)/Applications/ClaudePulse.app

.PHONY: app install dmg icon clean

# Release build wrapped as a menu bar app (no Dock icon), ad-hoc signed.
app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp .build/release/ClaudePulse $(APP)/Contents/MacOS/ClaudePulse
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --sign - $(APP) >/dev/null
	@echo "Built $(APP)"

# Copies to ~/Applications and relaunches.
install: app
	-pkill -x ClaudePulse
	mkdir -p $(HOME)/Applications
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	open $(DEST)
	@echo "Installed and launched $(DEST)"

# Drag-to-install disk image: the app plus an Applications shortcut.
dmg: app
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(APP) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Claude Pulse" -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DMG) >/dev/null
	rm -rf build/dmg
	@echo "Built $(DMG)"

# Redraws assets/icon-1024.png and the social preview, then rebuilds AppIcon.icns.
icon:
	swift assets/make-logo.swift assets
	rm -rf build/AppIcon.iconset
	mkdir -p build/AppIcon.iconset
	for s in 16 32 128 256 512; do \
		sips -z $$s $$s assets/icon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}.png >/dev/null; \
		sips -z $$((s*2)) $$((s*2)) assets/icon-1024.png --out build/AppIcon.iconset/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

clean:
	rm -rf build .build
