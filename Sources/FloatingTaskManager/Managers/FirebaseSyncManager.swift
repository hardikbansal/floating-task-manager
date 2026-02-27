import Foundation
import Combine

#if os(iOS)
import UIKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - FTMLog — thin logger that prefixes all messages with [FirebaseSyncManager]
// All log lines are visible in Xcode console, Console.app (filter by "FTM"),
// and in the in-app Log Viewer window (macOS).
private func ftmLog(_ msg: String, file: String = #file, line: Int = #line) {
    let filename = URL(fileURLWithPath: file).lastPathComponent
    print("🔵 [FTM:\(filename):\(line)] \(msg)")
}
private func ftmError(_ msg: String, file: String = #file, line: Int = #line) {
    let filename = URL(fileURLWithPath: file).lastPathComponent
    print("🔴 [FTM:\(filename):\(line)] \(msg)")
}
private func ftmWarn(_ msg: String, file: String = #file, line: Int = #line) {
    let filename = URL(fileURLWithPath: file).lastPathComponent
    print("🟡 [FTM:\(filename):\(line)] \(msg)")
}

// MARK: - FirebaseSyncManager (iOS — Firebase)
// Cloud sync via Firebase Firestore + Email/Password Authentication.
// All devices signed in with the same email share the same
// Firestore path → automatic cross-device sync.

class FirebaseSyncManager: ObservableObject {

    // MARK: - Stable per-device identifier (NOT the Firebase UID)
    // Uses UIDevice.identifierForVendor — unique per device, persists across app reinstalls
    // only if iCloud Keychain is enabled; good enough for our purposes.
    private static let deviceID: String =
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    // MARK: - Auth state

    enum AuthState: Equatable {
        case signedOut
        case signedIn(email: String)
    }

    @Published var authState: AuthState = .signedOut {
        didSet { ftmLog("authState changed → \(authState)") }
    }
    @Published var syncStatus: PeerSyncStatus = .disconnected {
        didSet { ftmLog("syncStatus changed → \(syncStatus)") }
    }

    enum PeerSyncStatus: Equatable {
        case disconnected   // not signed in
        case connected      // listener active
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: - Public callbacks
    var onReceivedData: ((Data) -> Void)?

    // MARK: - Private
    private let db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    var currentUID: String?   // internal — read by TaskStore for resting sync status
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var settleWorkItem: DispatchWorkItem?  // debounces synced → connected

    // Tracks whether signOut() was called explicitly by the user
    private var isExplicitSignOut = false

    // MARK: - Init

    init() {
        ftmLog("FirebaseSyncManager init — Firebase configured: \(FirebaseApp.app() != nil)")
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            DispatchQueue.main.async {
                if let user {
                    ftmLog("Auth state changed → signed IN | uid=\(user.uid) email=\(user.email ?? "nil") emailVerified=\(user.isEmailVerified)")
                    self.currentUID = user.uid
                    let email = user.email ?? "Unknown"
                    self.authState = .signedIn(email: email)
                    self.attachListener(uid: user.uid)
                } else {
                    if self.isExplicitSignOut {
                        ftmLog("Auth state changed → signed OUT (user-initiated)")
                    } else {
                        ftmError("Auth state changed → signed OUT unexpectedly (Firebase SDK auto sign-out — token may have been revoked or invalidated)")
                    }
                    self.isExplicitSignOut = false
                    self.currentUID = nil
                    self.authState = .signedOut
                    self.listenerRegistration?.remove()
                    self.listenerRegistration = nil
                    self.syncStatus = .disconnected
                }
            }
        }
    }

