import SwiftUI
import UIKit

struct FeedView: View {
    @EnvironmentObject private var session: SessionStore
    let onCreateFromRemix: (String) -> Void

    @State private var scope: FeedScope = .forYou
    @State private var loops: [LoopClip] = []
    @State private var activeLoopID: LoopClip.ID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedComments: LoopClip?
    @State private var selectedSendLoop: LoopClip?
    @State private var selectedRemixLoop: LoopClip?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                if loops.isEmpty {
                    EmptyFeedView(isLoading: isLoading, message: errorMessage) {
                        Task { await loadFeed() }
                    }
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach($loops) { $loop in
                                LoopClipCard(
                                    loop: $loop,
                                    isActive: activeLoopID == loop.id,
                                    onOpenComments: { selectedComments = loop },
                                    onSend: { selectedSendLoop = loop },
                                    onRemix: { selectedRemixLoop = loop },
                                    onToggleLike: { liked in
                                        await toggleLike(loopID: loop.id, liked: liked)
                                    },
                                    onToggleFollow: { following in
                                        await toggleFollow(userID: loop.creator.id, following: following)
                                    }
                                )
                                .id(loop.id)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollPosition(id: $activeLoopID)
                    .scrollTargetBehavior(.paging)
                    .scrollDismissesKeyboard(.interactively)
                    .background(.black)
                    .ignoresSafeArea()
                    .refreshable {
                        await loadFeed()
                    }
                }

                FeedHeader(scope: $scope)
                    .padding(.horizontal, 16)
                    .padding(.top, 54) // Keep header below safe area notch
            }
            .background(loops.isEmpty ? Color.loopPanel : Color.black)
        }
        .ignoresSafeArea()
        .task {
            await loadFeed()
        }
        .onChange(of: scope) {
            Task { await loadFeed() }
        }
        .onChange(of: loops.map(\.id)) { _, ids in
            if activeLoopID == nil || !ids.contains(activeLoopID ?? "") {
                activeLoopID = ids.first
            }
        }
        .sheet(item: $selectedComments) { loop in
            CommentsSheet(loop: loop) { updatedLoop in
                if let index = loops.firstIndex(where: { $0.id == updatedLoop.id }) {
                    loops[index] = updatedLoop
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedSendLoop) { loop in
            SendLoopSheet(loop: loop)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedRemixLoop) { loop in
            RemixLoopSheet(loop: loop) { draft in
                selectedRemixLoop = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    onCreateFromRemix(draft)
                }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private func loadFeed() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            loops = try await session.apiClient.feed(scope: scope, token: token).loops
            activeLoopID = loops.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(loopID: String, liked: Bool) async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            let response = try await session.apiClient.setLike(loopID: loopID, liked: liked, token: token)
            if let index = loops.firstIndex(where: { $0.id == loopID }) {
                loops[index] = response.loop
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow(userID: String, following: Bool) async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            let response = try await session.apiClient.setFollow(userID: userID, following: following, token: token)
            for index in loops.indices where loops[index].creator.id == userID {
                loops[index].creator = response.user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct FeedHeader: View {
    @Binding var scope: FeedScope

    var body: some View {
        HStack(spacing: 12) {
            Text("Loop")
                .font(LoopFont.logo(30))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)

            HStack(spacing: 4) {
                ForEach(FeedScope.allCases) { item in
                    Button {
                        scope = item
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(scope == item ? .white : .white.opacity(0.74))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(scope == item ? Color.loopGreen : Color.black.opacity(0.32), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
    }
}

private struct EmptyFeedView: View {
    let isLoading: Bool
    let message: String?
    let reload: () -> Void

    var body: some View {
        ZStack {
            Color.loopPanel
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "play.rectangle.stack.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.loopGreen)

                Text(isLoading ? "Loading" : "No loops yet")
                    .font(LoopFont.display(24))
                    .foregroundStyle(.loopInk)

                Text(message ?? "Post a loop or discover creators.")
                    .font(LoopFont.body(14))
                    .foregroundStyle(.loopSubtext)

                Button(action: reload) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.loopGreen, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
        }
    }
}

private struct LoopClipCard: View {
    @Binding var loop: LoopClip
    let isActive: Bool
    let onOpenComments: () -> Void
    let onSend: () -> Void
    let onRemix: () -> Void
    let onToggleLike: (Bool) async -> Void
    let onToggleFollow: (Bool) async -> Void

    @State private var manualPaused = false
    @State private var isLiking = false
    @State private var isFollowing = false
    @State private var isCellVisible = false

    var body: some View {
        ZStack {
            LoopPlayerView(url: loop.videoURL, isActive: isActive && isCellVisible && !manualPaused)

            LinearGradient(
                colors: [.black.opacity(0.20), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            if isActive && manualPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.42), in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                Spacer()

                HStack(alignment: .bottom, spacing: 10) {
                    captionBlock
                        .frame(maxWidth: .infinity, alignment: .leading)

                    actionRail
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 94) // Shift up to clear the TabView tab bar
            }

            VStack {
                HStack {
                    Spacer()
                    GlassPill {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .foregroundStyle(Color.loopGreen)
                            Text("0:06")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 102) // Shift down to clear the notch and top feed header
                .padding(.horizontal, 15)

                Spacer()
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            guard isActive else {
                return
            }
            withAnimation(.snappy(duration: 0.18)) {
                manualPaused.toggle()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                manualPaused = false
            }
        }
        .onAppear {
            isCellVisible = true
        }
        .onDisappear {
            isCellVisible = false
        }
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(user: loop.creator, size: 30)

                VStack(alignment: .leading, spacing: 0) {
                    Text("@\(loop.creator.username)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                    if !loop.creator.bio.isEmpty {
                        Text(loop.creator.bio)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.66))
                            .lineLimit(1)
                    }
                }

                if loop.creator.isFollowedByViewer != true {
                    Button {
                        Task {
                            isFollowing = true
                            await onToggleFollow(true)
                            isFollowing = false
                        }
                    } label: {
                        Text(isFollowing ? "..." : "Follow")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.loopGreen, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isFollowing)
                }
            }

            CaptionText(caption: loop.caption)

            if !loop.hashtags.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(loop.hashtags.prefix(5), id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(.loopGreen)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.42), in: Capsule())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if !loop.commentsPreview.isEmpty {
                Button(action: onOpenComments) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(loop.commentCount.compactCount) comments")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(.white.opacity(0.82))

                        ForEach(loop.commentsPreview.prefix(2)) { comment in
                            HStack(spacing: 5) {
                                Text(comment.author.username)
                                    .fontWeight(.black)
                                Text(comment.body)
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.84))
                            .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .shadow(color: .black.opacity(0.55), radius: 5, y: 2)
    }

    private var actionRail: some View {
        VStack(spacing: 14) {
            AvatarView(user: loop.creator, size: 44)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: loop.creator.isFollowedByViewer == true ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.loopGreen)
                        .background(.black, in: Circle())
                }

            ActionButton(
                symbol: loop.didLike ? "heart.fill" : "heart",
                value: loop.likeCount.compactCount,
                active: loop.didLike
            ) {
                Task { await like() }
            }
            .disabled(isLiking)

            ActionButton(symbol: "bubble.left.fill", value: loop.commentCount.compactCount, active: false, action: onOpenComments)
            ActionButton(symbol: "paperplane.fill", value: "Send", active: false, action: onSend)

            ActionButton(symbol: "arrow.triangle.2.circlepath", value: "Remix", active: true, action: onRemix)
        }
        .padding(.bottom, 14)
    }

    private func like() async {
        guard !isLiking else {
            return
        }
        isLiking = true
        await onToggleLike(!loop.didLike)
        isLiking = false
    }
}

private struct CaptionText: View {
    let caption: String

    var body: some View {
        Text(caption.isEmpty ? "Untitled loop" : caption)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(3)
            .textSelection(.disabled)
    }
}

private struct ActionButton: View {
    let symbol: String
    let value: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(active ? Color.loopGreen : Color.white)

                Text(value)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 46)
            .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SendLoopSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    let loop: LoopClip

    @State private var query = ""
    @State private var users: [LoopUser] = []
    @State private var note = ""
    @State private var isLoading = false
    @State private var sendingUserID: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Search people", text: $query)
                    .textInputAutocapitalization(.never)
                    .loopField()
                    .padding(.horizontal, 16)

                TextField("Add a message", text: $note)
                    .loopField()
                    .padding(.horizontal, 16)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.loopWarm)
                        .padding(.horizontal, 16)
                }

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
                            Task { await send(to: user) }
                        } label: {
                            Text(sendingUserID == user.id ? "Sending" : "Send")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.loopGreen, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(sendingUserID != nil)
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .overlay {
                    if isLoading {
                        ProgressView().tint(.loopGreen)
                    }
                }
            }
            .navigationTitle("Send loop")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await search() }
        .onChange(of: query) {
            Task { await search() }
        }
    }

    private func search() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            users = try await session.apiClient.search(query: query, token: token).users
                .filter { $0.id != session.currentUser?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send(to user: LoopUser) async {
        guard let token = try? session.requireToken() else {
            return
        }
        sendingUserID = user.id
        defer { sendingUserID = nil }
        do {
            let conversation = try await session.apiClient.startConversation(userID: user.id, token: token).conversation
            _ = try await session.apiClient.sendMessage(
                conversationID: conversation.id,
                body: note.trimmingCharacters(in: .whitespacesAndNewlines),
                loopID: loop.id,
                token: token
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RemixLoopSheet: View {
    @Environment(\.dismiss) private var dismiss
    let loop: LoopClip
    let onCreateDraft: (String) -> Void

    private var remixDraft: String {
        let baseCaption = loop.caption.isEmpty ? "this loop" : loop.caption
        return "Remix @\(loop.creator.username): \(baseCaption)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                LoopSummaryRow(loop: loop)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Remix angle")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.loopSubtext)

                    ForEach(remixIdeas, id: \.self) { idea in
                        Button {
                            onCreateDraft(idea)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.loopGreen)
                                Text(idea)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.loopInk)
                                    .lineLimit(2)
                                Spacer()
                                Image(systemName: "camera.fill")
                                    .font(.caption.weight(.black))
                                    .foregroundStyle(.loopSubtext)
                            }
                            .padding(12)
                            .loopCard(radius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = remixDraft
                    } label: {
                        Label("Copy setup", systemImage: "doc.on.doc.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.loopGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .loopCard(radius: 13)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onCreateDraft(remixDraft)
                        dismiss()
                    } label: {
                        Label("Record remix", systemImage: "camera.fill")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(.loopGreen, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.loopPanel.ignoresSafeArea())
            .navigationTitle("Remix")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var remixIdeas: [String] {
        [
            "Reply to @\(loop.creator.username) in one take",
            "Recreate the format with a new ending",
            "Add a faster, funnier version in 6 seconds"
        ]
    }
}
