import SwiftUI
import Combine
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
import FirebaseCore
#if canImport(WidgetKit)
import WidgetKit
#endif
#endif

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case disconnected       // not signed in / offline
    case connected          // signed in, listener active
    case error(String)

    var icon: String {
        switch self {
        case .disconnected:   return "icloud.slash"
        case .connected:      return "checkmark.icloud"
        case .error:          return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .disconnected:   return .secondary
        case .connected:      return .green
        case .error:          return .red
        }
    }

    var label: String {
        switch self {
        case .disconnected:       return "Not signed in"
        case .connected:          return "Synced"
        case .error(let msg):     return "Error: \(msg)"
        }
    }
}

// MARK: - TaskStore

class TaskStore: ObservableObject {
    @Published var lists: [TaskList] = []
    @Published var mergedTaskOrder: [UUID] = []
    @Published var mergedListPosition: CGPoint = .zero
    @Published var mergedListSize: CGSize = CGSize(width: 350, height: 500)
    @Published var syncStatus: SyncStatus = .disconnected

    private var listCancellables = Set<AnyCancellable>()
    private var syncCancellables = Set<AnyCancellable>()
    private var didSetupFirebaseSync = false
    private let savePath: URL

    // Firebase cloud sync manager (iOS only; macOS uses a no-op stub)
    // Lazy so it is created only after FirebaseApp.configure() has run.
    lazy var firebaseSync: FirebaseSyncManager = FirebaseSyncManager()

    // Debounce save + broadcast
    private var saveWorkItem: DispatchWorkItem?
    private var isApplyingRemoteData = false
    private var wasPreviouslySignedIn = false
    private var awaitingInitialRemoteAfterSignIn = false
    private var bootstrapUploadWorkItem: DispatchWorkItem?

    /// Tombstone set for deleted lists — persisted so deletions survive app restarts.
    private var deletedListIDs: [UUID: Date] = [:]
    #if os(iOS)
    private let widgetSnapshotFilename = "merged-widget-snapshot.json"
    private let widgetSnapshotDefaultsKey = "merged-widget-snapshot-json"
    private let widgetKind = "MergedTasksWidget"
    private let appGroupID = "group.com.hardikbansal.floatingtaskmanager"
    #endif

    init() {
        #if os(iOS)
        // Configure Firebase before anything accesses FirebaseSyncManager.
        // This is the earliest safe point — before the lazy firebaseSync property is touched.
        if FirebaseApp.app() == nil {
            print("🔵 [TaskStore] FirebaseApp.configure() — not yet configured, configuring now")
            FirebaseApp.configure()
        } else {
            print("🔵 [TaskStore] FirebaseApp already configured — skipping")
        }
        #endif

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FloatingTaskManager")
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        savePath = appSupport.appendingPathComponent("tasks.json")
        print("🔵 [TaskStore] init — savePath=\(savePath.path)")

        load()
        setupObservers()
        setupFirebaseSync()
        setupAppLifecycleObservers()
    }

    // MARK: - Setup

