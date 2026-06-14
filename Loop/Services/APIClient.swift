import Foundation

enum APIError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Check the server URL."
        case .invalidResponse:
            "Loop received an unexpected server response."
        case .server(let message):
            message
        }
    }
}

final class APIClient {
    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func signUp(email: String, username: String, password: String) async throws -> AuthResponse {
        try await request(
            "/api/auth/signup",
            method: "POST",
            json: ["email": email, "username": username, "password": password],
            token: nil
        )
    }

    func login(emailOrUsername: String, password: String) async throws -> AuthResponse {
        try await request(
            "/api/auth/login",
            method: "POST",
            json: ["email": emailOrUsername, "password": password],
            token: nil
        )
    }

    func me(token: String) async throws -> MeResponse {
        try await request("/api/me", token: token)
    }

    func updateProfile(displayName: String, bio: String, token: String) async throws -> UserResponse {
        try await request(
            "/api/me",
            method: "PATCH",
            json: ["displayName": displayName, "bio": bio],
            token: token
        )
    }

    func uploadAvatar(imageData: Data, fileName: String, token: String) async throws -> UserResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartFile(
            name: "avatar",
            filename: fileName,
            contentType: "image/jpeg",
            data: imageData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await request(
            "/api/me/avatar",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            token: token
        )
    }

    func feed(scope: FeedScope, token: String) async throws -> FeedResponse {
        try await request("/api/feed?scope=\(scope.rawValue)", token: token)
    }

    func discover(token: String) async throws -> DiscoverResponse {
        try await request("/api/discover", token: token)
    }

    func search(query: String, token: String) async throws -> SearchResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await request("/api/search?q=\(encoded)", token: token)
    }

    func userLoops(userID: String, token: String) async throws -> UserLoopsResponse {
        try await request("/api/users/\(userID)/loops", token: token)
    }

    func setLike(loopID: String, liked: Bool, token: String) async throws -> LoopResponse {
        try await request("/api/loops/\(loopID)/like", method: liked ? "POST" : "DELETE", token: token)
    }

    func comments(loopID: String, token: String) async throws -> CommentsResponse {
        try await request("/api/loops/\(loopID)/comments", token: token)
    }

    func addComment(loopID: String, body: String, token: String) async throws -> CommentCreateResponse {
        try await request(
            "/api/loops/\(loopID)/comments",
            method: "POST",
            json: ["body": body],
            token: token
        )
    }

    func setFollow(userID: String, following: Bool, token: String) async throws -> UserResponse {
        try await request("/api/users/\(userID)/follow", method: following ? "POST" : "DELETE", token: token)
    }

    func notifications(token: String) async throws -> NotificationsResponse {
        try await request("/api/notifications", token: token)
    }

    func markNotificationsRead(token: String) async throws -> EmptyResponse {
        try await request("/api/notifications/read", method: "POST", token: token)
    }

    func conversations(token: String) async throws -> ConversationsResponse {
        try await request("/api/conversations", token: token)
    }

    func startConversation(userID: String, token: String) async throws -> ConversationResponse {
        try await request("/api/conversations", method: "POST", json: ["userId": userID], token: token)
    }

    func messages(conversationID: String, token: String) async throws -> MessagesResponse {
        try await request("/api/conversations/\(conversationID)/messages", token: token)
    }

    func sendMessage(conversationID: String, body: String, loopID: String? = nil, token: String) async throws -> MessageCreateResponse {
        if let loopID {
            return try await request(
                "/api/conversations/\(conversationID)/messages",
                method: "POST",
                json: ["body": body, "loopId": loopID],
                token: token
            )
        }
        return try await request(
            "/api/conversations/\(conversationID)/messages",
            method: "POST",
            json: ["body": body],
            token: token
        )
    }

    func uploadLoop(videoURL: URL, caption: String, durationSeconds: Double, token: String) async throws -> LoopResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "caption", value: caption, boundary: boundary)
        body.appendMultipartField(name: "durationSeconds", value: String(format: "%.3f", durationSeconds), boundary: boundary)
        let videoData = try Data(contentsOf: videoURL)
        body.appendMultipartFile(
            name: "video",
            filename: videoURL.lastPathComponent.isEmpty ? "loop.mov" : videoURL.lastPathComponent,
            contentType: "video/quicktime",
            data: videoData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return try await request(
            "/api/loops",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            token: token
        )
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        json: [String: String]? = nil,
        token: String?
    ) async throws -> T {
        let body = try json.map { try JSONEncoder().encode($0) }
        return try await request(path, method: method, body: body, contentType: "application/json", token: token)
    }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil,
        token: String?
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            if let errorPayload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data),
               let message = errorPayload.error {
                throw APIError.server(message)
            }
            throw APIError.server("Server returned HTTP \(httpResponse.statusCode).")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

private struct ServerErrorPayload: Decodable {
    let error: String?
}

struct EmptyResponse: Codable {
    let ok: Bool?
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, filename: String, contentType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
