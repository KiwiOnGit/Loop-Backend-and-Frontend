import SwiftUI

@main
struct LoopApp: App {
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .task {
                    AdvertisingService.shared.configure()
                    await session.bootstrap()
                }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Group {
                if session.isBootstrapping {
                    SplashView()
                } else if session.currentUser == nil {
                    AuthView()
                } else {
                    MainAppView()
                }
            }
            .animation(.snappy, value: session.isBootstrapping)
            .animation(.snappy, value: session.currentUser?.id)
            
            if session.isLocked {
                AppLockView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                if session.isFaceIDEnabled {
                    session.isLocked = true
                }
            } else if newPhase == .active {
                if session.isFaceIDEnabled && session.isLocked {
                    session.authenticateLock()
                }
            }
        }
    }
}

private struct AppLockView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 78, weight: .semibold))
                    .foregroundStyle(Color.loopGreen)

                VStack(spacing: 8) {
                    Text("Loop is Locked")
                        .font(LoopFont.display(26, weight: .black))
                        .foregroundStyle(Color.loopInk)

                    Text("Use biometrics or your passcode to access the app.")
                        .font(LoopFont.body(15))
                        .foregroundStyle(Color.loopSubtext)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)

                Spacer()

                Button {
                    session.authenticateLock()
                } label: {
                    Label("Unlock with Passcode / FaceID", systemImage: "faceid")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.loopGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            session.authenticateLock()
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.loopInk, .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Loop")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(Color.loopGreen)

                ProgressView()
                    .tint(Color.loopGreen)
            }
        }
    }
}
