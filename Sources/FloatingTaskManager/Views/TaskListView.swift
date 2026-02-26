#if os(macOS)
import AppKit
#endif
import SwiftUI
import UserNotifications

private func durationBadgeText(minutes: Int?) -> String? {
    guard let minutes, minutes > 0 else { return nil }
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(mins)m"
}

// MARK: - Task List View

struct TaskListView: View {
    @ObservedObject var list: TaskList
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    @State private var newItemContent: String = ""
    @State private var showColorPicker = false

    var body: some View {
        #if os(iOS)
        iosBody
        #else
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────
            HStack(spacing: 12) {
                // Compact color swatch button
                Button(action: { showColorPicker.toggle() }) {
                    Circle()
                        .fill(list.color.swiftUIColor)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: list.color.swiftUIColor.opacity(0.3), radius: 4)
                }
                .buttonStyle(PremiumButtonStyle())
                .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                    ColorSwatchPicker(selected: $list.color, onPick: { store.touch(list) })
                }

                TextField("List Title", text: $list.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .textFieldStyle(PlainTextFieldStyle())
                    .onSubmit { store.touch(list) }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: 200, alignment: .leading)

                Spacer()

                HStack(spacing: 8) {
                    // Sort button
                    Button(action: { 
                        withAnimation(PremiumTheme.spring()) {
                            list.sortDescending.toggle()
                            list.sortItemsByPriority()
                            store.touch(list)
                        }
                    }) {
                        Image(systemName: list.sortDescending ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(list.color.swiftUIColor)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    #if os(macOS)
                    .help(list.sortDescending ? "Sort: High to Low" : "Sort: Low to High")
                    #endif

                    // Close/Back button
                    #if os(macOS)
                    Button(action: { windowManager.closeListWindow(for: list.id) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    #endif
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                headerBackground
            )

            Divider().opacity(0.1)

            // ── Items ──
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Active Tasks
                    LazyVStack(spacing: 2) {
                        ForEach($list.items.filter { !$0.wrappedValue.isCompleted }) { $item in
                            TaskItemRow(item: $item,
                                        onDelete: { deleteItem(item.id) },
                                        onChange: { store.touchItem(in: list) })
                        }
                    }

                    // Completed Tasks
                    let completedItems = $list.items.filter { $0.wrappedValue.isCompleted }
                    if !completedItems.isEmpty {
                        DisclosureGroup {
                            LazyVStack(spacing: 2) {
                                ForEach(completedItems) { $item in
                                    TaskItemRow(item: $item,
                                                onDelete: { deleteItem(item.id) },
                                                onChange: { store.touchItem(in: list) })
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            HStack {
                                Text("Completed")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(completedItems.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                            }
                        }
                        .accentColor(.secondary)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.1)

            // ── Add task row ────────────────────────────────────────
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundColor(list.color.swiftUIColor)
                    .font(.system(size: 14, weight: .bold))
                
                TextField("Add a task...", text: $newItemContent)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: baseFontSize, weight: .medium, design: .rounded))
                    .onSubmit { 
                        withAnimation(.spring()) {
                            addItem()
                        }
                    }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.02))

            Divider().opacity(0.1)

            // ── Footer ──────────────────────────────────────────────
            HStack {
                let done = list.items.filter(\.isCompleted).count
                let total = list.items.count
                Text(total == 0 ? "No tasks" : "\(done) of \(total) completed")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                #if os(macOS)
                Text("⌘⇧N  New List")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.4))
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        #if os(macOS)
        .frame(minWidth: 280, minHeight: 320)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .containerShape(RoundedRectangle(cornerRadius: 16))
        .opacity(windowOpacity)
        #else
        .background(Color(.systemBackground))
        #endif
        .onChange(of: enableShadows) { newValue in
            #if os(macOS)
            windowManager.updateWindowsAppearance()
            #endif
        }
        .onChange(of: windowOpacity) { _ in
            #if os(macOS)
            windowManager.updateWindowsAppearance()
            #endif
        }
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        VStack(spacing: 0) {
            // ── Premium Header ──
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button(action: { showColorPicker.toggle() }) {
                        Circle()
                            .fill(list.color.swiftUIColor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                            .shadow(color: list.color.swiftUIColor.opacity(0.4), radius: 4)
                    }
                    .sheet(isPresented: $showColorPicker) {
                        NavigationStack {
                            ColorSwatchPicker(selected: $list.color, onPick: { store.touch(list) })
                                .navigationTitle("List Color")
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("Done") { showColorPicker = false }
                                    }
                                }
                        }
                        .presentationDetents([.height(200)])
                    }

                    TextField("List Title", text: $list.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .onSubmit { store.touch(list) }

                    Spacer()

                    // Sort priority button
                    Button(action: {
                        withAnimation(.spring()) {
                            list.sortDescending.toggle()
                            list.sortItemsByPriority()
                            store.touch(list)
                        }
                    }) {
                        Image(systemName: list.sortDescending ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(list.color.swiftUIColor)
                    }

                    // Edit button for drag-to-reorder
                    EditButton()
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(list.color.swiftUIColor)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(headerBackground)

            Divider().opacity(0.3)

            // ── Task Items ──
            List {
                // Active tasks — use item IDs so .onMove works
                let activeItems = list.items.filter { !$0.isCompleted }
                Section {
                    ForEach(activeItems) { item in
                        if let index = list.items.firstIndex(where: { $0.id == item.id }) {
                            IOSTaskRow(item: $list.items[index],
                                       listColor: list.color.swiftUIColor,
                                       onDelete: { deleteItem(item.id) },
                                       onChange: { store.touchItem(in: list) })
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.visible)
                                .listRowBackground(Color(uiColor: .systemBackground))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        withAnimation(.spring()) { deleteItem(item.id) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        withAnimation(.spring()) {
                                            var mutableItem = list.items[index]
                                            cyclePriority(&mutableItem)
                                            mutableItem.lastModified = Date()
                                            list.items[index] = mutableItem
                                            list.lastModified = Date()
                                            store.save()
                                        }
                                    } label: {
                                        Label("Priority", systemImage: "flag.fill")
                                    }
                                    .tint(list.items[index].priority.color)
                                }
                        }
                    }
                    .onMove { source, destination in
                        moveActiveItems(from: source, to: destination)
                    }
                }

                // Completed tasks
                let completedItems = list.items.filter { $0.isCompleted }
                if !completedItems.isEmpty {
                    Section {
                        ForEach(completedItems) { item in
                            if let index = list.items.firstIndex(where: { $0.id == item.id }) {
                                IOSTaskRow(item: $list.items[index],
                                           listColor: list.color.swiftUIColor,
                                           onDelete: { deleteItem(item.id) },
                                           onChange: { store.touchItem(in: list) })
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.visible)
                                    .listRowBackground(Color(uiColor: .systemBackground))
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            withAnimation(.spring()) { deleteItem(item.id) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    } header: {
                        HStack {
                            Text("Completed")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Text("\(completedItems.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.05)))

                            // Clear completed button
                            Button {
                                withAnimation(.spring()) { clearCompleted() }
                            } label: {
                                Text("Clear")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.3)

            // ── Add Task Row ──
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .foregroundColor(list.color.swiftUIColor)
                    .font(.system(size: 14, weight: .bold))

                TextField("Add a task...", text: $newItemContent)
                    .font(.system(size: baseFontSize, weight: .medium, design: .rounded))
                    .onSubmit {
                        withAnimation(.spring()) { addItem() }
                    }

                if !newItemContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button(action: { withAnimation(.spring()) { addItem() } }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(list.color.swiftUIColor)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider().opacity(0.1)

            // ── Footer ──
            HStack {
                let done = list.items.filter(\.isCompleted).count
                let total = list.items.count
                Text(total == 0 ? "No tasks" : "\(done) of \(total) completed")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Move active (non-completed) tasks by remapping indices into the full items array.
    private func moveActiveItems(from source: IndexSet, to destination: Int) {
        var activeIds = list.items.filter { !$0.isCompleted }.map { $0.id }
        activeIds.move(fromOffsets: source, toOffset: destination)

        // Rebuild items: active tasks in new order, then completed tasks appended
        let completedItems = list.items.filter { $0.isCompleted }
        let itemById = Dictionary(uniqueKeysWithValues: list.items.map { ($0.id, $0) })
        list.items = activeIds.compactMap { itemById[$0] } + completedItems
        store.touch(list)
    }

    /// Remove all completed tasks from this list.
    private func clearCompleted() {
        let ids = list.items.filter { $0.isCompleted }.map { $0.id }
        for id in ids {
            list.deletedItemIDs[id] = Date()
        }
        list.items.removeAll { $0.isCompleted }
        store.touch(list)
    }

    private func cyclePriority(_ item: inout TaskItem) {
        switch item.priority {
        case .none: item.priority = .low
        case .low: item.priority = .medium
        case .medium: item.priority = .high
        case .high: item.priority = .none
        }
    }
    #endif

    private var taskSummaryText: String {
        let done = list.items.filter(\.isCompleted).count
        let total = list.items.count
        return total == 0 ? "No tasks" : "\(done) of \(total) completed"
    }

    @ViewBuilder
    private var headerBackground: some View {
        MeshGradientView(baseColor: list.color.swiftUIColor)
            .opacity(0.15)
            .overlay {
                #if os(macOS)
                VisualEffectView(material: .headerView, blendingMode: .withinWindow).opacity(0.5)
                #else
                VisualEffectView(material: .systemUltraThinMaterial).opacity(0.5)
                #endif
            }
    }

    private func addItem() {
        let trimmed = newItemContent.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.items.append(TaskItem(content: trimmed))
        newItemContent = ""
        store.touch(list)
    }

    private func deleteItem(_ id: UUID) {
        withAnimation(.spring()) {
            list.deletedItemIDs[id] = Date()   // tombstone — prevents remote resurrection
            list.items.removeAll { $0.id == id }
            store.touch(list)
        }
    }
}

// MARK: - Compact Color Swatch Picker

struct ColorSwatchPicker: View {
    @Binding var selected: ListColor
    var onPick: () -> Void

    let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5)

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
        .background(
            colorPickerBackground
        )
    }

    @ViewBuilder
    private var colorPickerBackground: some View {
        #if os(macOS)
        VisualEffectView(material: .menu, blendingMode: .behindWindow)
        #else
        VisualEffectView(material: .systemThinMaterial)
        #endif
    }
}

struct TaskItemRow: View {
    @Binding var item: TaskItem
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    var onDelete: () -> Void
    var onChange: () -> Void

    /// Stamps item.lastModified so the last-writer-wins merge keeps this change.
    private func stampAndSave() {
        item.lastModified = Date()
        onChange()
    }

    @State private var rowHovered = false
    @State private var showReminderPicker = false
    @State private var tempReminderDate = Date()
    @State private var customEstimateText = ""
    @State private var showDetailsInspector = false

    private var notificationCenter: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Checkbox
            ModernCheckbox(isChecked: $item.isCompleted, color: .blue)
                .onChange(of: item.isCompleted) { newValue in
                    if newValue {
                        removeReminder()
                    }
                    stampAndSave()
                }

            // Reminder Indicator
            if let reminder = item.reminderDate, !item.isCompleted {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))
                    .foregroundColor(reminder < Date() ? .red : .blue)
                    #if os(macOS)
                    .help("Reminder: \(reminder.formatted())")
                    #endif
            }

            VStack(alignment: .leading, spacing: 5) {
                // Text field
                ZStack(alignment: .leading) {
                    // Invisible text just to render a perfectly sized strikethrough line
                    if item.isCompleted || item.isStrikethrough {
                        Text(item.content.isEmpty ? "Task..." : item.content)
                            .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .medium, design: item.isItalic ? .default : .rounded))
                            .italic(item.isItalic)
                            .foregroundColor(.clear)
                            .overlay(
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.8))
                                    .frame(height: 1)
                                    .offset(y: 1),
                                alignment: .center
                            )
                    }

                    TextField("Task...", text: $item.content, onCommit: stampAndSave)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .medium, design: item.isItalic ? .default : .rounded))
                        .italic(item.isItalic)
                        .foregroundColor(item.isCompleted ? .secondary.opacity(0.6) : .primary)
                }
                .id("\(item.id)-\(item.isBold)-\(item.isItalic)-\(item.isStrikethrough)-\(item.isCompleted)")
                .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.status.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(item.status.color.opacity(0.12))
                                .overlay(Capsule().stroke(item.status.color.opacity(0.22), lineWidth: 0.5))
                        )
                        .foregroundColor(item.status.color)
                        .fixedSize()

                    if item.priority != .none {
                        Text(item.priority.title.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(item.priority.color.opacity(0.12))
                                    .overlay(Capsule().stroke(item.priority.color.opacity(0.2), lineWidth: 0.5))
                            )
                            .foregroundColor(item.priority.color)
                            .fixedSize()
                    }

                    if let duration = durationBadgeText(minutes: item.estimatedMinutes) {
                        Text(duration)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.10))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
                            )
                            .foregroundColor(.blue)
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            }
            .layoutPriority(1)

            // Format toolbar
            #if os(macOS)
            let showToolbar = rowHovered || showReminderPicker || showDetailsInspector
            #else
            let showToolbar = false
            #endif

            if showToolbar {
                HStack(spacing: 10) {
                    // Reminder Button
                    Button(action: { 
                        tempReminderDate = item.reminderDate ?? Date().addingTimeInterval(3600)
                        showReminderPicker.toggle() 
                    }) {
                        Image(systemName: item.reminderDate == nil ? "bell" : "bell.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(item.reminderDate == nil ? .secondary : .blue)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(item.reminderDate != nil ? Color.blue.opacity(0.1) : Color.clear))
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .popover(isPresented: $showReminderPicker) {
                        VStack(spacing: 12) {
                            Text("Set Reminder")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            
                            DatePicker("", selection: $tempReminderDate, displayedComponents: [.date])
                                .datePickerStyle(GraphicalDatePickerStyle())
                                .labelsHidden()
                                .frame(width: 260)
                                
                            DatePicker("Time", selection: $tempReminderDate, displayedComponents: [.hourAndMinute])
                                .labelsHidden()
                                .frame(width: 150)

                            HStack(spacing: 8) {
                                PresetPill(title: "+1h") { tempReminderDate = Date().addingTimeInterval(3600) }
                                PresetPill(title: "+6h") { tempReminderDate = Date().addingTimeInterval(6 * 3600) }
                                PresetPill(title: "+1d") { tempReminderDate = Date().addingTimeInterval(24 * 3600) }
                                PresetPill(title: "9AM") {
                                    var nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                                    nextDay = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: nextDay) ?? nextDay
                                    tempReminderDate = nextDay
                                }
                            }
                            .padding(.top, 4)

                            HStack {
                                if item.reminderDate != nil {
                                    Button("Clear") {
                                        removeReminder()
                                        showReminderPicker = false
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(.red)
                                }
                                Spacer()
                                Button("Cancel") { showReminderPicker = false }
                                    .buttonStyle(.borderless)
                                Button("Set") {
                                    setReminder(at: tempReminderDate)
                                    showReminderPicker = false
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                        .padding(16)
                    }

                    Button {
                        customEstimateText = item.estimatedMinutes.map(String.init) ?? ""
                        showDetailsInspector = true
                    } label: {
                        Label("Details", systemImage: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .popover(isPresented: $showDetailsInspector, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Task Details")
                                .font(.system(size: 13, weight: .bold, design: .rounded))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Formatting")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Toggle("Bold", isOn: Binding(
                                    get: { item.isBold },
                                    set: { item.isBold = $0; stampAndSave() }
                                ))
                                Toggle("Italic", isOn: Binding(
                                    get: { item.isItalic },
                                    set: { item.isItalic = $0; stampAndSave() }
                                ))
                                Toggle("Strikethrough", isOn: Binding(
                                    get: { item.isStrikethrough },
                                    set: { item.isStrikethrough = $0; stampAndSave() }
                                ))
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Status")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Picker("Status", selection: Binding(
                                    get: { item.status },
                                    set: { item.status = $0; stampAndSave() }
                                )) {
                                    ForEach(TaskStatus.allCases, id: \.self) { status in
                                        Label(status.title, systemImage: status.icon).tag(status)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Priority")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Picker("Priority", selection: Binding(
                                    get: { item.priority },
                                    set: { item.priority = $0; stampAndSave() }
                                )) {
                                    ForEach(Priority.allCases, id: \.self) { p in
                                        Text(p.title).tag(p)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Estimate (minutes)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    TextField("45", text: $customEstimateText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 72)
                                    Button("Set") {
                                        let minutes = Int(customEstimateText.trimmingCharacters(in: .whitespacesAndNewlines))
                                        item.estimatedMinutes = (minutes ?? 0) > 0 ? minutes : nil
                                        stampAndSave()
                                    }
                                    .buttonStyle(.bordered)
                                    if item.estimatedMinutes != nil {
                                        Button("Clear") {
                                            item.estimatedMinutes = nil
                                            customEstimateText = ""
                                            stampAndSave()
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundColor(.red)
                                    }
                                }
                                HStack(spacing: 6) {
                                    ForEach([15, 30, 45, 60], id: \.self) { mins in
                                        Button(durationBadgeText(minutes: mins) ?? "\(mins)m") {
                                            item.estimatedMinutes = mins
                                            customEstimateText = "\(mins)"
                                            stampAndSave()
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                                        .foregroundColor(.blue)
                                    }
                                }
                            }

                            Divider()
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete Task", systemImage: "trash")
                            }
                        }
                        .frame(width: 300)
                        .padding(14)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .fixedSize()
            }
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { rowHovered = $0 }
        #endif
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: rowHovered)
    }

    private func setReminder(at date: Date) {
        item.reminderDate = date
        stampAndSave()

        guard notificationCenter != nil else {
            print("⚠️ Cannot schedule notification: Not in an app bundle.")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = item.content
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func removeReminder() {
        item.reminderDate = nil
        stampAndSave()
        notificationCenter?.removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }
}

// MARK: - Preset Pill

struct PresetPill: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                        .overlay(Capsule().stroke(Color.blue.opacity(0.2), lineWidth: 0.5))
                )
                .foregroundColor(.blue)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - iOS Task Row

#if os(iOS)
struct IOSTaskRow: View {
    @Binding var item: TaskItem
    var listColor: Color
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    var onDelete: () -> Void
    var onChange: () -> Void

    /// Stamps item.lastModified so the last-writer-wins merge keeps this change.
    private func stampAndSave() {
        item.lastModified = Date()
        onChange()
    }

    @State private var showReminderSheet = false
    @State private var tempReminderDate = Date()
    @State private var showEstimateSheet = false
    @State private var customEstimateText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Checkbox
            ModernCheckbox(isChecked: $item.isCompleted, color: listColor)
                .onChange(of: item.isCompleted) { newValue in
                    if newValue { removeReminder() }
                    stampAndSave()
                }

            VStack(alignment: .leading, spacing: 3) {
                // Editable text field
                ZStack(alignment: .leading) {
                    if item.isCompleted || item.isStrikethrough {
                        Text(item.content.isEmpty ? "Task..." : item.content)
                            .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .medium, design: item.isItalic ? .default : .rounded))
                            .italic(item.isItalic)
                            .foregroundColor(.clear)
                            .overlay(
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.7))
                                    .frame(height: 1)
                                    .offset(y: 1),
                                alignment: .center
                            )
                    }
                    TextField("Task...", text: $item.content)
                        .font(.system(size: baseFontSize, weight: item.isBold ? .bold : .medium, design: item.isItalic ? .default : .rounded))
                        .italic(item.isItalic)
                        .foregroundColor(item.isCompleted ? .secondary.opacity(0.6) : .primary)
                        .onChange(of: item.content) { _ in stampAndSave() }
                }
                .id("\(item.id)-\(item.isBold)-\(item.isItalic)-\(item.isStrikethrough)-\(item.isCompleted)")
                .lineLimit(2)

                HStack(spacing: 6) {
                    Text(item.status.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(item.status.color.opacity(0.12))
                                .overlay(Capsule().stroke(item.status.color.opacity(0.22), lineWidth: 0.5))
                        )
                        .foregroundColor(item.status.color)
                        .fixedSize()

                    if item.priority != .none {
                        Text(item.priority.title.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(item.priority.color.opacity(0.12))
                                    .overlay(Capsule().stroke(item.priority.color.opacity(0.2), lineWidth: 0.5))
                            )
                            .foregroundColor(item.priority.color)
                            .fixedSize()
                    }

                    if let duration = durationBadgeText(minutes: item.estimatedMinutes) {
                        Text(duration)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.10))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
                            )
                            .foregroundColor(.blue)
                            .fixedSize()
                    }

                    if let reminder = item.reminderDate, !item.isCompleted {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(reminder < Date() ? .red : .blue)
                            .onTapGesture {
                                tempReminderDate = reminder
                                showReminderSheet = true
                            }
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showReminderSheet) {
            ReminderPickerSheet(
                reminderDate: item.reminderDate,
                initialDate: tempReminderDate,
                onSet: { date in
                    setReminder(at: date)
                    showReminderSheet = false
                },
                onClear: {
                    removeReminder()
                    showReminderSheet = false
                },
                onCancel: { showReminderSheet = false }
            )
        }
        .sheet(isPresented: $showEstimateSheet) {
            NavigationStack {
                Form {
                    Section("Estimate") {
                        TextField("Minutes", text: $customEstimateText)
                            .keyboardType(.numberPad)
                    }
                }
                .navigationTitle("Task Estimate")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showEstimateSheet = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let value = Int(customEstimateText.trimmingCharacters(in: .whitespacesAndNewlines))
                            item.estimatedMinutes = (value ?? 0) > 0 ? value : nil
                            stampAndSave()
                            showEstimateSheet = false
                        }
                    }
                }
            }
        }
        .contextMenu {
            // Reminder
            Button {
                tempReminderDate = item.reminderDate ?? Date().addingTimeInterval(3600)
                showReminderSheet = true
            } label: {
                Label(item.reminderDate == nil ? "Set Reminder" : "Edit Reminder", systemImage: "bell")
            }
            if item.reminderDate != nil {
                Button {
                    removeReminder()
                } label: {
                    Label("Clear Reminder", systemImage: "bell.slash")
                }
            }

            Divider()

            // Format options
            Button {
                item.isBold.toggle(); stampAndSave()
            } label: {
                Label(item.isBold ? "Remove Bold" : "Bold", systemImage: "bold")
            }
            Button {
                item.isItalic.toggle(); stampAndSave()
            } label: {
                Label(item.isItalic ? "Remove Italic" : "Italic", systemImage: "italic")
            }
            Button {
                item.isStrikethrough.toggle(); stampAndSave()
            } label: {
                Label(item.isStrikethrough ? "Remove Strikethrough" : "Strikethrough", systemImage: "strikethrough")
            }

            Divider()

            // Priority submenu
            Menu {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        item.priority = p; stampAndSave()
                    } label: {
                        HStack {
                            Text(p.title)
                            if item.priority == p {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag.fill")
            }

            Menu {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Button {
                        item.status = status
                        stampAndSave()
                    } label: {
                        HStack {
                            Label(status.title, systemImage: status.icon)
                            if item.status == status { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label("Status", systemImage: "circle.lefthalf.filled")
            }

            Menu {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { mins in
                    Button(durationBadgeText(minutes: mins) ?? "\(mins)m") {
                        item.estimatedMinutes = mins
                        stampAndSave()
                    }
                }
                Divider()
                Button("Custom…") {
                    customEstimateText = item.estimatedMinutes.map(String.init) ?? ""
                    showEstimateSheet = true
                }
                if item.estimatedMinutes != nil {
                    Button("Clear", role: .destructive) {
                        item.estimatedMinutes = nil
                        stampAndSave()
                    }
                }
            } label: {
                Label("Estimate", systemImage: "timer")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func setReminder(at date: Date) {
        item.reminderDate = date
        stampAndSave()
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = item.content
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func removeReminder() {
        item.reminderDate = nil
        stampAndSave()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }
}

// MARK: - Reminder Picker Sheet (iOS)

struct ReminderPickerSheet: View {
    let reminderDate: Date?
    @State private var tempDate: Date
    let onSet: (Date) -> Void
    let onClear: () -> Void
    let onCancel: () -> Void

    init(reminderDate: Date?, initialDate: Date, onSet: @escaping (Date) -> Void, onClear: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.reminderDate = reminderDate
        self._tempDate = State(initialValue: initialDate)
        self.onSet = onSet
        self.onClear = onClear
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker("", selection: $tempDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal)

                // Preset pills
                HStack(spacing: 10) {
                    reminderPresetPill(title: "+1h")  { tempDate = Date().addingTimeInterval(3600) }
                    reminderPresetPill(title: "+6h")  { tempDate = Date().addingTimeInterval(6 * 3600) }
                    reminderPresetPill(title: "+1d")  { tempDate = Date().addingTimeInterval(24 * 3600) }
                    reminderPresetPill(title: "9AM Tomorrow") {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        tempDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if reminderDate != nil {
                        Button("Clear", role: .destructive) { onClear() }
                            .foregroundColor(.red)
                    } else {
                        Button("Cancel") { onCancel() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") { onSet(tempDate) }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reminderPresetPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.blue.opacity(0.1))
                        .overlay(Capsule().stroke(Color.blue.opacity(0.25), lineWidth: 0.5))
                )
                .foregroundColor(.blue)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
#endif
