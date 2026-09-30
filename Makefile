.PHONY: gen build run clean

gen:
	xcodegen

build: gen
	xcodebuild -project ManaBar.xcodeproj -scheme ManaBar -configuration Debug build

run: build
	open "$$(xcodebuild -project ManaBar.xcodeproj -scheme ManaBar -configuration Debug -showBuildSettings | grep -m1 ' BUILT_PRODUCTS_DIR' | awk '{print $$3}')/ManaBar.app"

clean:
	rm -rf ManaBar.xcodeproj ~/Library/Developer/Xcode/DerivedData/ManaBar-*
