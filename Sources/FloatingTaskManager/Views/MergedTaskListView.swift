import SwiftUI
import UserNotifications

private func mergedDurationText(minutes: Int?) -> String? {
    guard let minutes, minutes > 0 else { return nil }
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 && mins > 0 { return "\(hours)h \(mins)m" }
    if hours > 0 { return "\(hours)h" }
    return "\(mins)m"
}

struct MergedTaskListView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95

    var body: some View {
        #if os(iOS)
        iosBody
        #else
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Merged Tasks")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                #if os(macOS)
                Button(action: { windowManager.closeListWindow(for: windowManager.MERGED_LIST_ID) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PremiumButtonStyle())
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                headerBackground
            )

            Divider().opacity(0.1)

            // Items
            List {
                ForEach(orderedTasks) { task in
                    MergedTaskRow(task: task)
                }
                .onMove(perform: moveTasks)
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)

            Divider().opacity(0.1)

            // Footer
            HStack {
                let allTasks = store.getAllTasks()
                let done = allTasks.filter(\.isCompleted).count
                let total = allTasks.count
                Text("\(done) of \(total) completed across all lists")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 400)
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
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        VStack(spacing: 0) {
            // ── Header ──
            HStack {
                Text("Merged Tasks")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                EditButton()
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(headerBackground)

            Divider().opacity(0.3)

            // ── Task Rows ──
            List {
                ForEach(orderedTasks) { task in
                    IOSMergedTaskRow(task: task)
                        .environmentObject(store)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.visible)
                        .listRowBackground(Color(uiColor: .systemBackground))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.toggleTaskCompletion(taskID: task.id)
                            } label: {
                                Label(task.isCompleted ? "Undo" : "Done", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
                            }
                            .tint(task.isCompleted ? .orange : .green)
                        }
                }
                .onMove(perform: moveTasks)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.3)

            // ── Footer ──
            HStack {
                let allTasks = store.getAllTasks()
                let done = allTasks.filter(\.isCompleted).count
                let total = allTasks.count
                Text("\(done) of \(total) completed across all lists")
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

    #endif

    @ViewBuilder
    private var headerBackground: some View {
        #if os(macOS)
        VisualEffectView(material: .headerView, blendingMode: .withinWindow).opacity(0.5)
        #else
        VisualEffectView(material: .systemThinMaterial).opacity(0.5)
        #endif
    }

    private var orderedTasks: [TaskItem] {
        let allTasks = store.getAllTasks().filter { !$0.isCompleted }
        let taskMap = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        
        var sortedTasks: [TaskItem] = []
        
        // Add tasks that are in the order list
        for id in store.mergedTaskOrder {
            if let task = taskMap[id] {
                sortedTasks.append(task)
            }
        }
        
        // Add any remaining tasks that weren't in the order list
        let orderedIDs = Set(store.mergedTaskOrder)
        for task in allTasks {
            if !orderedIDs.contains(task.id) {
                sortedTasks.append(task)
            }
        }
        
        return sortedTasks
    }

    private func moveTasks(from source: IndexSet, to destination: Int) {
        var newOrder = orderedTasks.map { $0.id }
        newOrder.move(fromOffsets: source, toOffset: destination)
        store.mergedTaskOrder = newOrder
        store.save()
    }
}

struct MergedTaskRow: View {
    let task: TaskItem
    @EnvironmentObject var store: TaskStore
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0

    var body: some View {
        HStack(spacing: 10) {
            // Read-only checkbox (since it's a merged view, we could make it editable but let's keep it simple first)
            // Actually, user might want to toggle here too.
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? .blue : .secondary)
                .onTapGesture {
                    toggleTaskCompletion()
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.content)
                    .font(.system(size: baseFontSize, weight: task.isBold ? .bold : .medium, design: .rounded))
                    .strikethrough(task.isCompleted || task.isStrikethrough)
                    .italic(task.isItalic)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                HStack(spacing: 6) {
                    // List Tag
                    if let list = store.lists.first(where: { $0.items.contains(where: { $0.id == task.id }) }) {
                        Text(list.title)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(list.color.swiftUIColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(list.color.swiftUIColor.opacity(0.1))
                            .cornerRadius(4)
                    }

                    // Priority Tag
                    if task.priority != .none {
                        Text(task.priority.title.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(task.priority.color.opacity(0.12))
                                    .overlay(Capsule().stroke(task.priority.color.opacity(0.2), lineWidth: 0.5))
                            )
                            .foregroundColor(task.priority.color)
                    }

                    Text(task.status.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(task.status.color.opacity(0.12))
                                .overlay(Capsule().stroke(task.status.color.opacity(0.22), lineWidth: 0.5))
                        )
                        .foregroundColor(task.status.color)

                    if let duration = mergedDurationText(minutes: task.estimatedMinutes) {
                        Text(duration)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
                            )
                            .foregroundColor(.blue)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 6, x: 0, y: 2)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
    }

    private func toggleTaskCompletion() {
        store.toggleTaskCompletion(taskID: task.id)
    }
}

// MARK: - iOS Merged Task Row

#if os(iOS)
struct IOSMergedTaskRow: View {
    let task: TaskItem
    @EnvironmentObject var store: TaskStore
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0

    @State private var showReminderSheet = false
    @State private var tempReminderDate = Date()
    @State private var showEstimateSheet = false
    @State private var customEstimateText = ""

    var body: some View {
        HStack(spacing: 10) {
            // Modern checkbox
            ModernCheckbox(isChecked: Binding(
                get: { task.isCompleted },
                set: { _ in toggleTaskCompletion() }
            ), color: listColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.content)
                    .font(.system(size: baseFontSize, weight: task.isBold ? .bold : .medium, design: .rounded))
                    .strikethrough(task.isCompleted || task.isStrikethrough)
                    .italic(task.isItalic)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // List Tag
                    if let list = store.lists.first(where: { $0.items.contains(where: { $0.id == task.id }) }) {
                        Text(list.title)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(list.color.swiftUIColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(list.color.swiftUIColor.opacity(0.1))
                            )
                    }

                    // Priority Tag
                    if task.priority != .none {
                        Text(task.priority.title.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(task.priority.color.opacity(0.12))
                                    .overlay(Capsule().stroke(task.priority.color.opacity(0.2), lineWidth: 0.5))
                            )
                            .foregroundColor(task.priority.color)
                    }

                    Text(task.status.title.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(task.status.color.opacity(0.12))
                                .overlay(Capsule().stroke(task.status.color.opacity(0.22), lineWidth: 0.5))
                        )
                        .foregroundColor(task.status.color)

                    if let duration = mergedDurationText(minutes: task.estimatedMinutes) {
                        Text(duration)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.blue.opacity(0.22), lineWidth: 0.5))
                            )
                            .foregroundColor(.blue)
                    }

                    // Reminder indicator
                    if let reminder = task.reminderDate, !task.isCompleted {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(reminder < Date() ? .red : .blue)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showReminderSheet) {
            ReminderPickerSheet(
                reminderDate: task.reminderDate,
                initialDate: tempReminderDate,
                onSet: { date in
                    updateTask { item in
                        item.reminderDate = date
                        scheduleReminder(for: item, at: date)
                    }
                    showReminderSheet = false
                },
                onClear: {
                    updateTask { item in
                        item.reminderDate = nil
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
                    }
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
                            updateTask { $0.estimatedMinutes = (value ?? 0) > 0 ? value : nil }
                            showEstimateSheet = false
                        }
                    }
                }
            }
        }
        .contextMenu {
            // Reminder
            Button {
                tempReminderDate = task.reminderDate ?? Date().addingTimeInterval(3600)
                showReminderSheet = true
            } label: {
                Label(task.reminderDate == nil ? "Set Reminder" : "Edit Reminder", systemImage: "bell")
            }
            if task.reminderDate != nil {
                Button {
                    updateTask { item in
                        item.reminderDate = nil
                        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
                    }
                } label: {
                    Label("Clear Reminder", systemImage: "bell.slash")
                }
            }

            Divider()

            // Format toggles
            Button {
                updateTask { $0.isBold.toggle() }
            } label: {
                Label(task.isBold ? "Remove Bold" : "Bold", systemImage: "bold")
            }
            Button {
                updateTask { $0.isItalic.toggle() }
            } label: {
                Label(task.isItalic ? "Remove Italic" : "Italic", systemImage: "italic")
            }
            Button {
                updateTask { $0.isStrikethrough.toggle() }
            } label: {
                Label(task.isStrikethrough ? "Remove Strikethrough" : "Strikethrough", systemImage: "strikethrough")
            }

            Divider()

            // Priority submenu
            Menu {
                ForEach(Priority.allCases, id: \.self) { p in
                    Button {
                        updateTask { $0.priority = p }
                    } label: {
                        HStack {
                            Text(p.title)
                            if task.priority == p { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label("Priority", systemImage: "flag.fill")
            }

            Menu {
                ForEach(TaskStatus.allCases, id: \.self) { status in
                    Button {
                        updateTask { $0.status = status }
                    } label: {
                        HStack {
                            Label(status.title, systemImage: status.icon)
                            if task.status == status { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label("Status", systemImage: "circle.lefthalf.filled")
            }

            Menu {
                ForEach([15, 30, 45, 60, 90, 120], id: \.self) { mins in
                    Button(mergedDurationText(minutes: mins) ?? "\(mins)m") {
                        updateTask { $0.estimatedMinutes = mins }
                    }
                }
                Divider()
                Button("Custom…") {
                    customEstimateText = task.estimatedMinutes.map(String.init) ?? ""
                    showEstimateSheet = true
                }
                if task.estimatedMinutes != nil {
                    Button("Clear", role: .destructive) {
                        updateTask { $0.estimatedMinutes = nil }
                    }
                }
            } label: {
                Label("Estimate", systemImage: "timer")
            }

            Divider()

            Button(role: .destructive) {
                deleteTask()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var listColor: Color {
        store.lists.first(where: { $0.items.contains(where: { $0.id == task.id }) })?.color.swiftUIColor ?? .blue
    }

    private func toggleTaskCompletion() {
        store.toggleTaskCompletion(taskID: task.id)
    }

    /// Mutate the task item in-place across all lists and save.
    private func updateTask(_ mutation: (inout TaskItem) -> Void) {
        store.updateTask(taskID: task.id, mutation: mutation)
    }

    /// Delete a task from whichever list owns it.
    private func deleteTask() {
        for i in 0..<store.lists.count {
            if let _ = store.lists[i].items.firstIndex(where: { $0.id == task.id }) {
                store.lists[i].deletedItemIDs[task.id] = Date()
                store.lists[i].items.removeAll { $0.id == task.id }
                store.lists[i].lastModified = Date()
                store.save()
                return
            }
        }
    }

    private func scheduleReminder(for item: TaskItem, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Task Reminder"
        content.body = item.content
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: item.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }
}
#endif
