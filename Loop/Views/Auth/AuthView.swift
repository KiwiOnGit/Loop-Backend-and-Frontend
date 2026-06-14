import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var mode: AuthMode = .login
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var showingServerSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.loopInk, .black, Color(red: 0.02, green: 0.10, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    brandHeader

                    VStack(spacing: 14) {
                        Picker("Mode", selection: $mode) {
                            ForEach(AuthMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(.loopGreen)

                        VStack(spacing: 12) {
                            TextField(mode == .login ? "Email or username" : "Email", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .loopField(dark: true)

                            if mode == .signup {
                                TextField("Username", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .textContentType(.nickname)
                                    .loopField(dark: true)
                            }

                            SecureField("Password", text: $password)
                                .textContentType(mode == .login ? .password : .newPassword)
                                .loopField(dark: true)
                        }

                        PrimaryLoopButton(
                            title: mode == .login ? "Sign in" : "Create account",
                            systemImage: mode == .login ? "arrow.right" : "sparkles",
                            isLoading: isSubmitting
                        ) {
                            Task { await submit() }
                        }

                        if let authError = session.authError {
                            Label(authError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.loopWarm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    }

                    Button {
                        showingServerSettings = true
                    } label: {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 92)
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showingServerSettings) {
            ServerURLSheet()
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
        }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.loopGreen)

                Text("Loop")
                    .font(LoopFont.logo(58))
                    .foregroundStyle(.loopGreen)
            }

            Text("Six seconds. Real people. Fast loops.")
                .font(LoopFont.display(20, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() async {
        guard !isSubmitting else {
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        session.saveServerURL()
        switch mode {
        case .login:
            await session.login(emailOrUsername: email, password: password)
        case .signup:
            await session.signUp(email: email, username: username, password: password)
        }
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case login
    case signup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login:
            "Sign in"
        case .signup:
            "Join"
        }
    }
}

private struct ServerURLSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Server URL", text: $session.serverURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .loopField()

                PrimaryLoopButton(title: "Save", systemImage: "checkmark") {
                    session.saveServerURL()
                    dismiss()
                }
            }
            .padding(20)
            .navigationTitle("Advanced")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