    deinit {
        ftmLog("FirebaseSyncManager deinit")
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Email/Password Auth

    /// Sign in with email + password. Creates the account automatically if it doesn't exist yet.
    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        ftmLog("signIn() called | email=\(email)")

        guard FirebaseApp.app() != nil else {
            ftmError("Firebase is not configured — aborting signIn()")
            completion(NSError(domain: "FirebaseSyncManager", code: -2,
                               userInfo: [NSLocalizedDescriptionKey: "Firebase is not configured."]))
            return
        }

        ftmLog("Calling Auth.auth().signIn(withEmail:password:) …")
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            if let error = error as NSError? {
                ftmWarn("signIn failed | code=\(error.code) domain=\(error.domain) desc=\(error.localizedDescription)")
                let isNotFound       = error.code == AuthErrorCode.userNotFound.rawValue
                let isInvalidCred    = error.code == AuthErrorCode.invalidCredential.rawValue
                let isWrongPassword  = error.code == AuthErrorCode.wrongPassword.rawValue

                if isNotFound || isInvalidCred || isWrongPassword {
                    ftmLog("Attempting createUser (account may not exist yet) …")
                    Auth.auth().createUser(withEmail: email, password: password) { [weak self] createResult, createError in
                        if let createError = createError as NSError? {
                            ftmError("createUser failed | code=\(createError.code) domain=\(createError.domain) desc=\(createError.localizedDescription)")
                            DispatchQueue.main.async {
                                self?.syncStatus = .error(createError.localizedDescription)
                                completion(createError)
                            }
                        } else {
                            ftmLog("createUser succeeded | uid=\(createResult?.user.uid ?? "nil")")
                            DispatchQueue.main.async { completion(nil) }
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self?.syncStatus = .error(error.localizedDescription)
                        completion(error)
                    }
                }
            } else {
                ftmLog("signIn succeeded | uid=\(result?.user.uid ?? "nil") email=\(result?.user.email ?? "nil")")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// Explicit register (creates a new account, errors if already exists).
    func register(email: String, password: String, completion: @escaping (Error?) -> Void) {
        ftmLog("register() called | email=\(email)")
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            if let error = error as NSError? {
                ftmError("register failed | code=\(error.code) desc=\(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.syncStatus = .error(error.localizedDescription)
                    completion(error)
                }
            } else {
                ftmLog("register succeeded | uid=\(result?.user.uid ?? "nil")")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        ftmLog("signOut() called — marking as explicit")
        isExplicitSignOut = true
        do {
            try Auth.auth().signOut()
            ftmLog("signOut succeeded")
        } catch {
            isExplicitSignOut = false
            ftmError("signOut error: \(error)")
        }
    }

    // MARK: - Lifecycle

    func start() {
        let currentUser = Auth.auth().currentUser
        ftmLog("start() — currentUser=\(currentUser?.uid ?? "nil")")
        if currentUser == nil {
            DispatchQueue.main.async { self.syncStatus = .disconnected }
        }
    }

    func stop() {
        ftmLog("stop() called")
        listenerRegistration?.remove()
        listenerRegistration = nil
        settleWorkItem?.cancel()
    }

    /// Force an immediate re-read from Firestore (used by manual refresh).
    func forcePoll() {
        guard let uid = currentUID else { return }
        ftmLog("forcePoll() — re-attaching listener for uid=\(uid)")
        attachListener(uid: uid)
    }

    // MARK: - Broadcast

    func broadcast(data: Data, allowAuthRetry: Bool = true) {
        guard let docRef = storeDocRef() else {
            ftmWarn("broadcast() skipped — no docRef (not signed in?)")
            return
        }
        guard let jsonString = String(data: data, encoding: .utf8) else {
            ftmError("broadcast() failed — data is not valid UTF-8")
            return
        }

        ftmLog("broadcast() — writing \(data.count) bytes …")

        Auth.auth().currentUser?.getIDTokenForcingRefresh(false) { [weak self] _, tokenError in
            guard let self else { return }
            if let tokenError {
                ftmWarn("broadcast() token check warning (will try write anyway): \(tokenError.localizedDescription)")
            }
            docRef.setData([
                "payload": jsonString,
                "updatedAt": FieldValue.serverTimestamp(),
                "deviceId": Self.deviceID
            ]) { [weak self] writeError in
                guard let self else { return }
                DispatchQueue.main.async {
                    if let writeError {
                        self.syncStatus = .error(writeError.localizedDescription)
                        ftmError("Firestore write error: \(writeError.localizedDescription)")
                    } else {
                        ftmLog("📤 Synced \(data.count) bytes to Firestore")
                        // Stay on .connected — no transient state changes
                    }
                }
            }
        }
    }

    // MARK: - Private helpers

    private func storeDocRef() -> DocumentReference? {
        guard let uid = currentUID else {
            ftmWarn("storeDocRef() — currentUID is nil")
            return nil
        }
        return db.collection("users").document(uid).collection("store").document("snapshot")
    }

    // Retry counter so we don't loop forever on persistent permission errors
    private var listenerRetryCount = 0
    private static let maxListenerRetries = 4

    /// Force-refresh the Firebase ID token first, THEN attach the Firestore listener.
    /// This prevents the "Missing or insufficient permissions" error that occurs when
    /// the cached ID token has expired or hasn't been issued yet after a fresh sign-in.
    private func attachListener(uid: String) {
        ftmLog("attachListener() for uid=\(uid) — forcing ID token refresh before attaching listener")
        listenerRegistration?.remove()

        guard let currentUser = Auth.auth().currentUser, currentUser.uid == uid else {
            ftmError("attachListener() — no current user or UID mismatch (expected \(uid))")
            return
        }

        // Force-refresh the token so Firestore receives a fresh, valid Bearer token
        currentUser.getIDTokenForcingRefresh(true) { [weak self] token, error in
            guard let self else { return }
            if let error {
                ftmError("getIDTokenForcingRefresh failed: \(error.localizedDescription) — retrying in 3s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    self?.attachListener(uid: uid)
                }
                return
            }
            ftmLog("ID token refreshed successfully (token prefix: \(String((token ?? "").prefix(20)))…)")
            self.attachListenerAfterTokenRefresh(uid: uid)
        }
    }

    private func attachListenerAfterTokenRefresh(uid: String) {
        guard let docRef = storeDocRef() else {
            ftmError("attachListenerAfterTokenRefresh() — could not get docRef")
            return
        }

        ftmLog("Attaching Firestore snapshot listener for uid=\(uid)")
        DispatchQueue.main.async { self.syncStatus = .connected }
        listenerRetryCount = 0

        listenerRegistration = docRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                let nsErr = error as NSError
                let code = nsErr.code
                ftmError("Firestore listener error: code=\(code) \(error.localizedDescription)")

                // Code 7 = PERMISSION_DENIED — token may have been stale despite refresh.
                // Remove the listener, force-refresh the token again and reattach.
                if code == 7 && self.listenerRetryCount < Self.maxListenerRetries {
                    self.listenerRetryCount += 1
                    let delay = Double(self.listenerRetryCount) * 2.0 // 2s, 4s, 6s, 8s
                    ftmWarn("Permission denied — retry \(self.listenerRetryCount)/\(Self.maxListenerRetries) in \(delay)s")
                    self.listenerRegistration?.remove()
                    self.listenerRegistration = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        guard let self else { return }
                        self.attachListener(uid: uid)
                    }
                } else {
                    DispatchQueue.main.async { self.syncStatus = .error(error.localizedDescription) }
                }
                return
            }

            guard let snapshot else {
                ftmWarn("Firestore snapshot is nil (no error)")
                return
            }
            ftmLog("Firestore snapshot received | exists=\(snapshot.exists) data keys=\(snapshot.data()?.keys.joined(separator: ",") ?? "nil")")

            guard snapshot.exists,
                  let jsonString = snapshot.data()?["payload"] as? String,
                  let deviceId = snapshot.data()?["deviceId"] as? String
            else {
                ftmWarn("Firestore snapshot missing required fields (payload/deviceId) or document doesn't exist yet — this is normal if no data has been synced yet")
                return
            }

            // Reset retry counter on a successful snapshot
            self.listenerRetryCount = 0
            ftmLog("Firestore snapshot | deviceId=\(deviceId) myUID=\(self.currentUID ?? "nil") payloadLen=\(jsonString.count)")

            guard deviceId != Self.deviceID else {
                ftmLog("Skipping snapshot — it was written by this device (deviceId=\(deviceId))")
                return
            }
            guard let data = jsonString.data(using: .utf8) else {
                ftmError("Firestore payload is not valid UTF-8")
                return
            }

            ftmLog("📥 Received \(data.count) bytes from Firestore (device: \(deviceId))")
            DispatchQueue.main.async {
                self.onReceivedData?(data)
            }
        }
    }
}



#else

// MARK: - FirebaseSyncManager (macOS — Firestore REST API)
// Uses Firebase Auth REST + Firestore REST so no SDK is needed for `swift build`.
// Auth flow:
//   1. User signs in with phone on their iPhone.
//   2. iOS Settings shows a "Link Mac" refresh token — user copies it.
//   3. User pastes it once into the Mac app's Settings window.
//   4. Mac exchanges the refresh token for an ID token on every launch and polls
//      Firestore via the REST listen endpoint (Server-Sent Events).
//
// Refresh tokens never expire unless explicitly revoked, so this is a one-time setup.

import AppKit

class FirebaseSyncManager: NSObject, ObservableObject, URLSessionDataDelegate {

