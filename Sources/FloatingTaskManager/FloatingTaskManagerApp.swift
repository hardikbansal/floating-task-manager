import SwiftUI
#if os(iOS)
import FirebaseCore
#endif
#if os(macOS)
import AppKit
import Carbon
#else
import UIKit
#endif
import UserNotifications

#if os(iOS)
class AppDelegateIOS: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        print("🔵 [AppDelegate] application didFinishLaunching — configuring Firebase")
        FirebaseApp.configure()
        print("🔵 [AppDelegate] FirebaseApp.configure() done — app=\(FirebaseApp.app() != nil ? "ok" : "FAILED")")
        requestNotificationPermission()
        return true
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("🔵 [AppDelegate] Notification permission granted.")
            } else if let error = error {
                print("🔴 [AppDelegate] Notification permission error: \(error.localizedDescription)")
            } else {
                print("🟡 [AppDelegate] Notification permission denied by user.")
            }
        }
    }
}
#endif

#if os(macOS)
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
        setupAppIcon()

        for list in store.lists where list.isVisible {
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
        
        // Move to Monitor Menu
        let screens = NSScreen.screens
        if screens.count > 1 {
            let monitorMenu = NSMenu()
            for (index, _) in screens.enumerated() {
                let item = NSMenuItem(title: "Screen \(index + 1)", action: #selector(moveToScreen(_:)), keyEquivalent: "")
                item.tag = index
                monitorMenu.addItem(item)
            }
            let monitorItem = NSMenuItem(title: "Move All to Monitor", action: nil, keyEquivalent: "")
            monitorItem.submenu = monitorMenu
            menu.addItem(monitorItem)
        }
        
        // Debug Menu
        let debugMenu = NSMenu()
        debugMenu.addItem(NSMenuItem(title: "Print Window List to Logs", action: #selector(debugListWindows), keyEquivalent: ""))
        debugMenu.addItem(NSMenuItem(title: "Force Cleanup Ghost Windows", action: #selector(forceCleanup), keyEquivalent: ""))
        let debugItem = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        
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
        WindowManager.shared.showSettingsWindowManual()
    }

    @objc private func moveToScreen(_ sender: NSMenuItem) {
        let screens = NSScreen.screens
        if sender.tag < screens.count {
            WindowManager.shared.moveAllWindows(to: screens[sender.tag])
        }
    }

    @objc private func debugListWindows() {
        print("🔍 Debug: Window List")
        for window in NSApp.windows {
            let isManaged = WindowManager.shared.isManaged(window)
            print("🪟 [\(isManaged ? "MANAGED" : "UNMANAGED")] '\(window.title)' | frame: \(window.frame) | level: \(window.level.rawValue) | alpha: \(window.alphaValue) | isVisible: \(window.isVisible)")
        }
    }

    @objc private func forceCleanup() {
        print("🧹 Force cleaning up ghost windows...")
        for window in NSApp.windows {
            if !WindowManager.shared.isManaged(window) && window.frame.width > 100 {
                print("🚪 Closing ghost window: '\(window.title)'")
                window.close()
            }
        }
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

    private func setupAppIcon() {
        // 1. Try asset catalog (works when built via Xcode with Assets.xcassets)
        if let image = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = image
            return
        }

        // 2. Try bundle resources – works when run via `swift run` / SPM
        if let url = Bundle.main.url(forResource: "AppIcon-1024", withExtension: "png") ??
                     Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
            return
        }

        // 3. Fallback: path inside .app bundle
        let bundlePath = Bundle.main.bundlePath
        let candidates = [
            (bundlePath as NSString).appendingPathComponent("Contents/Resources/AppIcon.png"),
            (bundlePath as NSString).appendingPathComponent("Contents/Resources/AppIcon-1024.png"),
            "Sources/FloatingTaskManager/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
            "Sources/FloatingTaskManager/AppIcon.png"
        ]
        for path in candidates {
            if let image = NSImage(contentsOfFile: path) {
                NSApp.applicationIconImage = image
                return
            }
        }
    }
}
#endif

@main
struct FloatingTaskManagerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegateIOS.self) var appDelegate
    #endif

    @StateObject var store = TaskStore()
    @StateObject var windowManager = WindowManager.shared

    var body: some Scene {
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            MainIOSView()
                .environmentObject(store)
                .environmentObject(windowManager)
        }
        #endif
    }
}
