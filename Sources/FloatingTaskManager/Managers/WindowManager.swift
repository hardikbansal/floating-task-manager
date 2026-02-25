import SwiftUI
import AppKit

class WindowManager: NSObject, ObservableObject {
    static let shared = WindowManager()

    // Track open windows by list ID
    private var windows: [UUID: NSWindow] = [:]
    // Published set of open list IDs so views can observe open/close state
    @Published private(set) var openWindowIDs: Set<UUID> = []
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
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

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
        windows[UUID()] = window        // floating button has a random key
    }

    // MARK: - List Windows

    /// Open window for list, or bring existing one to front.
    func openOrFocusListWindow(for list: TaskList, store: TaskStore) {
        if let existing = windows[list.id] {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            openWindowIDs.insert(list.id)
            return
        }
        createListWindow(for: list, store: store)
    }

    func createListWindow(for list: TaskList, store: TaskStore) {
        let origin = list.position == .zero ? randomPosition() : list.position
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: list.size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

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
        }
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