    // MARK: - Stable per-device identifier (NOT the Firebase UID)
    private static let deviceID: String = {
        if let saved = UserDefaults.standard.string(forKey: "ftm.deviceID") { return saved }
        let id = "mac-" + UUID().uuidString
        UserDefaults.standard.set(id, forKey: "ftm.deviceID")
        return id
    }()

    // MARK: - Shared config (must match GoogleService-Info.plist values)
    // Read from a small JSON sidecar so we don't hard-code secrets.
    // Falls back to compile-time defaults set in FirebaseConfig.swift.
    static var apiKey: String = FirebaseConfig.apiKey
    static var projectId: String = FirebaseConfig.projectId

    // MARK: - Auth state

    enum AuthState: Equatable {
        case signedOut
        case signedIn(email: String)
    }

    @Published var authState: AuthState = .signedOut
    @Published var syncStatus: PeerSyncStatus = .disconnected

    enum PeerSyncStatus: Equatable {
        case disconnected
        case connected
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    var onReceivedData: ((Data) -> Void)?

    // MARK: - Private state
    var currentUID: String?   // internal — read by TaskStore
    private var idToken: String?
    private var idTokenExpiry: Date = .distantPast
    private var sseSession: URLSession?
    private var sseTask: URLSessionDataTask?
    private var sseBuffer: String = ""
    private var pollTimer: Timer?
    private var lastKnownUpdatedAt: String?  // Firestore updatedAt — skips already-processed snapshots
    private var isPollInFlight = false
    private var consecutivePollFailures = 0
    private var currentPollInterval: TimeInterval = 10

