import SwiftUI

struct FloatingButtonView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @State private var isHovered = false
    @State private var showPanel = false

    var body: some View {
        Button(action: { showPanel.toggle() }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hue: 0.6, saturation: 0.8, brightness: 0.9),
                                     Color(hue: 0.55, saturation: 0.9, brightness: 0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)

                Image(systemName: showPanel ? "xmark" : "list.bullet.rectangle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .animation(.spring(response: 0.3), value: showPanel)
            }
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .animation(.spring(response: 0.25), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPanel, arrowEdge: .top) {
            ListsPanel(showPanel: $showPanel)
                .environmentObject(store)
                .environmentObject(windowManager)
        }
    }
}

// MARK: - All Lists Panel

struct ListsPanel: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @Binding var showPanel: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("My Lists")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button(action: createNewList) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .help("New List (⌘⇧N)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if store.lists.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No lists yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Create New List", action: createNewList)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(store.lists) { list in
                            ListPanelRow(list: list)
                                .environmentObject(store)
                                .environmentObject(windowManager)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 320)
            }

            Divider()

            // Settings Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11))
                    Text("Text Size: \(Int(baseFontSize))pt")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { baseFontSize },
                    set: { baseFontSize = $0 }
                ), in: 10...24, step: 1)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // Menu Actions
            VStack(spacing: 0) {
                MenuActionButton(title: "Show All Lists", icon: "macwindow.on.rectangle") {
                    for list in store.lists { windowManager.openOrFocusListWindow(for: list, store: store) }
                    showPanel = false
                }
                MenuActionButton(title: "Hide All Windows", icon: "window.casement") {
                    for list in store.lists { windowManager.closeListWindow(for: list.id) }
                    showPanel = false
                }
                
                let screens = NSScreen.screens
                if screens.count > 1 {
                    Divider().padding(.horizontal, 10)
                    ForEach(0..<screens.count, id: \.self) { index in
                        MenuActionButton(title: "Move All to Screen \(index + 1)", icon: "display") {
                            windowManager.moveAllWindows(to: screens[index])
                            showPanel = false
                        }
                    }
                }
                
                Divider().padding(.horizontal, 10)
                
                MenuActionButton(title: "Settings...", icon: "gearshape") {
                    windowManager.showSettingsWindowManual()
                    showPanel = false
                }
                MenuActionButton(title: "Quit", icon: "power", color: .red) {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 260)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
    }
    
    private func createNewList() {
        store.createNewList()
        if let last = store.lists.last {
            windowManager.openOrFocusListWindow(for: last, store: store)
        }
        showPanel = false
    }
}

struct MenuActionButton: View {
    let title: String
    let icon: String
    var color: Color = .primary
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundColor(color.opacity(isHovered ? 1.0 : 0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - List Row in Panel

struct ListPanelRow: View {
    @ObservedObject var list: TaskList
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @State private var isHovered = false

    var isOpen: Bool { windowManager.isWindowOpen(for: list.id) }

    var body: some View {
        HStack(spacing: 10) {
            // Colored dot
            Circle()
                .fill(list.color.swiftUIColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(list.title.isEmpty ? "Untitled" : list.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(list.items.count) item\(list.items.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Show/hide window toggle
            Button(action: {
                if isOpen {
                    windowManager.closeListWindow(for: list.id)
                } else {
                    windowManager.openOrFocusListWindow(for: list, store: store)
                }
            }) {
                Image(systemName: isOpen ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundColor(isOpen ? .blue : .secondary.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
            .help(isOpen ? "Hide window" : "Show window")

            // Delete list
            Button(action: {
                windowManager.closeListWindow(for: list.id)
                store.deleteList(list)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red.opacity(0.75))
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete list")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.primary.opacity(0.07) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            windowManager.openOrFocusListWindow(for: list, store: store)
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
