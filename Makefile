VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG := build/ClaudePulse-$(VERSION).dmg

.PHONY: app install dmg clean

app:
	./scripts/build-app.sh

install:
	./scripts/build-app.sh --install

# Drag-to-install disk image: the app plus an Applications shortcut.
dmg: app
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R build/ClaudePulse.app build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "Claude Pulse" -srcfolder build/dmg -fs HFS+ -format UDZO -ov $(DMG) >/dev/null
	rm -rf build/dmg
	@echo "Built $(DMG)"

clean:
	rm -rf build .build