    private static let minPollInterval: TimeInterval = 10
    private static let maxPollInterval: TimeInterval = 90
    private static let pollBackoffMultiplier: Double = 1.8
    private static let visibleErrorThreshold = 3

    // Keychain keys
    private static let keychainRefreshTokenKey = "ftm.firebase.refreshToken"
    private static let keychainUIDKey          = "ftm.firebase.uid"
    private static let keychainEmailKey        = "ftm.firebase.email"
    private static let defaultsRefreshTokenKey = "ftm.defaults.firebase.refreshToken"
    private static let defaultsUIDKey          = "ftm.defaults.firebase.uid"
    private static let defaultsEmailKey        = "ftm.defaults.firebase.email"

    // MARK: - Init

    override init() {
        super.init()
        // Restore session on launch.
        if let _ = Self.secureLoad(key: Self.keychainRefreshTokenKey, defaultsKey: Self.defaultsRefreshTokenKey),
           let uid = Self.secureLoad(key: Self.keychainUIDKey, defaultsKey: Self.defaultsUIDKey) {
            currentUID = uid
            let email = Self.secureLoad(key: Self.keychainEmailKey, defaultsKey: Self.defaultsEmailKey) ?? uid
            appLog("Restored saved sync session for uid=\(uid) email=\(email)")
            DispatchQueue.main.async {
                self.authState = .signedIn(email: email)
            }
        } else {
            appWarn("No saved sync session found on launch (refresh token/uid missing)")
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard case .signedIn = authState else {
            appWarn("start() skipped: authState is signedOut")
            DispatchQueue.main.async { self.syncStatus = .disconnected }
            return
        }
        guard !Self.projectId.isEmpty else {
            appError("start() failed: PROJECT_ID missing")
            DispatchQueue.main.async {
                self.syncStatus = .error("GoogleService-Info.plist missing PROJECT_ID.")
            }
            return
        }
        appLog("start() beginning sync bootstrap for uid=\(currentUID ?? "nil")")
        refreshTokenThenListen()
    }

    func stop() {
        sseTask?.cancel()
        pollTimer?.invalidate()
        pollTimer = nil
        isPollInFlight = false
    }

    /// Force an immediate Firestore fetch (used by manual refresh button).
    func forcePoll() {
        guard let uid = currentUID else { return }
        appLog("forcePoll() — clearing dedup and re-fetching")
        lastKnownUpdatedAt = nil   // clear dedup so the next poll always re-applies
        pollFirestore(uid: uid)
    }

    // MARK: - Email / Password Auth (Firebase Auth REST)

    /// Sign in with email + password. Creates the account automatically if it doesn't exist.
    func signIn(email: String, password: String, completion: @escaping (Error?) -> Void) {
        appLog("signIn() started | projectId='\(Self.projectId)'")

        if Self.apiKey.isEmpty {
            let err = NSError(domain: "FirebaseSyncManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "GoogleService-Info.plist not found or API_KEY is missing. Make sure the plist is in the project root and rebuild."
            ])
            DispatchQueue.main.async { self.syncStatus = .error(err.localizedDescription); completion(err) }
            return
        }
        if Self.projectId.isEmpty {
            let err = NSError(domain: "FirebaseSyncManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "GoogleService-Info.plist not found or PROJECT_ID is missing. Make sure the plist is bundled with the app."
            ])
            DispatchQueue.main.async { self.syncStatus = .error(err.localizedDescription); completion(err) }
            return
        }

