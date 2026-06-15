import SwiftUI

struct ExploreView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var query = ""
    @State private var users: [LoopUser] = []
    @State private var hashtags: [TrendingHashtag] = []
    @State private var loops: [LoopClip] = []
    @State private var selectedUser: LoopUser?
    @State private var selectedLoop: LoopClip?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Categories
    private let categories = [
        ("Vlog", "video.circle.fill"),
        ("Tech", "cpu.fill"),
        ("Comedy", "face.smiling.fill"),
        ("Music", "music.note"),
        ("Art", "paintpalette.fill"),
        ("Food", "fork.knife"),
        ("Sports", "sportscourt.fill"),
        ("Travel", "airplane")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.loopPanel.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        searchField
                        
                        if query.isEmpty {
                            trendingCategoriesGrid
                        }
                        
                        hashtagSection
                        peopleSection
                        loopsSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.loopWarm)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .overlay {
                    if isLoading {
                        ProgressView()
                            .tint(Color.loopGreen)
                    }
                }
            }
        }
        .task {
            await loadDiscover()
        }
        .onChange(of: query) {
            Task { await searchOrDiscover() }
        }
        .sheet(item: $selectedUser) { user in
            UserProfileSheet(user: user)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLoop) { loop in
            LoopDetailView(loop: loop)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Discover")
                .font(LoopFont.logo(36))
                .foregroundStyle(.loopInk)
            Text("People, tags, and loops moving right now.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.loopSubtext)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.loopSubtext)
            TextField("Search creators, #tags, captions", text: $query)
                .textInputAutocapitalization(.never)
                .foregroundStyle(.loopInk)
                .submitLabel(.search)
        }
        .loopField()
    }

    private var hashtagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Trending")
            if hashtags.isEmpty {
                emptyLine("Hashtags appear as people post loops.")
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(hashtags) { item in
                            Button {
                                query = "#\(item.tag)"
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("#\(item.tag)")
                                        .font(.system(size: 15, weight: .black))
                                        .foregroundStyle(.loopInk)
                                    Text("\(item.count) loops")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.loopSubtext)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 11)
                                .loopCard(radius: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(query.isEmpty ? "Creators" : "People")
            if users.isEmpty {
                emptyLine("No people found.")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(users.prefix(8)) { user in
                        UserRow(user: user) {
                            selectedUser = user
                        } onFollow: {
                            await toggleFollow(user)
                        }
                    }
                }
            }
        }
    }

    private var loopsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(query.isEmpty ? "Fresh loops" : "Loop results")
            if loops.isEmpty {
                emptyLine("No loops found.")
            } else {
                LazyVStack(spacing: 9) {
                    ForEach(loops.prefix(12)) { loop in
                        Button {
                            selectedLoop = loop
                        } label: {
                            LoopSummaryRow(loop: loop)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .black))
            .foregroundStyle(.loopInk)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.loopSubtext)
            .padding(.vertical, 4)
    }

    private func searchOrDiscover() async {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await loadDiscover()
        } else {
            await search()
        }
    }

    private func loadDiscover() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.apiClient.discover(token: token)
            users = response.users.filter { $0.id != session.currentUser?.id }
            hashtags = response.hashtags
            loops = response.loops
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func search() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await session.apiClient.search(query: query, token: token)
            users = response.users.filter { $0.id != session.currentUser?.id }
            hashtags = response.hashtags
            loops = response.loops
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow(_ user: LoopUser) async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            let response = try await session.apiClient.setFollow(
                userID: user.id,
                following: user.isFollowedByViewer != true,
                token: token
            )
            if let index = users.firstIndex(where: { $0.id == user.id }) {
                users[index] = response.user
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UserRow: View {
    let user: LoopUser
    let onOpen: () -> Void
    let onFollow: () async -> Void
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 11) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    AvatarView(user: user, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(.loopInk)
                        Text("@\(user.username) · \(user.loopCount) loops")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.loopSubtext)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                Task {
                    isWorking = true
                    await onFollow()
                    isWorking = false
                }
            } label: {
                Text(user.isFollowedByViewer == true ? "Following" : "Follow")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(user.isFollowedByViewer == true ? Color.loopSubtext : Color.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(user.isFollowedByViewer == true ? Color.loopMist : Color.loopGreen, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
        }
        .padding(11)
        .loopCard(radius: 16)
    }
}

