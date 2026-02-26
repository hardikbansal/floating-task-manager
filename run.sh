#!/bin/bash
set -euo pipefail

echo "🚀 Building Floating Task Manager..."
swift build
echo "✅ Build successful!"

# Kill any running instance first
pkill -f FloatingTaskManager 2>/dev/null || true

echo "📦 Packaging application bundle..."
APP_DIR=".build/FloatingTaskManager.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

BIN_PATH="$(find .build -type f -path "*/debug/FloatingTaskManager" | head -n 1)"
if [ -z "${BIN_PATH}" ]; then
    echo "❌ Could not find built binary under .build/*/debug/FloatingTaskManager"
    exit 1
fi

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/FloatingTaskManager"
cp Info.plist "$APP_DIR/Contents/" 2>/dev/null || true
cp Sources/FloatingTaskManager/AppIcon.png "$APP_DIR/Contents/Resources/" 2>/dev/null || true
if [ -f "GoogleService-Info.plist" ]; then
    cp GoogleService-Info.plist "$APP_DIR/Contents/Resources/"
elif [ -f "Sources/FloatingTaskManager/GoogleService-Info.plist" ]; then
    cp Sources/FloatingTaskManager/GoogleService-Info.plist "$APP_DIR/Contents/Resources/GoogleService-Info.plist"
else
    echo "⚠️  GoogleService-Info.plist not found in project root or Sources/FloatingTaskManager."
fi

echo "💿 Creating DMG..."
DMG_PATH=".build/FloatingTaskManager.dmg"
STAGING_DIR="$(mktemp -d)"
cp -R "$APP_DIR" "$STAGING_DIR/"
hdiutil create -volname "FloatingTaskManager" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR"
echo "✅ DMG created at $DMG_PATH"

echo "📥 Installing app to /Applications..."
MOUNT_POINT="/tmp/FloatingTaskManagerMount.$$"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_PATH" -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null

ditto "$MOUNT_POINT/FloatingTaskManager.app" "/Applications/FloatingTaskManager.app"
hdiutil detach "$MOUNT_POINT" -quiet || true
rmdir "$MOUNT_POINT" 2>/dev/null || true
echo "✅ Installed to /Applications/FloatingTaskManager.app"

echo "🔐 Disabling keychain-backed token storage for local run.sh installs..."
defaults write com.hardikbansal.FloatingTaskManager ftm.disableKeychain -bool true

echo "🏃 Launching application from /Applications..."
open "/Applications/FloatingTaskManager.app"
echo ""
echo "✨ Application launched!"
echo "   • Installed via DMG into /Applications"
echo "   • Keychain token prompt disabled for this app (uses UserDefaults fallback)"
echo "   • Floating ＋ button appears at the bottom-right of your screen"
echo "   • Click ＋ to create a new list"
echo "   • Press ⌘⇧N (Cmd+Shift+N) as a global hotkey to create a new list"