        signInREST(email: email, password: password) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let info):
                self.saveSession(refreshToken: info.refreshToken, uid: info.uid, email: email)
                DispatchQueue.main.async {
                    self.idToken       = info.idToken
                    self.idTokenExpiry = Date().addingTimeInterval(3500)
                    self.currentUID    = info.uid
                    self.authState     = .signedIn(email: email)
                    completion(nil)
                    self.attachListener()
                }
            case .failure(let err as NSError):
                let msg = err.userInfo[NSLocalizedDescriptionKey] as? String ?? ""
                appError("signIn failed: code=\(err.code) msg=\(msg)")

                // OPERATION_NOT_ALLOWED → Email/Password provider is disabled in Firebase console
                if msg.contains("OPERATION_NOT_ALLOWED") {
                    let friendly = NSError(domain: "FirebaseSyncManager", code: err.code, userInfo: [
                        NSLocalizedDescriptionKey: "Email/Password sign-in is not enabled. Go to Firebase Console → Authentication → Sign-in method → enable Email/Password."
                    ])
                    DispatchQueue.main.async { self.syncStatus = .error(friendly.localizedDescription); completion(friendly) }
                    return
                }

                // API key restriction — iOS-only key used from macOS REST calls
                if msg.lowercased().contains("unregistered callers") || msg.contains("UNAUTHORIZED_DOMAIN") || msg.contains("API key not valid") {
                    let friendly = NSError(domain: "FirebaseSyncManager", code: err.code, userInfo: [
                        NSLocalizedDescriptionKey: "API key is restricted to iOS. Go to Google Cloud Console → APIs & Services → Credentials → find this key → remove iOS app restriction (or add a MAC_API_KEY to GoogleService-Info.plist)."
                    ])
                    DispatchQueue.main.async { self.syncStatus = .error(friendly.localizedDescription); completion(friendly) }
                    return
                }

