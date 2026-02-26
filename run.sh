#!/bin/bash

echo "🚀 Building Floating Task Manager..."
swift build

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    
    # Kill any running instance first
    pkill -f FloatingTaskManager 2>/dev/null

    echo "📦 Packaging application bundle..."
    APP_DIR=".build/FloatingTaskManager.app"
    mkdir -p "$APP_DIR/Contents/MacOS"
    mkdir -p "$APP_DIR/Contents/Resources"
    
    cp .build/arm64-apple-macosx/debug/FloatingTaskManager "$APP_DIR/Contents/MacOS/"
    cp Info.plist "$APP_DIR/Contents/" 2>/dev/null || true
    cp Sources/FloatingTaskManager/AppIcon.png "$APP_DIR/Contents/Resources/" 2>/dev/null || true

    echo "🏃 Launching application..."
    open "$APP_DIR"
    echo ""
    echo "✨ Application launched!"
    echo "   • Floating ＋ button appears at the bottom-right of your screen"
    echo "   • Click ＋ to create a new list"
    echo "   • Press ⌘⇧N (Cmd+Shift+N) as a global hotkey to create a new list"
    echo "   • Hover over a task to see bold / italic / strikethrough formatting options"
    echo "   • Drag list windows anywhere — positions are saved automatically"
else
    echo "❌ Build failed."
    exit 1
fi
