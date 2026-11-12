#!/usr/bin/env bash
# Builds MagdyBrowser and exports a sideloadable IPA.
# Requires macOS with Xcode 14+ and XcodeGen (brew install xcodegen).
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building"
rm -rf build
xcodebuild \
  -project MagdyBrowser.xcodeproj \
  -scheme MagdyBrowser \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/MagdyBrowser.xcarchive \
  archive

echo "==> Exporting IPA"
xcodebuild \
  -exportArchive \
  -archivePath build/MagdyBrowser.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/ipa

echo "==> Done: build/ipa/MagdyBrowser.ipa"
