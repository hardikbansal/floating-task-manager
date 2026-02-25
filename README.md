# Floating Task Manager

A premium, minimalist macOS application for managing your tasks in lightweight, floating windows.

![App Icon](Sources/FloatingTaskManager/AppIcon.png)

## Features

- **Floating List Windows**: Keep your tasks visible but out of the way. Windows are borderless, sleek, and support glassmorphism.
- **Global Shortcut**: Quickly create a new list from anywhere using `Cmd+Shift+N`.
- **Priority Sorting**: Organize tasks by priority (High, Medium, Low) with a single click in the header.
- **Multi-Monitor Support**: Seamlessly move all your task windows to a different monitor while preserving your custom layout relative to the screen.
- **Premium Aesthetics**: Adjustable global text size, window opacity, and toggleable shadows for a perfect desk setup.
- **System Tray Integration**: Full control from the macOS menu bar, including quick access to settings and window management.
- **Floating Menu**: A dedicated ＋ button that stays on top for quick list creation and access to all app features.

## Installation

1. Download the latest `FloatingTaskManager.dmg` from the [Releases](https://github.com/hardikbansal/floating-task-manager/releases) page.
2. Drag `FloatingTaskManager.app` to your `Applications` folder.
3. Launch the app. It will appear as a ＋ button in the bottom-right and an icon in your menu bar.

## Usage

- **Create List**: Click the ＋ button or press `Cmd+Shift+N`.
- **Edit Task**: Click any task to edit its content.
- **Format Task**: Hover over a task to see bold, italic, and strikethrough options.
- **Set Priority**: Hover over a task and use the priority selector to categorize it.
- **Sort List**: Hover over a list header and click the sort icon to organize by priority.
- **Settings**: Access settings from the tray icon or the ＋ menu to adjust font size, opacity, and shadows.
- **Move to Monitor**: Use the "Move All to Monitor" option in the menus to shift your workspace to another screen.

## Development

The project is built with **SwiftUI** and **AppKit** for macOS 13.0+.

### Prerequisites
- Xcode 15+
- Swift 5.9+

### Building Locally
Use the provided `run.sh` script to build and launch the app:
```bash
./run.sh
```

## License
MIT License - Copyright (c) 2026 Hardik Bansal
