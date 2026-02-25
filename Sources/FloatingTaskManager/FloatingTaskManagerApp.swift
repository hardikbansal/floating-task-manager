import SwiftUI
import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var store = TaskStore()
    private var globalHotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as accessory - no dock icon, stays floating
        NSApp.setActivationPolicy(.accessory)

        WindowManager.shared.setTaskStore(store)
        WindowManager.shared.showFloatingButton()

        for list in store.lists {
            WindowManager.shared.createListWindow(for: list, store: store)
        }

        setupGlobalShortcut()

        // Hide the default WindowGroup window
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if window.title == "Floating Task Manager" {
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct FloatingTaskManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
