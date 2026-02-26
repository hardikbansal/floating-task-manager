import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class WindowManager: NSObject, ObservableObject {
    static let shared = WindowManager()

    // Track open windows by list ID
    #if os(macOS)
    private var windows: [UUID: NSWindow] = [:]
    private var floatingButtonID: UUID?
    private var settingsWindow: NSWindow?
    #endif
    // Published set of open list IDs so views can observe open/close state
    @Published private(set) var openWindowIDs: Set<UUID> = []
    let MERGED_LIST_ID = UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000000")!
    var taskStore: TaskStore?

    func setTaskStore(_ store: TaskStore) {
        self.taskStore = store
    }

    // MARK: - Query

    func isWindowOpen(for listID: UUID) -> Bool {
        #if os(macOS)
        return openWindowIDs.contains(listID)
        #else
        return false // Transitioning to NavigationStack on iOS
        #endif
    }

    /// Check if a window is managed by this manager (either a list window or the floating button)
    #if os(macOS)
    func isManaged(_ window: NSWindow) -> Bool {
        windows.values.contains(window)
    }
    #endif

    // MARK: - Floating Button

    func showFloatingButton() {
        #if os(macOS)
        guard let store = taskStore else { return }

        class BorderlessFloatingButtonWindow: NSWindow {
            override var canBecomeKey: Bool { true }
            override var canBecomeMain: Bool { false }
        }

        let window = BorderlessFloatingButtonWindow(
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

        let targetScreen: NSScreen? = {
            let mouseLocation = NSEvent.mouseLocation
            if let underMouse = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                return underMouse
            }
            return NSScreen.main ?? NSScreen.screens.first
        }()

        if let screen = targetScreen {
            let f = screen.visibleFrame
            let x = max(f.minX + 16, f.maxX - window.frame.width - 16)
            let y = f.minY + 16
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        let buttonID = UUID()
        self.floatingButtonID = buttonID
        windows[buttonID] = window
        #endif
    }

    // MARK: - List Windows

    /// Open window for list, or bring existing one to front.
    func openOrFocusListWindow(for list: TaskList, store: TaskStore) {
        #if os(macOS)
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
        #else
        // iOS handled by navigation
        #endif
    }

    func createListWindow(for list: TaskList, store: TaskStore) {
        #if os(macOS)
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
        #endif
    }

    // MARK: - Merged List Window

    func openOrFocusMergedListWindow(store: TaskStore) {
        #if os(macOS)
        if let existing = windows[MERGED_LIST_ID] {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            openWindowIDs.insert(MERGED_LIST_ID)
            return
        }

        class BorderlessMergedWindow: NSWindow {
            override var canBecomeKey: Bool { return true }
            override var canBecomeMain: Bool { return true }
        }

        let windowSize = store.mergedListSize
        let origin = store.mergedListPosition == .zero ? topCenterPosition(for: windowSize) : store.mergedListPosition
        let window = BorderlessMergedWindow(
            contentRect: NSRect(origin: origin, size: windowSize),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.level = .normal
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.hasShadow = UserDefaults.standard.bool(forKey: "enableShadows")
        window.collectionBehavior = []
        window.isRestorable = false
        window.isReleasedWhenClosed = false

        window.contentView = NSHostingView(rootView:
            MergedTaskListView()
                .environmentObject(store)
                .environmentObject(self)
        )

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        windows[MERGED_LIST_ID] = window
        openWindowIDs.insert(MERGED_LIST_ID)

        // Persist position/size
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { _ in
                store.mergedListPosition = window.frame.origin
                store.save()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                store.mergedListSize = window.frame.size
                store.save()
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.windows.removeValue(forKey: self?.MERGED_LIST_ID ?? UUID())
                self?.openWindowIDs.remove(self?.MERGED_LIST_ID ?? UUID())
        }
        #endif
    }

    /// Refresh appearance of all managed windows
    func updateWindowsAppearance() {
        #if os(macOS)
        let enableShadows = UserDefaults.standard.bool(forKey: "enableShadows")
        for (id, window) in windows {
            if id == floatingButtonID { continue }
            window.hasShadow = enableShadows
            window.invalidateShadow()
        }
        #endif
    }

    func showSettingsWindowManual() {
        #if os(macOS)
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Floating Task Manager Settings"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .windowBackgroundColor

        let store = taskStore ?? TaskStore()
        window.contentView = NSHostingView(rootView:
            SettingsView()
                .environmentObject(store)
                .padding()
                .frame(width: 520, height: 500)
        )

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.settingsWindow = nil
        }
        #endif
    }

    /// Move all managed windows to the specified screen preserving relative positions
    #if os(macOS)
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
    #endif

    /// Close a list window without deleting the list.
    func closeListWindow(for listID: UUID) {
        #if os(macOS)
        windows[listID]?.close()
        #endif
    }

    // MARK: - Helpers

    #if os(macOS)
    private func topCenterPosition(for size: CGSize) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let f = screen.visibleFrame
        let x = f.minX + (f.width - size.width) / 2
        let y = f.maxY - size.height - 40 // 40pt margin from top to stay below menu bar area typically
        return NSPoint(x: x, y: y)
    }

    private func randomPosition() -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let f = screen.visibleFrame
        let x = CGFloat.random(in: f.minX + 60 ... max(f.minX + 60, f.maxX - 360))
        let y = CGFloat.random(in: f.minY + 60 ... max(f.minY + 60, f.maxY - 460))
        return NSPoint(x: x, y: y)
    }
    #endif
}
