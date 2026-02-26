import SwiftUI

#if os(iOS)

/// Full-screen email/password auth flow.
struct PhoneAuthView: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismiss) var dismiss

    // MARK: - State
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    // MARK: - Body
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Icon + header
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 60))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.blue)

                    Text("Sign In to Sync")
                        .font(.system(size: 26, weight: .bold, design: .rounded))

                    Text("Enter your email and password to sync tasks across all your devices. An account will be created automatically if you don't have one.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Input fields
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        TextField("you@example.com", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)

                        SecureField("Min. 6 characters", text: $password)
                            .textContentType(.password)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 16)
                    }
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Sign In button
                Button(action: handleSignIn) {
                    Group {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign In / Create Account")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isLoading || email.count < 5 || password.count < 6)
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleSignIn() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        print("🔵 [PhoneAuthView] handleSignIn()")
        errorMessage = nil
        isLoading = true
        store.firebaseSync.signIn(email: trimmedEmail, password: password) { error in
            isLoading = false
            if let error {
                print("🔴 [PhoneAuthView] signIn callback — ERROR: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            } else {
                print("🟢 [PhoneAuthView] signIn callback — SUCCESS, dismissing sheet")
                dismiss()
            }
        }
    }
}

#Preview {
    PhoneAuthView()
}

#endif
