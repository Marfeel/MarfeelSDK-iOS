#!/bin/bash

# Check if bump type argument is provided
if [ -z "$1" ]; then
  echo "Usage: ./bump-version.sh <bump_type>"
  echo "  bump_type: 'major', 'minor', or 'patch'"
  exit 1
fi

BUMP_TYPE="$1"

# Validate bump type
if [ "$BUMP_TYPE" != "major" ] && [ "$BUMP_TYPE" != "minor" ] && [ "$BUMP_TYPE" != "patch" ]; then
  echo "Error: bump_type must be 'major', 'minor', or 'patch'"
  exit 1
fi

# Define paths for podspec, Info.plist and the compile-time version constant
PODSPEC_FILE="MarfeelSDK-iOS.podspec"
PLIST_PATH="CompassSDK/Info.plist"
VERSION_SWIFT_PATH="CompassSDK/SDKVersion.swift"

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

# Check if the version constant file exists
if [ ! -f "$VERSION_SWIFT_PATH" ]; then
  echo "SDKVersion.swift not found at $VERSION_SWIFT_PATH"
  exit 1
fi

# Read current version from line 19 of podspec
CURRENT_VERSION=$(sed -n '19p' "$PODSPEC_FILE" | grep -o '"[0-9]*\.[0-9]*\.[0-9]*"' | tr -d '"')

if [ -z "$CURRENT_VERSION" ]; then
  echo "Error: Could not read version from line 19 of $PODSPEC_FILE"
  exit 1
fi

# Parse version components
MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
PATCH=$(echo "$CURRENT_VERSION" | cut -d. -f3)

# Calculate new version based on bump type
if [ "$BUMP_TYPE" == "major" ]; then
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
elif [ "$BUMP_TYPE" == "minor" ]; then
  MINOR=$((MINOR + 1))
  PATCH=0
else
  PATCH=$((PATCH + 1))
fi

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Update the version in the .podspec file
echo "Updating podspec version $CURRENT_VERSION → $NEW_VERSION..."
sed -i '' "s/spec.version      = \".*\"/spec.version      = \"$NEW_VERSION\"/" "$PODSPEC_FILE"

# Update the version in the Info.plist file
echo "Updating Info.plist version..."
plutil -replace CFBundleShortVersionString -string "$NEW_VERSION" "$PLIST_PATH"

# Update the compile-time version constant (sent in the User-Agent header)
echo "Updating SDKVersion.swift version..."
sed -i '' "s/^let SDK_VERSION = \".*\"$/let SDK_VERSION = \"$NEW_VERSION\"/" "$VERSION_SWIFT_PATH"

if ! grep -q "^let SDK_VERSION = \"$NEW_VERSION\"$" "$VERSION_SWIFT_PATH"; then
  echo "Failed to update SDK_VERSION in $VERSION_SWIFT_PATH"
  exit 1
fi

# Check if the changes were successful
if [ $? -eq 0 ]; then
  echo "Version updated successfully in podspec, Info.plist and SDKVersion.swift"
else
  echo "Failed to update version in podspec or Info.plist"
  exit 1
fi
