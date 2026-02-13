.PHONY: run clean build kill install

# Derived data location
DERIVED_DATA = ~/Library/Developer/Xcode/DerivedData/Macaroni-gklvuqkiyhhyvzbltwavemxlsszm
BUILD_DIR = $(DERIVED_DATA)/Build/Products/Debug
APP = $(BUILD_DIR)/Macaroni.app

# Kill running instances, clean build, and run
run: kill clean build
	@echo "Launching Macaroni..."
	@open $(APP)

# Kill any running Macaroni instances
kill:
	@echo "Killing running instances..."
	@pkill -x Macaroni 2>/dev/null || true
	@sleep 0.5

# Clean build artifacts
clean:
	@echo "Cleaning..."
	@xcodebuild -project Macaroni.xcodeproj -scheme Macaroni -configuration Debug clean 2>/dev/null || true

# Build the project
build:
	@echo "Building..."
	@xcodebuild -project Macaroni.xcodeproj -scheme Macaroni -configuration Debug build 2>&1 | grep -E "(\*\* BUILD|error:)" || true

# Install to /Applications (clean replace)
install: kill clean build
	@echo "Installing to /Applications..."
	@rm -rf /Applications/Macaroni.app
	@cp -R $(APP) /Applications/Macaroni.app
	@echo "Installed. Launching..."
	@open /Applications/Macaroni.app