    private func setupFirebaseSync() {
        if didSetupFirebaseSync { return }
        didSetupFirebaseSync = true

        print("🔵 [TaskStore] setupFirebaseSync() attaching observers")
        // Forward Firebase sync status to our published syncStatus
        firebaseSync.$syncStatus
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] peerStatus in
                guard let self else { return }
                switch peerStatus {
                case .disconnected:       self.syncStatus = .disconnected
                case .connected:          self.syncStatus = .connected
                case .error(let msg):     self.syncStatus = .error(msg)
                }
                print("🔵 [TaskStore] syncStatus -> \(self.syncStatus.label)")
            }
            .store(in: &syncCancellables)

        // Clear all local data when the user signs out.
        firebaseSync.$authState
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] authState in
                guard let self else { return }
                switch authState {
                case .signedIn:
                    print("🔵 [TaskStore] authState -> signedIn")
                    self.wasPreviouslySignedIn = true
                    self.firebaseSync.start()
                    self.firebaseSync.forcePoll()
                    self.awaitingInitialRemoteAfterSignIn = true
                    self.bootstrapUploadWorkItem?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        guard self.awaitingInitialRemoteAfterSignIn else { return }
                        self.awaitingInitialRemoteAfterSignIn = false

                        // If no remote payload arrived shortly after sign-in, push local state once.
                        let hasLocalData = !self.lists.isEmpty || !self.deletedListIDs.isEmpty
                        guard hasLocalData else {
                            print("🔵 [TaskStore] bootstrap upload skipped (no local data)")
                            return
                        }
                        print("🔵 [TaskStore] bootstrap upload: no remote payload detected, uploading local snapshot")
                        self.save()
                    }
                    self.bootstrapUploadWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
                case .signedOut:
                    print("🟡 [TaskStore] authState -> signedOut")
                    self.awaitingInitialRemoteAfterSignIn = false
                    self.bootstrapUploadWorkItem?.cancel()
                    if self.wasPreviouslySignedIn {
                        self.clearAllLocalDataAfterSignOut()
                    }
                    self.wasPreviouslySignedIn = false
                }
            }
            .store(in: &syncCancellables)

        // When Firestore delivers data from another device, apply it
        firebaseSync.onReceivedData = { [weak self] data in
            guard let self else { return }
            print("🔵 [TaskStore] onReceivedData \(data.count) bytes")
            self.awaitingInitialRemoteAfterSignIn = false
            self.bootstrapUploadWorkItem?.cancel()
            self.isApplyingRemoteData = true
            self.applyData(data, save: true)
            // Note: isApplyingRemoteData is reset inside applyData's async block
        }

        firebaseSync.start()
    }

    private func setupAppLifecycleObservers() {
#if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Only reload from disk — do NOT save/broadcast, which would overwrite
            // remote deletions with stale local data.
            self?.loadFromDiskOnly()
        }
#else
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.loadFromDiskOnly()
        }
