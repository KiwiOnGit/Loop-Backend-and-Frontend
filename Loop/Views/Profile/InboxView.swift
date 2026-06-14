import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var selectedMode: InboxMode = .messages
    @State private var conversations: [LoopConversation] = []
    @State private var notifications: [LoopNotification] = []
    @State private var selectedConversation: LoopConversation?
    @State private var showingGroupWizard = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.loopPanel.ignoresSafeArea()

                VStack(spacing: 12) {
                    Picker("Inbox", selection: $selectedMode) {
                        ForEach(InboxMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.loopWarm)
                    }

                    content
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedMode == .messages {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingGroupWizard = true
                        } label: {
                            Image(systemName: "person.2.badge.plus")
                                .foregroundStyle(Color.loopGreen)
                        }
                    }
                }
            }
        }
        .task {
            await load()
        }
        .onChange(of: selectedMode) {
            Task { await load() }
        }
        .sheet(item: $selectedConversation) { conversation in
            ConversationView(conversation: conversation)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingGroupWizard) {
            GroupChatWizardView()
                .environmentObject(session)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView()
                .tint(Color.loopGreen)
            Spacer()
        } else if selectedMode == .messages {
            messagesList
        } else {
            notificationList
        }
    }

    private var messagesList: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                ForEach(conversations) { conversation in
                    Button {
                        selectedConversation = conversation
                    } label: {
                        ConversationRow(conversation: conversation, currentUserID: session.currentUser?.id)
                    }
                    .buttonStyle(.plain)
                }

                if conversations.isEmpty {
                    emptyState("No messages yet", "Send a loop from the feed to start a conversation.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var notificationList: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                ForEach(notifications) { notification in
                    NotificationRow(notification: notification)
                }

                if notifications.isEmpty {
                    emptyState("No activity yet", "Likes, comments, follows, mentions, and messages will appear here.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.loopGreen)
            Text(title)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.loopInk)
            Text(subtitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.loopSubtext)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .loopCard(radius: 18)
        .padding(.top, 18)
    }

    private func load() async {
        guard let token = try? session.requireToken() else {
            return
        }
        await LoopNotificationService.requestAuthorization()
        isLoading = true
        defer { isLoading = false }
        do {
            conversations = try await session.apiClient.conversations(token: token).conversations
            notifications = try await session.apiClient.notifications(token: token).notifications
            notifications.prefix(3).forEach { LoopNotificationService.publish($0) }
            _ = try? await session.apiClient.markNotificationsRead(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum InboxMode: String, CaseIterable, Identifiable {
    case messages
    case activity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .messages: "Messages"
        case .activity: "Activity"
        }
    }
}

private struct ConversationRow: View {
    let conversation: LoopConversation
    let currentUserID: String?

    var body: some View {
        let user = conversation.otherParticipant(currentUserID: currentUserID)
        HStack(spacing: 11) {
            if let user {
                AvatarView(user: user, size: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user?.displayName ?? "Conversation")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.loopInk)

                Text(preview)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.loopSubtext)
                    .lineLimit(1)
            }

            Spacer()

            if conversation.unreadCount > 0 {
                Text(conversation.unreadCount.compactCount)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.loopGreen, in: Capsule())
            }
        }
        .padding(12)
        .loopCard(radius: 16)
    }

    private var preview: String {
        guard let message = conversation.lastMessage else {
            return "No messages yet"
        }
        if let loop = message.loop {
            return message.body.isEmpty ? "Sent a loop: \(loop.caption)" : message.body
        }
        return message.body
    }
}

private struct NotificationRow: View {
    let notification: LoopNotification

    var body: some View {
        HStack(spacing: 11) {
            if let actor = notification.actor {
                AvatarView(user: actor, size: 42)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.loopInk)
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.loopSubtext)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: icon)
                .foregroundStyle(.loopGreen)
        }
        .padding(12)
        .background(notification.readAt == nil ? Color.loopMist : Color.loopSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.loopLine, lineWidth: 1)
        }
    }

    private var title: String {
        let name = notification.actor?.displayName ?? "Someone"
        return switch notification.type {
        case "like": "\(name) liked your loop"
        case "comment": "\(name) commented"
        case "follow": "\(name) followed you"
        case "mention": "\(name) mentioned you"
        case "message": "\(name) sent a message"
        default: "New activity"
        }
    }

    private var icon: String {
        switch notification.type {
        case "like": "heart.fill"
        case "comment": "bubble.left.fill"
        case "follow": "person.crop.circle.badge.plus"
        case "mention": "at"
        case "message": "paperplane.fill"
        default: "bell.fill"
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var session: SessionStore
    let conversation: LoopConversation
    @State private var messages: [LoopMessage] = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message, isMine: message.sender.id == session.currentUser?.id)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.loopWarm)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                HStack(spacing: 10) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .loopField()

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.loopGreen)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(12)
                .background(.background)
            }
            .navigationTitle(conversation.otherParticipant(currentUserID: session.currentUser?.id)?.displayName ?? "Message")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await load()
        }
    }

    private func load() async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            messages = try await session.apiClient.messages(conversationID: conversation.id, token: token).messages
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        guard let token = try? session.requireToken() else {
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let response = try await session.apiClient.sendMessage(conversationID: conversation.id, body: text, token: token)
            messages.append(response.message)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: LoopMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 42) }

            VStack(alignment: .leading, spacing: 7) {
                if let loop = message.loop {
                    LoopSummaryRow(loop: loop)
                        .frame(maxWidth: 260)
                }
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(10)
            .foregroundStyle(isMine ? .black : .primary)
            .background(isMine ? Color.loopGreen : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !isMine { Spacer(minLength: 42) }
        }
    }
}

private struct GroupChatWizardView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var selectedUsers: Set<String> = []
    @State private var query = ""
    @State private var users: [LoopUser] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("Group Name", text: $groupName)
                    .loopField()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                TextField("Search creators to invite...", text: $query)
                    .loopField()
                    .padding(.horizontal, 16)
                
                List(users) { user in
                    HStack(spacing: 11) {
                        AvatarView(user: user, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(.headline)
                            Text("@\(user.username)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if selectedUsers.contains(user.id) {
                                selectedUsers.remove(user.id)
                            } else {
                                selectedUsers.insert(user.id)
                            }
                        } label: {
                            Image(systemName: selectedUsers.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedUsers.contains(user.id) ? Color.loopGreen : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("New Group Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        dismiss()
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedUsers.isEmpty)
                }
            }
            .task { await search() }
            .onChange(of: query) {
                Task { await search() }
            }
        }
    }
    
    private func search() async {
        guard let token = try? session.requireToken() else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await session.apiClient.search(query: query, token: token).users
                .filter { $0.id != session.currentUser?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
