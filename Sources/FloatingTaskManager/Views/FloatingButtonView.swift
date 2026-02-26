import SwiftUI

#if os(macOS)

struct FloatingButtonView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @State private var isHovered = false
    @State private var showPanel = false

    var body: some View {
        Button(action: { showPanel.toggle() }) {
            ZStack {
                // Frosty Backdrop Blur
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 58, height: 58)
                    .blur(radius: 2)
                
                // Main Pristine Orb (Frosted White)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(white: 0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        // Refractive Frosty Edge
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 0.5)
                    )
                
                
                // Inner "Brilliance" Glow
                Circle()
                    .fill(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: 28))
                    .opacity(0.6)
                    .frame(width: 50, height: 50)
                
                // Top Glass Shell Refraction
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.9), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 44, height: 26)
                    .offset(y: -14)
                    .blur(radius: 0.8)

                // Vibrant Plus Icon
                Image(systemName: showPanel ? "xmark" : "plus")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.blue)
                    .shadow(color: .blue.opacity(0.3), radius: 4)
                    .rotationEffect(.degrees(showPanel ? 90 : 0))
            }
            .frame(width: 120, height: 120)
            .background(Color.clear)
            .contentShape(Circle())
            .shadow(color: .black.opacity(0.12), radius: 15, x: 0, y: 10)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showPanel)
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
                Text("Command Center")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
                Spacer()
                Button(action: createNewList) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.blue)
                }
                .buttonStyle(PremiumButtonStyle())
                .help("New List (⌘⇧N)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.1)

            if store.lists.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No Active Lists")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Button("Initialize First List", action: createNewList)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(store.lists) { list in
                            ListPanelRow(list: list)
                                .environmentObject(store)
                                .environmentObject(windowManager)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 340)
            }

            Divider().opacity(0.1)

            // Settings Widget Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11, weight: .bold))
                    Text("System Font Size")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    Text("\(Int(baseFontSize))pt")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                }
                .foregroundColor(.secondary)

                Slider(value: $baseFontSize, in: 10...24, step: 1)
                    .controlSize(.mini)
                    .accentColor(.blue)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.04))
                    .padding(8)
            )

            Divider().opacity(0.1)

            // Grid Actions
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                QuickActionButton(title: "Show All", icon: "eye.fill") {
                    for list in store.lists { windowManager.openOrFocusListWindow(for: list, store: store) }
                    showPanel = false
                }
                QuickActionButton(title: "Hide All", icon: "eye.slash.fill") {
                    for list in store.lists { windowManager.closeListWindow(for: list.id) }
                    showPanel = false
                }
                QuickActionButton(title: "Settings", icon: "gearshape.fill") {
                    windowManager.showSettingsWindowManual()
                    showPanel = false
                }
                QuickActionButton(title: "Merged", icon: "square.grid.2x2.fill") {
                    windowManager.openOrFocusMergedListWindow(store: store)
                    showPanel = false
                }
                
                let screens = NSScreen.screens
                if screens.count > 1 {
                    ForEach(0..<screens.count, id: \.self) { index in
                        QuickActionButton(title: "To Screen \(index + 1)", icon: "display") {
                            windowManager.moveAllWindows(to: screens[index])
                            showPanel = false
                        }
                    }
                }
                
                QuickActionButton(title: "Quit", icon: "power", color: .red) {
                    NSApp.terminate(nil)
                }

            }
            .padding(12)
        }
        .frame(width: 280)
        .background(GlassBackground(cornerRadius: 20))
    }
    
    private func createNewList() {
        withAnimation(.spring()) {
            store.createNewList()
            if let last = store.lists.last {
                windowManager.openOrFocusListWindow(for: last, store: store)
            }
            showPanel = false
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    var color: Color = .primary
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(isHovered ? 0.15 : 0.06))
            )
            .foregroundColor(color.opacity(isHovered ? 1.0 : 0.8))
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
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
        HStack(spacing: 12) {
            // Colored dot
            Circle()
                .fill(list.color.swiftUIColor)
                .frame(width: 8, height: 8)
                .shadow(color: list.color.swiftUIColor.opacity(0.4), radius: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(list.title.isEmpty ? "Untitled List" : list.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(list.items.count) items")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: {
                    withAnimation(.spring()) {
                        if isOpen {
                            windowManager.closeListWindow(for: list.id)
                        } else {
                            windowManager.openOrFocusListWindow(for: list, store: store)
                        }
                    }
                }) {
                    Image(systemName: isOpen ? "eye.fill" : "eye.slash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isOpen ? .blue : .secondary.opacity(0.4))
                }
                .buttonStyle(PremiumButtonStyle())

                Button(action: {
                    withAnimation(.spring()) {
                        windowManager.closeListWindow(for: list.id)
                        store.deleteList(list)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(PremiumButtonStyle())
            }
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            windowManager.openOrFocusListWindow(for: list, store: store)
        }
        .onHover { isHovered = $0 }
    }
}

#endif
