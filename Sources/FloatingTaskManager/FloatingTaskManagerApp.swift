import SwiftUI
import AppKit
import Carbon
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    var store = TaskStore()
    private var globalHotKey: EventHotKeyRef?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory - no dock icon, stays floating
        NSApp.setActivationPolicy(.accessory)

        WindowManager.shared.setTaskStore(store)
        WindowManager.shared.showFloatingButton()
        requestNotificationPermission()

        for list in store.lists {
            WindowManager.shared.createListWindow(for: list, store: store)
        }

        setupSystemTray()
        setupGlobalShortcut()

        // Hide the default WindowGroup window(s) that SwiftUI creates automatically.
        // We only want windows managed by WindowManager to be visible.
        // Status bar items create tiny windows (usually ~30x30), so we ignore those.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for window in NSApp.windows {
                let isManaged = WindowManager.shared.isManaged(window)
                if !isManaged && window.frame.width > 100 { 
                    print("🚪 Closing unmanaged ghost window: '\(window.title)' frame: \(window.frame)")
                    window.close()
                }
            }
        }
    }

    private func setupGlobalShortcut() {
        // Register Cmd+Shift+N as global shortcut to create a new list
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x46544D4E) // 'FTMN'
        hotKeyID.id = 1

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    guard let store = WindowManager.shared.taskStore else { return }
                    store.createNewList()
                    if let lastList = store.lists.last {
                        WindowManager.shared.createListWindow(for: lastList, store: store)
                    }
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        // Cmd (cmdKey = 256) + Shift (shiftKey = 512) + N (keycode 45)
        RegisterEventHotKey(UInt32(45), UInt32(cmdKey + shiftKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &globalHotKey)
    }

    private func setupSystemTray() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "list.bullet.rectangle.portrait", accessibilityDescription: "Floating Task Manager")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show All Lists", action: #selector(showAllLists), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Hide All Windows", action: #selector(hideAllWindows), keyEquivalent: "h"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }

    @objc private func showAllLists() {
        for list in store.lists {
            WindowManager.shared.openOrFocusListWindow(for: list, store: store)
        }
    }

    @objc private func hideAllWindows() {
        for list in store.lists {
            WindowManager.shared.closeListWindow(for: list.id)
        }
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestNotificationPermission() {
        // UNUserNotificationCenter.current() crashes if not running in a proper App Bundle
        // (e.g. when run directly from .build/debug via CLI)
        guard Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") else {
            print("⚠️ Skipped notification permission request: Not running in a proper App Bundle.")
            return
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted.")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct FloatingTaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
