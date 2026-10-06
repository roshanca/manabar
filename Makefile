.PHONY: gen build install run clean

gen:
	xcodegen

build: gen
	xcodebuild -project ManaBar.xcodeproj -scheme ManaBar -configuration Debug build

install: build
	-pkill -x ManaBar
	rm -rf /Applications/ManaBar.app
	ditto "$$(xcodebuild -project ManaBar.xcodeproj -scheme ManaBar -configuration Debug -showBuildSettings | grep -m1 ' BUILT_PRODUCTS_DIR' | awk '{print $$3}')/ManaBar.app" /Applications/ManaBar.app

run: install
	open /Applications/ManaBar.app

clean:
	rm -rf ManaBar.xcodeproj ~/Library/Developer/Xcode/DerivedData/ManaBar-*
