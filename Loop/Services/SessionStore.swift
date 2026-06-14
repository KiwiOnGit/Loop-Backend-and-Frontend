import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @AppStorage("isFaceIDEnabled") var isFaceIDEnabled = false
    @Published var isLocked = false
    @Published var currentUser: LoopUser?
    @Published var isBootstrapping = true
    @Published var authError: String?
    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
            updateClientBaseURL()
        }
    }

    let apiClient: APIClient
    private(set) var token: String?

    private static let tokenAccount = "loop-token"
    private static let serverURLKey = "LoopServerURL"

    init() {
        var savedURL = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? "https://loop-backend-and-frontend.onrender.com"
        if savedURL == "http://127.0.0.1:4000" || savedURL == "http://localhost:4000" || savedURL.contains("cloudinary.com") {
            savedURL = "https://loop-backend-and-frontend.onrender.com"
            UserDefaults.standard.set(savedURL, forKey: Self.serverURLKey)
        }
        serverURLString = savedURL
        apiClient = APIClient(baseURL: URL(string: savedURL) ?? URL(string: "https://loop-backend-and-frontend.onrender.com")!)
        token = KeychainStore.read(account: Self.tokenAccount)
        
        // If FaceID is enabled, start in locked state
        if UserDefaults.standard.bool(forKey: "isFaceIDEnabled") {
            isLocked = true
        }
    }

    func bootstrap() async {
        defer { isBootstrapping = false }
        
        // Fetch server URL dynamically from Cloudinary to resolve dynamic tunnels/server IP changes
        if let url = URL(string: "https://res.cloudinary.com/dvfindvne/raw/upload/loop_server_url.txt?t=\(Int(Date().timeIntervalSince1970))") {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let urlString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !urlString.isEmpty,
                   urlString.starts(with: "http://") || urlString.starts(with: "https://") {
                    serverURLString = urlString
                    print("[Loop] Dynamically resolved server URL from Cloudinary: \(urlString)")
                }
            } catch {
                print("[Loop] Warning: Could not resolve dynamic server URL from Cloudinary: \(error.localizedDescription)")
            }
        }
        
        updateClientBaseURL()
        guard let token else {
            return
        }
        do {
            currentUser = try await apiClient.me(token: token).user
        } catch {
            logout()
        }
    }

    func signUp(email: String, username: String, password: String) async {
        await authenticate {
            try await apiClient.signUp(email: email, username: username, password: password)
        }
    }

    func login(emailOrUsername: String, password: String) async {
        await authenticate {
            try await apiClient.login(emailOrUsername: emailOrUsername, password: password)
        }
    }

    func refreshMe() async {
        guard let token else {
            return
        }
        do {
            currentUser = try await apiClient.me(token: token).user
        } catch {
            authError = error.localizedDescription
        }
    }

    func logout() {
        token = nil
        currentUser = nil
        KeychainStore.delete(account: Self.tokenAccount)
    }

    func requireToken() throws -> String {
        guard let token else {
            throw APIError.server("Sign in again to continue.")
        }
        return token
    }

    func saveServerURL() {
        UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
        updateClientBaseURL()
    }

    private func authenticate(_ operation: () async throws -> AuthResponse) async {
        authError = nil
        updateClientBaseURL()
        do {
            let response = try await operation()
            token = response.token
            currentUser = response.user
            KeychainStore.save(response.token, account: Self.tokenAccount)
        } catch {
            authError = error.localizedDescription
        }
    }

    private func updateClientBaseURL() {
        var value = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") {
            value = "http://\(value)"
        }
        if let url = URL(string: value) {
            apiClient.baseURL = url
        }
    }

    func authenticateLock() {
        guard isFaceIDEnabled else {
            isLocked = false
            return
        }
        let context = LAContext()
        var error: NSError?
        
        // Use deviceOwnerAuthentication to support FaceID, TouchID, or passcode fallback
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Loop") { success, evalError in
                Task { @MainActor in
                    if success {
                        self.isLocked = false
                    }
                }
            }
        } else {
            self.isLocked = false
        }
    }
}
