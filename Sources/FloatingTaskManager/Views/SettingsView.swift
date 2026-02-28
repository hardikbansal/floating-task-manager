import SwiftUI

struct SettingsView: View {
    @AppStorage("baseFontSize") var baseFontSize: Double = 13.0
    @AppStorage("windowOpacity") var windowOpacity: Double = 0.95
    @AppStorage("enableShadows") var enableShadows: Bool = true
    #if os(macOS)
    @EnvironmentObject var store: TaskStore
    #endif

    var body: some View {
        VStack(spacing: 20) {
            // Title Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Configure your floating experience")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 10)

            // Settings Grid
            VStack(spacing: 12) {
                SettingsTile(title: "Text Size", icon: "textformat.size", value: "\(Int(baseFontSize))pt") {
                    Slider(value: $baseFontSize, in: 10...24, step: 1)
                        .controlSize(.mini)
                }

                SettingsTile(title: "Window Opacity", icon: "circle.lefthalf.filled", value: "\(Int(windowOpacity * 100))%") {
                    Slider(value: $windowOpacity, in: 0.1...1.0, step: 0.05)
                        .controlSize(.mini)
                }

                HStack(spacing: 12) {
                    SettingsToggleTile(title: "Window Shadows", icon: "shadow", isOn: $enableShadows)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("About")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        Text("v1.1.0 Premium")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
                }

                #if os(macOS)
                MacFirebaseSyncTile(store: store)
                #endif
            }

            Spacer()
        }
        .padding(30)
        #if os(macOS)
        .frame(width: 520, height: 500)
        .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
        #else
        .background(VisualEffectView(material: .systemMaterial))
        #endif
    }
}

// MARK: - macOS Firebase Sync Tile

#if os(macOS)
struct MacFirebaseSyncTile: View {
    @ObservedObject var store: TaskStore
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .bold))
                Text("Firebase Sync")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button(action: { WindowManager.shared.showLogViewerWindow() }) {
                    Label("Logs", systemImage: "terminal")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                syncBadge
            }

            switch store.firebaseSync.authState {
            case .signedIn(let signedInEmail):
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Signed in: \(signedInEmail)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Sign Out") {
                        store.firebaseSync.signOut()
                        email = ""
                        password = ""
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

            case .signedOut:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in to sync tasks across your devices.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .rounded))
                            .disableAutocorrection(true)
                            .frame(maxWidth: .infinity)

                        SecureField("Password (min 6)", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }

                    HStack {
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(.red)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(isSigningIn ? "Signing In…" : "Sign In / Create Account") {
                            handleSignIn()
                        }
                        .disabled(isSigningIn || email.count < 5 || password.count < 6)
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    private var syncBadge: some View {
        let s = store.syncStatus
        Label(s.label, systemImage: s.icon)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(s.color)
            .lineLimit(1)
    }

    private func handleSignIn() {
        isSigningIn = true
        errorMessage = nil
        store.firebaseSync.signIn(
            email: email.trimmingCharacters(in: .whitespaces),
            password: password
        ) { error in
            isSigningIn = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                password = ""
                // start() + forcePoll() are called by the TaskStore authState subscriber
                // when authState transitions to .signedIn — no need to call them here.
            }
        }
    }
}
#endif

// ...existing code...


struct SettingsTile<Content: View>: View {
    let title: String
    let icon: String
    let value: String
    let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.04)))
    }
}

struct SettingsToggleTile: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(isOn ? .blue : .secondary)
                        .font(.system(size: 14, weight: .bold))
                    Spacer()
                    Toggle("", isOn: $isOn)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.7)
                }
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(isOn ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOn ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