struct UserProfileSheet: View {
    @EnvironmentObject private var session: SessionStore
    @State var user: LoopUser
    @State private var loops: [LoopClip] = []
    @State private var selectedLoop: LoopClip?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ProfileHeader(user: user, isCurrentUser: user.id == session.currentUser?.id) {
                        await toggleFollow()
                    }

                    LazyVStack(spacing: 9) {
                        ForEach(loops) { loop in
                            Button {
                                selectedLoop = loop
                            } label: {
                                LoopSummaryRow(loop: loop)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if loops.isEmpty {
                        ContentUnavailableView("No loops yet", systemImage: "video")
                            .padding(.top, 20)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.loopWarm)
                    }
                }
                .padding(16)
            }
            .background(Color.loopPanel)
            .navigationTitle("@\(user.username)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await load()
        }
        .sheet(item: $selectedLoop) { loop in
            LoopDetailView(loop: loop)
                .presentationDetents([.large])
        }
    }

    private func load() async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            let response = try await session.apiClient.userLoops(userID: user.id, token: token)
            user = response.user
            loops = response.loops
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFollow() async {
        guard user.id != session.currentUser?.id,
              let token = try? session.requireToken() else {
            return
        }
        do {
            user = try await session.apiClient.setFollow(
                userID: user.id,
                following: user.isFollowedByViewer != true,
                token: token
            ).user
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileHeader: View {
    let user: LoopUser
    let isCurrentUser: Bool
    var followAction: (() async -> Void)?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 13) {
            AvatarView(user: user, size: 84)

            VStack(spacing: 3) {
                Text(user.displayName)
                    .font(.system(size: 24, weight: .black))
                Text("@\(user.username)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                if !user.bio.isEmpty {
                    Text(user.bio)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            HStack(spacing: 28) {
                StatView(value: user.loopCount, label: "Loops")
                StatView(value: user.followerCount, label: "Followers")
                StatView(value: user.followingCount, label: "Following")
            }

            if !isCurrentUser, let followAction {
                Button {
                    Task {
                        isWorking = true
                        await followAction()
                        isWorking = false
                    }
                } label: {
                    Text(user.isFollowedByViewer == true ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(user.isFollowedByViewer == true ? Color.primary : Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(user.isFollowedByViewer == true ? Color.secondary.opacity(0.14) : Color.loopGreen, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .loopCard(radius: 18)
    }
}

struct LoopSummaryRow: View {
    let loop: LoopClip

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [.loopMist, .loopGreen.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 82)

            VStack(alignment: .leading, spacing: 6) {
                Text(loop.displayCaption.isEmpty ? "Untitled loop" : loop.displayCaption)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !loop.hashtags.isEmpty {
                    Text(loop.hashtags.prefix(3).map { "#\($0)" }.joined(separator: " "))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.loopGreen)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Label(loop.likeCount.compactCount, systemImage: "heart.fill")
                    Label(loop.commentCount.compactCount, systemImage: "bubble.left.fill")
                    Label(loop.durationLabel, systemImage: "timer")
                }
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .loopCard(radius: 16)
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value.compactCount)
                .font(.system(size: 15, weight: .black))
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
}

extension ExploreView {
    var trendingCategoriesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(Color.loopInk)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(categories, id: \.0) { cat in
                    Button {
                        query = cat.0
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: cat.1)
                                .font(.system(size: 18))
                                .foregroundStyle(Color.loopGreen)
                            Text(cat.0)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.loopInk)
                            Spacer()
                        }
                        .padding(12)
                        .loopCard(radius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
