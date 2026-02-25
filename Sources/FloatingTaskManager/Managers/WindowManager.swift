import SwiftUI
import AppKit

class WindowManager: NSObject, ObservableObject {
    static let shared = WindowManager()

    // Track open windows by list ID
    private var windows: [UUID: NSWindow] = [:]
    // Published set of open list IDs so views can observe open/close state
    @Published private(set) var openWindowIDs: Set<UUID> = []
    private var floatingButtonID: UUID?
    private var settingsWindow: NSWindow?
    var taskStore: TaskStore?

    func setTaskStore(_ store: TaskStore) {
        self.taskStore = store
    }

    // MARK: - Query

    func isWindowOpen(for listID: UUID) -> Bool {
        openWindowIDs.contains(listID)
    }

    /// Check if a window is managed by this manager (either a list window or the floating button)
    func isManaged(_ window: NSWindow) -> Bool {
        windows.values.contains(window)
    }

    // MARK: - Floating Button

    func showFloatingButton() {
        guard let store = taskStore else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120), // Larger canvas to avoid shadow clipping
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false // SwiftUI handles this now
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isRestorable = false

        window.contentView = NSHostingView(rootView:
            FloatingButtonView()
                .environmentObject(store)
                .environmentObject(self)
        )

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - 80, y: f.minY + 20))
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        let buttonID = UUID()
        self.floatingButtonID = buttonID
        windows[buttonID] = window
    }

    // MARK: - List Windows

    /// Open window for list, or bring existing one to front.
    func openOrFocusListWindow(for list: TaskList, store: TaskStore) {
        if let existing = windows[list.id] {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            openWindowIDs.insert(list.id)
            if !list.isVisible {
                list.isVisible = true
                store.save()
            }
            return
        }
        createListWindow(for: list, store: store)
    }

    func createListWindow(for list: TaskList, store: TaskStore) {
        class BorderlessListWindow: NSWindow {
            override var canBecomeKey: Bool { return true }
            override var canBecomeMain: Bool { return true }
        }

        let origin = list.position == .zero ? randomPosition() : list.position
        let window = BorderlessListWindow(

            contentRect: NSRect(origin: origin, size: list.size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = UserDefaults.standard.bool(forKey: "enableShadows")
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.isRestorable = false
        window.isReleasedWhenClosed = false

        window.contentView = NSHostingView(rootView:
            TaskListView(list: list)
                .environmentObject(store)
                .environmentObject(self)
        )

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        windows[list.id] = window
        openWindowIDs.insert(list.id)
        
        if !list.isVisible {
            list.isVisible = true
            store.save()
        }

        // Persist position/size as user moves/resizes
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
                list.position = window.frame.origin
                store.save()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                list.size = window.frame.size
                store.save()
        }
        // Track when user clicks the native red close button
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.windows.removeValue(forKey: list.id)
                self?.openWindowIDs.remove(list.id)
                
                // If the user closed it, persist that it's hidden
                if list.isVisible {
                    list.isVisible = false
                    store.save()
                    print("💾 Persisted isVisible=false for list: \(list.title)")
                }
        }
    }

    /// Refresh appearance of all managed windows
    func updateWindowsAppearance() {
        let enableShadows = UserDefaults.standard.bool(forKey: "enableShadows")
        for (id, window) in windows {
            if id == floatingButtonID { continue }
            window.hasShadow = enableShadows
            window.invalidateShadow()
        }
    }

    func showSettingsWindowManual() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Floating Task Manager Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .windowBackgroundColor
        
        window.contentView = NSHostingView(rootView:
            SettingsView()
                .padding()
                .frame(width: 480, height: 320)
        )

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.settingsWindow = nil
        }
    }

    /// Move all managed windows to the specified screen preserving relative positions
    func moveAllWindows(to targetScreen: NSScreen) {
        let targetVisibleFrame = targetScreen.visibleFrame
        let managedWindows = windows.filter { $0.key != floatingButtonID }
        
        for (id, window) in managedWindows {
            let currentScreen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let currentVisibleFrame = currentScreen.visibleFrame
            
            // Calculate relative position as percentages of the visible frame
            let relativeX = (window.frame.minX - currentVisibleFrame.minX) / currentVisibleFrame.width
            let relativeY = (window.frame.minY - currentVisibleFrame.minY) / currentVisibleFrame.height
            
            // Apply percentages to the target visible frame
            var newX = targetVisibleFrame.minX + (relativeX * targetVisibleFrame.width)
            var newY = targetVisibleFrame.minY + (relativeY * targetVisibleFrame.height)
            
            // Ensure the window stays within the target screen's visible area
            newX = max(targetVisibleFrame.minX, min(newX, targetVisibleFrame.maxX - window.frame.width))
            newY = max(targetVisibleFrame.minY, min(newY, targetVisibleFrame.maxY - window.frame.height))
            
            let newOrigin = NSPoint(x: newX, y: newY)
            window.setFrameOrigin(newOrigin)
            
            // Update the store if it's a list
            if let list = taskStore?.lists.first(where: { $0.id == id }) {
                list.position = newOrigin
            }
        }
        taskStore?.save()
    }

    /// Close a list window without deleting the list.
    func closeListWindow(for listID: UUID) {
        windows[listID]?.close()
        // willCloseNotification handles dictionary cleanup
    }

    // MARK: - Helpers

    private func randomPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let f = screen.visibleFrame
        let x = CGFloat.random(in: f.minX + 60 ... max(f.minX + 60, f.maxX - 360))
        let y = CGFloat.random(in: f.minY + 60 ... max(f.minY + 60, f.maxY - 460))
        return NSPoint(x: x, y: y)
    }
}