#endif
    }

    /// Reload from disk without triggering a save or broadcast.
    private func loadFromDiskOnly() {
        guard FileManager.default.fileExists(atPath: savePath.path),
              let data = try? Data(contentsOf: savePath) else { return }
        print("🔵 [TaskStore] loadFromDiskOnly() — \(data.count) bytes")
        applyData(data, save: false)
    }

    private func setupObservers() {
        listCancellables.removeAll()

        resubscribeListObservers()
    }

    /// Subscribe to objectWillChange on every list so TaskStore forwards changes to SwiftUI.
    /// Call this whenever self.lists is replaced without tearing down Firebase subscriptions.
    private func resubscribeListObservers() {
        for list in lists {
            list.objectWillChange
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &listCancellables)
        }
    }

    // MARK: - Save

    func save() {
        // Debounce: coalesce rapid saves into one write
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performSave()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func performSave() {
        do {
            let data = try encodeStore()
            try data.write(to: savePath, options: .atomic)
            print("🔵 [TaskStore] performSave() — wrote \(data.count) bytes to disk")
            #if os(iOS)
            writeWidgetSnapshot()
            #endif

            // Broadcast to Firebase so other devices pick it up.
            // syncStatus is driven entirely by firebaseSync.$syncStatus — don't touch it here.
            if !isApplyingRemoteData {
                print("🔵 [TaskStore] broadcasting \(data.count) bytes to Firebase …")
                firebaseSync.broadcast(data: data)
            }
        } catch {
            print("🔴 [TaskStore] Save error: \(error)")
            syncStatus = .error(error.localizedDescription)
        }
    }

    private func encodeStore() throws -> Data {
        let wrapper = StoreWrapper(
            lists: lists,
            mergedTaskOrder: mergedTaskOrder,
            mergedListPosition: mergedListPosition,
            mergedListSize: mergedListSize,
            deletedListIDs: deletedListIDs
        )
        return try JSONEncoder().encode(wrapper)
    }

    // MARK: - Load

    func load() {
        guard FileManager.default.fileExists(atPath: savePath.path) else {
            print("🔵 [TaskStore] load() — no saved file at \(savePath.path), starting fresh")
            return
        }
        guard let data = try? Data(contentsOf: savePath) else {
            print("🔴 [TaskStore] load() — file exists but could not read data")
            return
        }
        print("🔵 [TaskStore] load() — read \(data.count) bytes from disk")
        applyData(data, save: false)
    }

    private func applyData(_ data: Data, save: Bool) {
        print("🔵 [TaskStore] applyData() — \(data.count) bytes, save=\(save)")
        guard let wrapper = try? JSONDecoder().decode(StoreWrapper.self, from: data) else {
            print("🟡 [TaskStore] applyData() — failed to decode as StoreWrapper, trying legacy [TaskList] format")
            // Legacy [TaskList] format fallback
            if let legacyLists = try? JSONDecoder().decode([TaskList].self, from: data) {
                print("🔵 [TaskStore] applyData() — legacy decode succeeded, \(legacyLists.count) lists")
                DispatchQueue.main.async {
                    self.lists.forEach { $0.objectWillChange.send() }
                    self.lists = legacyLists
                    self.resubscribeListObservers()
                    #if os(iOS)
                    self.writeWidgetSnapshot()
                    #endif
                    if save { self.performSave() }
                    self.isApplyingRemoteData = false
                }
            } else {
                print("🔴 [TaskStore] applyData() — could not decode data in any known format")
                self.isApplyingRemoteData = false
            }
            return
        }
        print("🔵 [TaskStore] applyData() — decoded StoreWrapper with \(wrapper.lists.count) lists")
        DispatchQueue.main.async {
            self.mergeRemoteWrapper(wrapper, save: save)
            self.isApplyingRemoteData = false
        }
    }

    /// Merge incoming remote wrapper using lastModified timestamps + tombstones.
    /// Rules:
    ///  - Tombstones are unioned: once deleted on any device, never resurrected
    ///  - Lists that only exist remotely AND are not tombstoned locally → add locally
    ///  - Lists that only exist locally AND are not tombstoned remotely → keep locally
    ///  - Lists that exist on both sides → merge field-by-field: newer lastModified wins
    ///  - Items inside a list: same tombstone + lastModified rules per item
    private func mergeRemoteWrapper(_ remote: StoreWrapper, save: Bool) {
        // 1. Union tombstones — a deletion on any device wins permanently
        let mergedDeletedLists = deletedListIDs.merging(remote.deletedListIDs) { local, remote in
            max(local, remote)  // keep the earlier deletion time (first delete wins)
        }
        deletedListIDs = mergedDeletedLists

        var localById: [UUID: TaskList] = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        var merged: [TaskList] = []

        for remoteList in remote.lists {
            // Skip if this list is tombstoned on either side
            if deletedListIDs[remoteList.id] != nil { continue }

            if let localList = localById[remoteList.id] {
                // Both sides have this list — pick winner per field
                if remoteList.lastModified > localList.lastModified {
                    localList.title          = remoteList.title
                    localList.color          = remoteList.color
                    localList.sortDescending = remoteList.sortDescending
                    localList.isVisible      = remoteList.isVisible
                    localList.lastModified   = remoteList.lastModified
                }
                // Merge item tombstones then items
                let mergedItemTombstones = localList.deletedItemIDs.merging(remoteList.deletedItemIDs) { max($0, $1) }
                localList.deletedItemIDs = mergedItemTombstones
                localList.items = mergeItems(local: localList.items,
                                             remote: remoteList.items,
                                             deletedIDs: mergedItemTombstones)
                merged.append(localList)
                localById.removeValue(forKey: remoteList.id)
            } else {
                // New list from remote — add it (with its item tombstones)
                merged.append(remoteList)
            }
        }

        // Lists that remain in localById only exist locally
        for (id, localList) in localById {
            // Skip if tombstoned remotely
            if deletedListIDs[id] != nil { continue }
            merged.append(localList)
        }

        // Sort to keep stable order
        let remoteOrder = remote.lists.map { $0.id }
        merged.sort { a, b in
            let ai = remoteOrder.firstIndex(of: a.id) ?? Int.max
            let bi = remoteOrder.firstIndex(of: b.id) ?? Int.max
            return ai < bi
        }

        // Notify each list that its contents changed so SwiftUI re-renders rows.
        // TaskList is a class — mutating its items/properties in-place doesn't
        // automatically trigger the parent store's @Published lists to refresh views.
        merged.forEach { $0.objectWillChange.send() }
        self.lists = merged

        // Merge UI state
        if let rPos = remote.mergedListPosition, rPos != .zero {
            self.mergedListPosition = rPos
        }
        if let rSize = remote.mergedListSize, rSize.width > 0 {
            self.mergedListSize = rSize
        }

        // Merged task order: union, preserving remote order for known IDs
        let allTaskIds = Set(merged.flatMap { $0.items.map { $0.id } })
        let remoteOrderFiltered = remote.mergedTaskOrder.filter { allTaskIds.contains($0) }
        let localOnlyIds = self.mergedTaskOrder.filter { !remoteOrderFiltered.contains($0) && allTaskIds.contains($0) }
        self.mergedTaskOrder = remoteOrderFiltered + localOnlyIds

        #if os(iOS)
        writeWidgetSnapshot()
        #endif

        self.resubscribeListObservers()
        if save { self.performSave() }
    }

    /// Merge two item arrays by id; tombstones win over everything, then newer lastModified wins.
    private func mergeItems(local: [TaskItem], remote: [TaskItem], deletedIDs: [UUID: Date]) -> [TaskItem] {
        var localById: [UUID: TaskItem] = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var merged: [TaskItem] = []

        for remoteItem in remote {
            // If tombstoned, skip entirely
            if deletedIDs[remoteItem.id] != nil { continue }

            if let localItem = localById[remoteItem.id] {
                if remoteItem.lastModified > localItem.lastModified {
                    merged.append(remoteItem)
                } else if localItem.lastModified > remoteItem.lastModified {
                    merged.append(localItem)
                } else {
                    // Timestamp tie: prefer remote when payload differs so cloud-originated
                    // edits still apply even if lastModified wasn't bumped upstream.
                    merged.append(remoteItem == localItem ? localItem : remoteItem)
                }
                localById.removeValue(forKey: remoteItem.id)
            } else {
                merged.append(remoteItem)
            }
        }
        // Items only in local — keep unless tombstoned
        for (id, localItem) in localById {
            if deletedIDs[id] != nil { continue }
            merged.append(localItem)
        }
        return merged
    }

    // MARK: - Manual Refresh

    /// Force a full sync: re-broadcast current state to Firestore so other devices
    /// pick it up, and (on macOS) trigger an immediate poll.
    func manualRefresh() {
        print("🔵 [TaskStore] manualRefresh() — user requested sync")
        do {
            let data = try encodeStore()
            firebaseSync.broadcast(data: data)
            firebaseSync.forcePoll()
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - CRUD

    func createNewList() {
        let newList = TaskList(title: "New List")
        lists.append(newList)
        setupObservers()
        save()
    }

    func deleteList(_ list: TaskList) {
        deletedListIDs[list.id] = Date()   // tombstone — prevents resurrection from remote
        lists.removeAll { $0.id == list.id }
        setupObservers()
        save()
    }

    /// Call this whenever you mutate a list's properties so the timestamp is updated.
    func touch(_ list: TaskList) {
        list.lastModified = Date()
        save()
    }

    /// Call this whenever you mutate a task item inside a list.
    func touchItem(in list: TaskList) {
        list.lastModified = Date()
        // Update the item's own lastModified at call site too if needed
        save()
    }

    /// Centralized item mutation path to ensure item/list timestamps are always stamped.
    func updateTask(taskID: UUID, mutation: (inout TaskItem) -> Void) {
        for i in 0..<lists.count {
            if let j = lists[i].items.firstIndex(where: { $0.id == taskID }) {
                mutation(&lists[i].items[j])
                lists[i].items[j].lastModified = Date()
                lists[i].lastModified = Date()
                save()
                return
            }
        }
    }

    /// Toggles completion state with proper timestamp stamping for conflict-safe sync.
    func toggleTaskCompletion(taskID: UUID) {
        updateTask(taskID: taskID) { item in
            item.isCompleted.toggle()
            if item.isCompleted {
                item.reminderDate = nil
            }
        }
    }

    func getAllTasks() -> [TaskItem] {
        lists.flatMap { $0.items }
    }

    // MARK: - Sign-out cleanup

    /// Clears in-memory + on-disk task data after auth transitions from signed-in to signed-out.
    private func clearAllLocalDataAfterSignOut() {
        print("🔵 [TaskStore] clearAllLocalDataAfterSignOut()")
        saveWorkItem?.cancel()

        lists = []
        mergedTaskOrder = []
        mergedListPosition = .zero
        mergedListSize = CGSize(width: 350, height: 500)
        deletedListIDs = [:]
        isApplyingRemoteData = false
        syncStatus = .disconnected

        do {
            if FileManager.default.fileExists(atPath: savePath.path) {
                try FileManager.default.removeItem(at: savePath)
                print("🔵 [TaskStore] Removed local snapshot at \(savePath.path)")
            }
            #if os(iOS)
            if let widgetURL = widgetSnapshotURL(),
               FileManager.default.fileExists(atPath: widgetURL.path) {
                try FileManager.default.removeItem(at: widgetURL)
            }
            UserDefaults(suiteName: appGroupID)?.removeObject(forKey: widgetSnapshotDefaultsKey)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            print("🔴 [TaskStore] Failed to remove local snapshot: \(error)")
        }
    }

    #if os(iOS)
    private func widgetSnapshotURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(widgetSnapshotFilename)
    }

    private func writeWidgetSnapshot() {
        let incompleteTasks = orderedMergedTasks().filter { !$0.isCompleted }
        let preview = incompleteTasks.prefix(8).map {
            WidgetTaskSnapshotItem(
                id: $0.id,
                content: $0.content,
                isCompleted: $0.isCompleted,
                priority: $0.priority.title,
                status: $0.status.title,
                estimatedMinutes: $0.estimatedMinutes
            )
        }
        let snapshot = MergedWidgetSnapshot(
            generatedAt: Date(),
            completedCount: getAllTasks().filter(\.isCompleted).count,
            totalCount: getAllTasks().count,
            items: Array(preview)
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            if let url = widgetSnapshotURL() {
                try data.write(to: url, options: .atomic)
            } else {
                print("🟡 [TaskStore] App Group container URL unavailable for widget snapshot file write")
            }

            if let json = String(data: data, encoding: .utf8) {
                if let sharedDefaults = UserDefaults(suiteName: appGroupID) {
                    sharedDefaults.set(json, forKey: widgetSnapshotDefaultsKey)
                } else {
                    print("🟡 [TaskStore] App Group defaults unavailable for widget snapshot defaults write")
                }
            }
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("🟡 [TaskStore] Failed to write widget snapshot: \(error)")
        }
    }

    private func orderedMergedTasks() -> [TaskItem] {
        let allTasks = getAllTasks()
        let taskMap = Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
        var sortedTasks: [TaskItem] = []
        for id in mergedTaskOrder {
            if let task = taskMap[id] { sortedTasks.append(task) }
        }
        let orderedIDs = Set(mergedTaskOrder)
        for task in allTasks where !orderedIDs.contains(task.id) {
            sortedTasks.append(task)
        }
        return sortedTasks
    }
    #endif
}

// MARK: - StoreWrapper

struct StoreWrapper: Codable {
    var lists: [TaskList]
    var mergedTaskOrder: [UUID]
    var mergedListPosition: CGPoint?
    var mergedListSize: CGSize?
    /// Tombstone map: list id → time it was deleted.
    /// Lists in this set are never resurrected by remote merges.
    var deletedListIDs: [UUID: Date]

    init(lists: [TaskList], mergedTaskOrder: [UUID],
         mergedListPosition: CGPoint? = nil, mergedListSize: CGSize? = nil,
         deletedListIDs: [UUID: Date] = [:]) {
        self.lists = lists
        self.mergedTaskOrder = mergedTaskOrder
        self.mergedListPosition = mergedListPosition
        self.mergedListSize = mergedListSize
        self.deletedListIDs = deletedListIDs
    }

    // Backward-compatible decoding — old snapshots have no deletedListIDs
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lists               = try c.decode([TaskList].self, forKey: .lists)
        mergedTaskOrder     = (try? c.decode([UUID].self, forKey: .mergedTaskOrder)) ?? []
        mergedListPosition  = try? c.decode(CGPoint.self, forKey: .mergedListPosition)
        mergedListSize      = try? c.decode(CGSize.self,  forKey: .mergedListSize)
        deletedListIDs      = (try? c.decode([UUID: Date].self, forKey: .deletedListIDs)) ?? [:]
    }
}

#if os(iOS)
struct WidgetTaskSnapshotItem: Codable, Identifiable {
    let id: UUID
    let content: String
    let isCompleted: Bool
    let priority: String
    let status: String
    let estimatedMinutes: Int?
}

struct MergedWidgetSnapshot: Codable {
    let generatedAt: Date
    let completedCount: Int
    let totalCount: Int
    let items: [WidgetTaskSnapshotItem]
}
#endif
