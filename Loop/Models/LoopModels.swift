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