                // EMAIL_NOT_FOUND → account doesn't exist yet, try creating it
                if msg.contains("EMAIL_NOT_FOUND") {
                    appLog("email not found — attempting createUser")
                    self.createUserREST(email: email, password: password) { [weak self] createResult in
                        guard let self else { return }
                        switch createResult {
                        case .success(let info):
                            self.saveSession(refreshToken: info.refreshToken, uid: info.uid, email: email)
                            DispatchQueue.main.async {
                                self.idToken       = info.idToken
                                self.idTokenExpiry = Date().addingTimeInterval(3500)
                                self.currentUID    = info.uid
                                self.authState     = .signedIn(email: email)
                                completion(nil)
                                self.attachListener()
                            }
                        case .failure(let createErr):
                            appError("createUser failed: \(createErr.localizedDescription)")
                            DispatchQueue.main.async {
                                self.syncStatus = .error(createErr.localizedDescription)
                                completion(createErr)
                            }
                        }
                    }
                } else {
                    // INVALID_PASSWORD, INVALID_LOGIN_CREDENTIALS, etc. — show as-is
                    DispatchQueue.main.async {
                        self.syncStatus = .error(msg.isEmpty ? err.localizedDescription : msg)
                        completion(err)
                    }
                }
            }
        }
    }

    private func saveSession(refreshToken: String, uid: String, email: String) {
        Self.secureSave(key: Self.keychainRefreshTokenKey, defaultsKey: Self.defaultsRefreshTokenKey, value: refreshToken)
        Self.secureSave(key: Self.keychainUIDKey,          defaultsKey: Self.defaultsUIDKey,          value: uid)
        Self.secureSave(key: Self.keychainEmailKey,        defaultsKey: Self.defaultsEmailKey,        value: email)
    }

    func signOut() {
        stop()
        currentUID = nil
        idToken    = nil
        consecutivePollFailures = 0
        currentPollInterval = Self.minPollInterval
        Self.secureDelete(key: Self.keychainRefreshTokenKey, defaultsKey: Self.defaultsRefreshTokenKey)
        Self.secureDelete(key: Self.keychainUIDKey,          defaultsKey: Self.defaultsUIDKey)
        Self.secureDelete(key: Self.keychainEmailKey,        defaultsKey: Self.defaultsEmailKey)
        DispatchQueue.main.async {
            self.authState  = .signedOut
            self.syncStatus = .disconnected
        }
    }


    // MARK: - Broadcast (Firestore REST PATCH)

    func broadcast(data: Data, allowAuthRetry: Bool = true) {
        guard let uid = currentUID,
              let jsonString = String(data: data, encoding: .utf8) else { return }

        withFreshToken { [weak self] tokenResult in
            guard let self else { return }
            guard case .success(let token) = tokenResult else {
                if case .failure(let err) = tokenResult {
                    DispatchQueue.main.async {
                        self.syncStatus = .error("Sync auth failed: \(err.localizedDescription)")
                    }
                    appError("broadcast() token refresh failed: \(err.localizedDescription)")
                }
                return
            }
            let deviceId = Self.deviceID
            let body: [String: Any] = [
                "fields": [
                    "payload":   ["stringValue": jsonString],
                    "deviceId":  ["stringValue": deviceId],
                    "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())]
                ]
            ]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

            let urlStr = "https://firestore.googleapis.com/v1/projects/\(Self.projectId)/databases/(default)/documents/users/\(uid)/store/snapshot"
            var req = URLRequest(url: URL(string: urlStr)!)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = bodyData

            URLSession.shared.dataTask(with: req) { [weak self] responseData, resp, error in
                if let error {
                    DispatchQueue.main.async {
                        self?.syncStatus = .error(error.localizedDescription)
                    }
                    appError("Firestore REST write error: \(error.localizedDescription)")
                    return
                }

                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let raw = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                    if (http.statusCode == 401 || http.statusCode == 403), allowAuthRetry {
                        appWarn("Firestore write unauthorized (\(http.statusCode)); refreshing token and retrying once")
                        self?.idToken = nil
                        self?.broadcast(data: data, allowAuthRetry: false)
                        return
                    }
                    appError("Firestore REST write HTTP \(http.statusCode): \(raw)")
                    DispatchQueue.main.async {
                        self?.syncStatus = .error("Firestore write HTTP \(http.statusCode)")
                    }
                    return
                }

                appLog("📤 Synced \(data.count) bytes via REST")
                DispatchQueue.main.async {
                    self?.syncStatus = .connected
                }
            }.resume()
        }
    }

    // MARK: - Private: token management

    private func refreshTokenThenListen() {
        guard let refreshToken = Self.secureLoad(key: Self.keychainRefreshTokenKey, defaultsKey: Self.defaultsRefreshTokenKey) else {
            appWarn("refreshTokenThenListen() aborted: no refresh token in secure storage")
            DispatchQueue.main.async { self.syncStatus = .disconnected }
            return
        }
        appLog("refreshTokenThenListen() exchanging refresh token")
        exchangeRefreshToken(refreshToken) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                appError("refreshTokenThenListen() failed: \(err.localizedDescription)")
                DispatchQueue.main.async { self.syncStatus = .error(err.localizedDescription) }
            case .success(let info):
                self.idToken      = info.idToken
                self.idTokenExpiry = Date().addingTimeInterval(3500)
                if self.currentUID == nil { self.currentUID = info.uid }
                appLog("refreshTokenThenListen() success; attaching listener for uid=\(self.currentUID ?? info.uid)")
                DispatchQueue.main.async {
                    self.attachListener()
                }
            }
        }
    }

    private func withFreshToken(_ block: @escaping (Result<String, Error>) -> Void) {
        if let token = idToken, Date() < idTokenExpiry {
            block(.success(token)); return
        }
        guard let refreshToken = Self.secureLoad(key: Self.keychainRefreshTokenKey, defaultsKey: Self.defaultsRefreshTokenKey) else {
            let err = NSError(
                domain: "FirebaseSyncManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing refresh token. Please sign in again."]
            )
            block(.failure(err))
            return
        }
        exchangeRefreshToken(refreshToken) { [weak self] result in
            guard let self else {
                block(.failure(NSError(domain: "FirebaseSyncManager", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Sync manager deallocated"
                ])))
                return
            }
            switch result {
            case .failure(let err):
                self.idToken = nil
                block(.failure(err))
            case .success(let info):
                self.idToken = info.idToken
                self.idTokenExpiry = Date().addingTimeInterval(3500)
                block(.success(info.idToken))
            }
        }
    }

    private struct TokenInfo { let idToken: String; let uid: String }
    private struct AuthRESTInfo { let idToken: String; let refreshToken: String; let uid: String }

    // Firebase Auth REST — sign in existing account
    private func signInREST(email: String, password: String, completion: @escaping (Result<AuthRESTInfo, Error>) -> Void) {
        let urlStr = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(Self.apiKey)"
        performAuthREST(urlStr: urlStr, body: ["email": email, "password": password, "returnSecureToken": true], completion: completion)
    }

    // Firebase Auth REST — create new account
    private func createUserREST(email: String, password: String, completion: @escaping (Result<AuthRESTInfo, Error>) -> Void) {
        let urlStr = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(Self.apiKey)"
        performAuthREST(urlStr: urlStr, body: ["email": email, "password": password, "returnSecureToken": true], completion: completion)
    }

    private func performAuthREST(urlStr: String, body: [String: Any], completion: @escaping (Result<AuthRESTInfo, Error>) -> Void) {
        appLog("performAuthREST URL: \(urlStr)")
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Add Referer header — some API key restrictions require it
        req.setValue("https://\(Self.projectId).firebaseapp.com", forHTTPHeaderField: "Referer")
        req.setValue("https://\(Self.projectId).firebaseapp.com", forHTTPHeaderField: "X-Client-Version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let httpResp = response as? HTTPURLResponse {
                appLog("performAuthREST HTTP status: \(httpResp.statusCode)")
            }
            if let error { completion(.failure(error)); return }
            guard let data else {
                completion(.failure(NSError(domain: "FirebaseSyncManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No response data"])))
                return
            }
            let raw = String(data: data, encoding: .utf8) ?? "nil"
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "FirebaseSyncManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid JSON: \(raw)"])))
                return
            }
            // Firebase Auth REST returns error details in json["error"]["message"]
            if let errorObj = json["error"] as? [String: Any],
               let message = errorObj["message"] as? String {
                appError("performAuthREST error message: \(message) | full: \(errorObj)")
                completion(.failure(NSError(domain: "FirebaseSyncManager", code: (errorObj["code"] as? Int) ?? 400,
                    userInfo: [NSLocalizedDescriptionKey: message])))
                return
            }
            guard let idToken      = json["idToken"]      as? String,
                  let refreshToken = json["refreshToken"] as? String,
                  let uid          = json["localId"]      as? String
            else {
                completion(.failure(NSError(domain: "FirebaseSyncManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unexpected response: \(raw)"])))
                return
            }
            completion(.success(AuthRESTInfo(idToken: idToken, refreshToken: refreshToken, uid: uid)))
        }.resume()
    }

    private func exchangeRefreshToken(_ refreshToken: String, completion: @escaping (Result<TokenInfo, Error>) -> Void) {
        let urlStr = "https://securetoken.googleapis.com/v1/token?key=\(Self.apiKey)"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["grant_type": "refresh_token", "refresh_token": refreshToken]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error { completion(.failure(error)); return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let idToken = json["id_token"] as? String,
                  let uid = json["user_id"] as? String
            else {
                let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                completion(.failure(NSError(domain: "FirebaseSyncManager", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(raw)"])))
                return
            }
            completion(.success(TokenInfo(idToken: idToken, uid: uid)))
        }.resume()
    }

    // MARK: - Private: real-time listener via Firestore REST SSE

    private func attachListener() {
        guard let uid = currentUID else { return }
        DispatchQueue.main.async { self.syncStatus = .connected }
        appLog("Firestore REST listener attached for uid \(uid)")
        startSSE(uid: uid)
    }

    private func startSSE(uid: String) {
        sseTask?.cancel()
        // Use polling as a reliable cross-platform alternative to SSE streaming.
        pollTimer?.invalidate()
        currentPollInterval = Self.minPollInterval
        consecutivePollFailures = 0
        isPollInFlight = false
        // Immediate first fetch
        pollFirestore(uid: uid)
    }

    private func scheduleNextPoll(uid: String, after delay: TimeInterval? = nil) {
        pollTimer?.invalidate()
        let nextDelay = max(1, delay ?? currentPollInterval)
        pollTimer = Timer.scheduledTimer(withTimeInterval: nextDelay, repeats: false) { [weak self] _ in
            self?.pollFirestore(uid: uid)
        }
    }

    private func markPollSuccess(uid: String) {
        consecutivePollFailures = 0
        currentPollInterval = Self.minPollInterval
        DispatchQueue.main.async { self.syncStatus = .connected }
        scheduleNextPoll(uid: uid)
    }

    private func markPollFailure(uid: String, userMessage: String, debugMessage: String) {
        consecutivePollFailures += 1
        currentPollInterval = min(Self.maxPollInterval, max(Self.minPollInterval, currentPollInterval * Self.pollBackoffMultiplier))
        if consecutivePollFailures >= Self.visibleErrorThreshold {
            DispatchQueue.main.async { self.syncStatus = .error(userMessage) }
        } else {
            appWarn("Transient sync issue (\(consecutivePollFailures)/\(Self.visibleErrorThreshold)): \(debugMessage)")
        }
        scheduleNextPoll(uid: uid)
    }

    private func pollFirestore(uid: String, allowAuthRetry: Bool = true) {
        if isPollInFlight {
            return
        }
        isPollInFlight = true

        withFreshToken { [weak self] tokenResult in
            guard let self else { return }
            guard case .success(let token) = tokenResult else {
                self.isPollInFlight = false
                if case .failure(let err) = tokenResult {
                    self.markPollFailure(
                        uid: uid,
                        userMessage: "Sync auth failed. Please sign in again.",
                        debugMessage: "token refresh failed: \(err.localizedDescription)"
                    )
                } else {
                    self.markPollFailure(
                        uid: uid,
                        userMessage: "Sync auth failed. Please sign in again.",
                        debugMessage: "token refresh failed"
                    )
                }
                return
            }
            let path = "projects/\(Self.projectId)/databases/(default)/documents/users/\(uid)/store/snapshot"
            let urlStr = "https://firestore.googleapis.com/v1/\(path)"
            var req = URLRequest(url: URL(string: urlStr)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { [weak self] data, resp, error in
                guard let self else { return }
                self.isPollInFlight = false

                if let error {
                    self.markPollFailure(
                        uid: uid,
                        userMessage: "Network unavailable. Retrying…",
                        debugMessage: "Firestore poll error: \(error.localizedDescription)"
                    )
                    return
                }
                if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"

                    if (http.statusCode == 401 || http.statusCode == 403), allowAuthRetry {
                        appWarn("Firestore poll unauthorized (\(http.statusCode)); refreshing token and retrying once")
                        self.idToken = nil
                        self.pollFirestore(uid: uid, allowAuthRetry: false)
                        return
                    }

                    // Missing document is expected before first successful sync write.
                    if http.statusCode == 404, raw.contains("\"status\": \"NOT_FOUND\"") {
                        appLog("Firestore snapshot does not exist yet (uid=\(uid)); waiting for first write")
                        self.markPollSuccess(uid: uid)
                        return
                    }
                    self.markPollFailure(
                        uid: uid,
                        userMessage: "Sync server returned HTTP \(http.statusCode). Retrying…",
                        debugMessage: "Firestore poll HTTP \(http.statusCode): \(raw)"
                    )
                    return
                }
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                    self.markPollFailure(
                        uid: uid,
                        userMessage: "Sync response parse failed. Retrying…",
                        debugMessage: "Firestore poll parse error: \(raw)"
                    )
                    return
                }

                // A successfully fetched document may still be effectively empty for our schema.
                guard let fields = json["fields"] as? [String: Any],
                      let payloadField = fields["payload"] as? [String: Any],
                      let jsonString = payloadField["stringValue"] as? String,
                      let deviceIdField = fields["deviceId"] as? [String: Any],
                      let deviceId = deviceIdField["stringValue"] as? String
                else {
                    appLog("Firestore snapshot has no payload/deviceId yet (uid=\(uid)); waiting for next update")
                    self.markPollSuccess(uid: uid)
                    return
                }

                // Extract the server-assigned updatedAt timestamp for deduplication
                let updatedAt = (json["updateTime"] as? String) ?? (json["createTime"] as? String) ?? ""

                // Skip if this was written by this Mac
                guard deviceId != Self.deviceID else {
                    self.markPollSuccess(uid: uid)
                    return
                }
                // Skip if we already processed this exact snapshot version
                guard updatedAt != self.lastKnownUpdatedAt else {
                    self.markPollSuccess(uid: uid)
                    return
                }

                guard let payload = jsonString.data(using: .utf8) else { return }
                self.lastKnownUpdatedAt = updatedAt
                appLog("📥 Received \(payload.count) bytes from Firestore REST (device: \(deviceId), updatedAt: \(updatedAt))")
                DispatchQueue.main.async {
                    self.onReceivedData?(payload)
                }
                self.markPollSuccess(uid: uid)
            }.resume()
        }
    }

    // MARK: - Keychain helpers

    private static let keychainService = "com.hardikbansal.FloatingTaskManager.Firebase"

    private static var useKeychain: Bool {
        if ProcessInfo.processInfo.environment["FTM_DISABLE_KEYCHAIN"] == "1" { return false }
        if UserDefaults.standard.bool(forKey: "ftm.disableKeychain") { return false }
        return true
    }

    private static func secureSave(key: String, defaultsKey: String, value: String) {
        if useKeychain {
            keychainSave(key: key, value: value)
        } else {
            UserDefaults.standard.set(value, forKey: defaultsKey)
        }
    }

    private static func secureLoad(key: String, defaultsKey: String) -> String? {
        if useKeychain {
            return keychainLoad(key: key)
        }
        return UserDefaults.standard.string(forKey: defaultsKey)
    }

    private static func secureDelete(key: String, defaultsKey: String) {
        if useKeychain {
            keychainDelete(key: key)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    private static func keychainSave(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData:   data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func keychainLoad(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService,
            kSecAttrAccount:      key,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainDelete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#endif
