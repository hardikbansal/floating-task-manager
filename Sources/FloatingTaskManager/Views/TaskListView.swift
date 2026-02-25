import SwiftUI
import AppKit

// MARK: - Task List View

struct TaskListView: View {
    @ObservedObject var list: TaskList
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @State private var newItemContent: String = ""
    @State private var isHoveringHeader = false
    @State private var showColorPicker = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 8) {
                // Compact color swatch button
                Button(action: { showColorPicker.toggle() }) {
                    Circle()
                        .fill(list.color.swiftUIColor)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        .shadow(color: list.color.swiftUIColor.opacity(0.5), radius: 3)
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    ColorSwatchPicker(selected: $list.color, onPick: { store.save() })
                }

                TextField("List Title", text: $list.title)
                    .font(.system(size: 14, weight: .semibold))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit { store.save() }

                Spacer()

                Button(action: { windowManager.closeListWindow(for: list.id) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(isHoveringHeader ? 1.0 : 0.45)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(list.color.swiftUIColor.opacity(0.12))
            .onHover { isHoveringHeader = $0 }

            Divider().opacity(0.25)

            // ── Items (ScrollView avoids AppKit row-height errors) ──
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 1) {
                    ForEach($list.items) { $item in
                        TaskItemRow(item: $item,
                                    onDelete: { list.items.removeAll { $0.id == item.id }; store.save() },
                                    onChange:  { store.save() })
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
            }

            Divider().opacity(0.2)

            // ── Add task row ────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundColor(list.color.swiftUIColor.opacity(0.8))
                    .font(.system(size: 13))
                TextField("Add task...", text: $newItemContent)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 13))
                    .onSubmit { addItem() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider().opacity(0.2)

            // ── Footer ──────────────────────────────────────────────
            HStack {
                let done = list.items.filter(\.isCompleted).count
                let total = list.items.count
                Text(total == 0 ? "No tasks" : "\(done) / \(total) done")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("⌘⇧N  new list")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .frame(minWidth: 270, minHeight: 300)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func addItem() {
        let trimmed = newItemContent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.items.append(TaskItem(content: trimmed))
        newItemContent = ""
        store.save()
    }
}

// MARK: - Compact Color Swatch Picker

struct ColorSwatchPicker: View {
    @Binding var selected: ListColor
    var onPick: () -> Void

    let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            Text("List Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ListColor.allCases, id: \.self) { color in
                    Button(action: { selected = color; onPick() }) {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 24, height: 24)
                            if selected == color {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(12)
        .background(VisualEffectView(material: .menu, blendingMode: .behindWindow))
    }
}

// MARK: - Task Item Row

struct TaskItemRow: View {
    @Binding var item: TaskItem
    var onDelete: () -> Void
    var onChange: () -> Void

    @State private var rowHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox
            Button(action: { item.isCompleted.toggle(); onChange() }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .blue : .secondary)
                    .font(.system(size: 15))
            }
            .buttonStyle(PlainButtonStyle())

            // Text field
            TextField("Task...", text: $item.content, onCommit: onChange)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 13, weight: item.isBold ? .bold : .regular))
                .italic(item.isItalic)
                .strikethrough(item.isCompleted || item.isStrikethrough, color: .secondary)
                .foregroundColor(item.isCompleted ? .secondary : .primary)

            // Format toolbar — single onHover on row keeps this flicker-free
            if rowHovered {
                HStack(spacing: 2) {
                    FormatToggle(icon: "bold",           active: item.isBold)            { item.isBold.toggle();           onChange() }
                    FormatToggle(icon: "italic",         active: item.isItalic)          { item.isItalic.toggle();         onChange() }
                    FormatToggle(icon: "strikethrough",  active: item.isStrikethrough)   { item.isStrikethrough.toggle();  onChange() }
                    Divider().frame(height: 12).padding(.horizontal, 1)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(.red.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.1)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { rowHovered = $0 }   // single hover — no flicker
    }
}

// MARK: - Format Toggle

struct FormatToggle: View {
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: active ? .bold : .regular))
                .foregroundColor(active ? .blue : .secondary)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(active ? Color.blue.opacity(0.15) : Color.clear))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Visual Effect

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
