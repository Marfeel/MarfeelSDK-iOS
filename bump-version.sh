#!/bin/bash

# Check if version argument is provided
if [ -z "$1" ]; then
  echo "Usage: ./bump_version.sh <new_version>"
  exit 1
fi

NEW_VERSION="$1"

# Define paths for podspec and Info.plist
PODSPEC_FILE="MarfeelSDK-iOS.podspec"
PLIST_PATH="CompassSDK/Info.plist"

# Check if the podspec file exists
if [ ! -f "$PODSPEC_FILE" ]; then
  echo "Podspec file not found at $PODSPEC_FILE"
  exit 1
fi

# Check if the Info.plist file exists
if [ ! -f "$PLIST_PATH" ]; then
  echo "Info.plist file not found at $PLIST_PATH"
  exit 1
fi

# Update the version in the .podspec file
echo "Updating podspec version..."
sed -i '' "s/spec.version      = \".*\"/spec.version      = \"$NEW_VERSION\"/" "$PODSPEC_FILE"

# Update the version in the Info.plist file
echo "Updating Info.plist version..."
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$PLIST_PATH"

# Check if the changes were successful
if [ $? -eq 0 ]; then
  echo "Version updated successfully in both podspec and Info.plist"
else
  echo "Failed to update version in podspec or Info.plist"
  exit 1
fi


echo "Version bump complete"
