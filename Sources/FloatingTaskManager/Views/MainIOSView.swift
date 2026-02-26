import SwiftUI
import UserNotifications

#if os(iOS)

// MARK: - Platform Color Helpers (iOS-only)
private extension Color {
    static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var secondaryGroupedBackground: Color { Color(uiColor: .secondarySystemGroupedBackground) }
}

private var iOSGroupedBackground: Color { .groupedBackground }

struct MainIOSView: View {
    @EnvironmentObject var store: TaskStore
    @EnvironmentObject var windowManager: WindowManager
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("hasPromptedPhoneAuth") var hasPromptedPhoneAuth: Bool = false
    @State private var showSettings = false
    @State private var showPhoneAuth = false
    @State private var isEditingLists = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    mergedTasksCard
                    myListsSection
                    quickActionsSection
                    fontSizeSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color.groupedBackground.ignoresSafeArea())
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusView(status: store.syncStatus)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if case .signedOut = store.firebaseSync.authState {
                            Button {
                                showPhoneAuth = true
                            } label: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundColor(.orange)
                            }
                        }
                        Button(action: { store.manualRefresh() }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        Button(action: { withAnimation(.spring()) { store.createNewList() } }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    IOSSettingsView()
                        .environmentObject(store)
                        .navigationTitle("Settings")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSettings = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showPhoneAuth) {
                PhoneAuthView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $isEditingLists) {
                ListReorderSheet()
                    .environmentObject(store)
            }
            .onAppear {
                print("🔵 [MainIOSView] onAppear — authState=\(store.firebaseSync.authState) syncStatus=\(store.syncStatus) hasPromptedPhoneAuth=\(hasPromptedPhoneAuth)")
                if !hasPromptedPhoneAuth, case .signedOut = store.firebaseSync.authState {
                    hasPromptedPhoneAuth = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showPhoneAuth = true
                    }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var mergedTasksCard: some View {
        NavigationLink(destination: MergedTaskListView()
            .environmentObject(store)
            .environmentObject(windowManager)
        ) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merged Tasks")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    let allTasks = store.getAllTasks()
                    let done = allTasks.filter(\.isCompleted).count
                    let total = allTasks.count
                    Text("\(done) of \(total) completed across all lists")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondaryGroupedBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var myListsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("My Lists")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if !store.lists.isEmpty {
                    Button {
                        isEditingLists = true
                    } label: {
                        Text("Reorder")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 4)

            if store.lists.isEmpty {
                emptyListsPlaceholder
            } else {
                listRows
            }
        }
    }

    private var emptyListsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Active Lists")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
            Button("Create First List") {
                withAnimation(.spring()) { store.createNewList() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondaryGroupedBackground)
        )
    }

    private var listRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.lists.enumerated()), id: \.element.id) { index, list in
                VStack(spacing: 0) {
                    NavigationLink(destination: TaskListView(list: list)
                        .environmentObject(store)
                        .environmentObject(windowManager)
                    ) {
                        IOSListRow(list: list)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.spring()) { store.deleteList(list) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if index < store.lists.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondaryGroupedBackground)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                IOSQuickActionCard(title: "New List", icon: "plus.circle.fill", color: .blue) {
                    withAnimation(.spring()) { store.createNewList() }
                }
                Button(action: { showSettings = true }) {
                    IOSQuickActionCardContent(title: "Settings", icon: "gearshape.fill", color: .gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "textformat.size")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
                Text("Text Size")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(baseFontSize))pt")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            Slider(value: $baseFontSize, in: 10...24, step: 1)
                .tint(.blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondaryGroupedBackground)
        )
    }
}

// MARK: - Sync Status View

struct SyncStatusView: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(status.color)
            Text(status.label.components(separatedBy: ":").first ?? status.label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(status.color)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(status.color.opacity(0.1))
        )
        .fixedSize()
    }
}

// MARK: - List Reorder Sheet

struct ListReorderSheet: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.lists) { list in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(list.color.swiftUIColor)
                            .frame(width: 10, height: 10)
                        Text(list.title.isEmpty ? "Untitled List" : list.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(list.items.count) items")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    store.lists.move(fromOffsets: source, toOffset: destination)
                    store.save()
                }
                .onDelete { offsets in
                    offsets.map { store.lists[$0] }.forEach { store.deleteList($0) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - iOS List Row

struct IOSListRow: View {
    @ObservedObject var list: TaskList

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(list.color.swiftUIColor)
                .frame(width: 10, height: 10)
                .shadow(color: list.color.swiftUIColor.opacity(0.4), radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.title.isEmpty ? "Untitled List" : list.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(list.items.count) items")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Priority indicators
            let highCount = list.items.filter { $0.priority == .high && !$0.isCompleted }.count
            if highCount > 0 {
                Text("\(highCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red.opacity(0.1)))
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - iOS Quick Action Card

struct IOSQuickActionCardContent: View {
    let title: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(0.08))
        )
    }
}

struct IOSQuickActionCard: View {
    let title: String
    let icon: String
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IOSQuickActionCardContent(title: title, icon: icon, color: color)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - iOS Settings View

struct IOSSettingsView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @EnvironmentObject var store: TaskStore
    @State private var showPhoneAuth = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            // Text Size
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "textformat.size")
                            .foregroundColor(.blue)
                            .font(.system(size: 14, weight: .bold))
                        Text("Text Size")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Spacer()
                        Text("\(Int(baseFontSize))pt")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    Slider(value: $baseFontSize, in: 10...24, step: 1)
                        .tint(.blue)
                }
            }

            // Notifications
            Section(header: Text("Reminders & Notifications")) {
                notificationsRow
            }

            // Sync / Account
            Section(header: Text("Sync Account")) {
                syncAccountRow
            }

            // About
            Section {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Version")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Spacer()
                    Text("v1.1.0 Premium")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showPhoneAuth) {
            PhoneAuthView()
                .environmentObject(store)
        }
        .onAppear { checkNotificationStatus() }
    }

