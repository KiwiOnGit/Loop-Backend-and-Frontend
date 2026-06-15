import Foundation

struct LoopUser: Codable, Identifiable, Equatable {
    let id: String
    let username: String
    var displayName: String
    var bio: String
    let avatarColor: String
    let avatarURL: URL?
    let createdAt: String
    let followerCount: Int
    let followingCount: Int
    let loopCount: Int
    var isFollowedByViewer: Bool?
}

struct LoopClip: Codable, Identifiable, Equatable {
    let id: String
    let caption: String
    let durationSeconds: Double
    let category: String?
    let videoURL: URL
    let thumbnailURL: URL?
    let createdAt: String
    var creator: LoopUser
    var likeCount: Int
    var commentCount: Int
    var didLike: Bool
    var hashtags: [String]
    var mentions: [String]
    var commentsPreview: [LoopComment]
    let source: LoopClipSource?
    let sponsorName: String?
    let provider: String?
    let disclosure: String?
    let callToActionURL: URL?
}

enum LoopClipSource: String, Codable, Equatable {
    case ugc
    case vine
    case ad
}

extension LoopClip {
    var clipSource: LoopClipSource {
        source ?? .ugc
    }

    var isUserGenerated: Bool {
        clipSource == .ugc
    }

    var isAd: Bool {
        clipSource == .ad
    }

    var isVineArchive: Bool {
        clipSource == .vine
    }

    var displayCaption: String {
        LoopCaptionFormatter.display(caption)
    }

    var durationLabel: String {
        let totalSeconds = max(0, Int(durationSeconds.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

enum LoopCaptionFormatter {
    static func display(_ rawCaption: String) -> String {
        let trimmed = rawCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        var title: String?
        var description: String?
        var hashtags: String?
        var unlabeledLines: [String] = []
        var foundGeneratedLabels = false

        for rawLine in trimmed.components(separatedBy: .newlines) {
            let line = cleanedMarkdownLine(rawLine)
            guard !line.isEmpty else {
                continue
            }

            if let labeled = labeledValue(line) {
                foundGeneratedLabels = true
                switch labeled.label {
                case "title", "caption":
                    title = strippedWrappingQuotes(labeled.value)
                case "description", "desc":
                    description = strippedWrappingQuotes(labeled.value)
                case "hashtags", "tags":
                    hashtags = labeled.value
                default:
                    unlabeledLines.append(line)
                }
            } else {
                unlabeledLines.append(line)
            }
        }

        guard foundGeneratedLabels else {
            return trimmed
        }

        if description == nil, !unlabeledLines.isEmpty {
            description = unlabeledLines.joined(separator: " ")
        }

        return [title, description, hashtags]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func cleanedMarkdownLine(_ rawLine: String) -> String {
        rawLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func labeledValue(_ line: String) -> (label: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else {
            return nil
        }
        let label = line[..<separator]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let supportedLabels = ["title", "caption", "description", "desc", "hashtags", "tags"]
        guard supportedLabels.contains(label) else {
            return nil
        }

        let valueStart = line.index(after: separator)
        let value = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (label, value)
    }

    private static func strippedWrappingQuotes(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.count >= 2 &&
            ((result.hasPrefix("\"") && result.hasSuffix("\"")) ||
             (result.hasPrefix("'") && result.hasSuffix("'"))) {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

struct LoopComment: Codable, Identifiable, Equatable {
    let id: String
    let body: String
    let createdAt: String
    let author: LoopUser
}

struct TrendingHashtag: Codable, Identifiable, Equatable {
    let tag: String
    let count: Int

    var id: String { tag }
}

struct LoopConversation: Codable, Identifiable, Equatable {
    let id: String
    let participants: [LoopUser]
    let lastMessage: LoopMessage?
    let unreadCount: Int
    let updatedAt: String
    let createdAt: String

    func otherParticipant(currentUserID: String?) -> LoopUser? {
        participants.first { $0.id != currentUserID } ?? participants.first
    }
}

struct LoopMessage: Codable, Identifiable, Equatable {
    let id: String
    let conversationId: String
    let body: String
    let createdAt: String
    let sender: LoopUser
    let loop: LoopClip?
}

struct LoopNotification: Codable, Identifiable, Equatable {
    let id: String
    let type: String
    let body: String
    let readAt: String?
    let createdAt: String
    let actor: LoopUser?
    let loop: LoopClip?
    let conversationId: String?
}

struct AuthResponse: Codable {
    let token: String
    let user: LoopUser
}

struct MeResponse: Codable {
    let user: LoopUser
}

struct FeedResponse: Codable {
    let loops: [LoopClip]
}

struct CommentsResponse: Codable {
    let comments: [LoopComment]
}

struct CommentCreateResponse: Codable {
    let comment: LoopComment
    let loop: LoopClip
}

struct LoopResponse: Codable {
    let loop: LoopClip
}

struct UserResponse: Codable {
    let user: LoopUser
}

struct UserLoopsResponse: Codable {
    let user: LoopUser
    let loops: [LoopClip]
}

struct SearchResponse: Codable {
    let users: [LoopUser]
    let hashtags: [TrendingHashtag]
    let loops: [LoopClip]
}

struct DiscoverResponse: Codable {
    let hashtags: [TrendingHashtag]
    let users: [LoopUser]
    let loops: [LoopClip]
}

struct ConversationsResponse: Codable {
    let conversations: [LoopConversation]
}

struct ConversationResponse: Codable {
    let conversation: LoopConversation
}

struct MessagesResponse: Codable {
    let messages: [LoopMessage]
}

struct MessageCreateResponse: Codable {
    let message: LoopMessage
    let conversation: LoopConversation
}

struct NotificationsResponse: Codable {
    let notifications: [LoopNotification]
}

enum FeedScope: String, CaseIterable, Identifiable {
    case forYou
    case following

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou:
            "For You"
        case .following:
            "Following"
        }
    }
}

enum FeedCategory: String, CaseIterable, Identifiable {
    case both = "both"
    case sixSeconds = "6s"
    case sixtySeconds = "60s"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .both: "All"
        case .sixSeconds: "6s Only"
        case .sixtySeconds: "60s Only"
        }
    }
}