    @ViewBuilder
    private var notificationsRow: some View {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Enabled")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                    Text("Reminders will appear as notifications")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
            }
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications Disabled")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Tap to open Settings and enable notifications")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        default:
            Button {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                    DispatchQueue.main.async { checkNotificationStatus() }
                }
            } label: {
                HStack {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Notifications")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Allow reminders for your tasks")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    @ViewBuilder
    private var syncAccountRow: some View {
        switch store.firebaseSync.authState {
        case .signedOut:
            Button {
                showPhoneAuth = true
            } label: {
                HStack {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign In to Sync")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Text("Sync tasks across all your devices")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }

        case .signedIn(let email):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed In")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                        Text(email)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    // Live sync status badge
                    Label(store.syncStatus.label, systemImage: store.syncStatus.icon)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(store.syncStatus.color)
                        .lineLimit(1)
                }

                // Link Mac button — copies refresh token to clipboard
                LinkMacButton()

                Button(role: .destructive) {
                    store.firebaseSync.signOut()
                } label: {
                    Text("Sign Out")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
            }
        }
    }
}

// MARK: - LinkMacButton (iOS only)
#if os(iOS)
import FirebaseAuth

private struct LinkMacButton: View {
    @State private var state: CopyState = .idle

    enum CopyState {
        case idle, copying, copied, failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                copyToken()
            } label: {
                HStack(spacing: 6) {
                    if case .copying = state {
                        ProgressView().scaleEffect(0.7).tint(.blue)
                    } else {
                        Image(systemName: iconName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(iconColor)
                    }
                    Text(labelText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(iconColor)
                }
            }
            .disabled({ if case .copying = state { return true }; return false }())

            if case .failed(let msg) = state {
                Text(msg)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.red)
            }
        }
    }

    private var iconName: String {
        switch state {
        case .copied:  return "checkmark.circle.fill"
        case .failed:  return "exclamationmark.triangle.fill"
        default:       return "desktopcomputer.and.arrow.down"
        }
    }

    private var iconColor: Color {
        switch state {
        case .copied:  return .green
        case .failed:  return .red
        default:       return .blue
        }
    }

    private var labelText: String {
        switch state {
        case .idle:    return "Copy Link-Mac Token"
        case .copying: return "Getting token…"
        case .copied:  return "Copied! Paste in Mac app Settings"
        case .failed:  return "Failed — see error below"
        }
    }

    private func copyToken() {
        print("🔵 [LinkMacButton] copyToken() tapped")
        guard let user = Auth.auth().currentUser else {
            print("🔴 [LinkMacButton] Auth.auth().currentUser is nil — not signed in?")
            withAnimation { state = .failed("Not signed in. Please sign in first.") }
            return
        }
        print("🔵 [LinkMacButton] currentUser uid=\(user.uid) email=\(user.email ?? "nil")")

        // Try refreshToken directly first (fastest path)
        if let token = user.refreshToken, !token.isEmpty {
            print("🟢 [LinkMacButton] refreshToken available, copying to clipboard (len=\(token.count))")
            UIPasteboard.general.string = token
            withAnimation { state = .copied }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation { state = .idle }
            }
            return
        }

        // refreshToken was nil — force a token refresh to populate it
        print("🟡 [LinkMacButton] refreshToken is nil, forcing ID token refresh …")
        withAnimation { state = .copying }
        user.getIDTokenForcingRefresh(true) { _, error in
            if let error {
                print("🔴 [LinkMacButton] getIDTokenForcingRefresh error: \(error.localizedDescription)")
                withAnimation { state = .failed(error.localizedDescription) }
                return
            }
            // Re-check after refresh
            if let token = Auth.auth().currentUser?.refreshToken, !token.isEmpty {
                print("🟢 [LinkMacButton] refreshToken available after force-refresh, copying (len=\(token.count))")
                UIPasteboard.general.string = token
                withAnimation { state = .copied }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { state = .idle }
                }
            } else {
                print("🔴 [LinkMacButton] refreshToken still nil after force-refresh")
                withAnimation { state = .failed("Could not retrieve token. Try signing out and back in.") }
            }
        }
    }
}
#endif

#endif // os(iOS)

