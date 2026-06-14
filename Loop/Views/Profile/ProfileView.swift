import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var loops: [LoopClip] = []
    @State private var selectedLoop: LoopClip?
    @State private var showingEditProfile = false
    @State private var errorMessage: String?
    
    @State private var profileTab = 0 // 0 = Posts, 1 = Bookmarks, 2 = Drafts
    
    // Mock data for Bookmarks & Drafts
    private let mockBookmarks = [
        "Inspirational Sage vlog ideas",
        "Coffee brewing in 6 seconds",
        "Cyberpunk design walkthrough",
        "Forest birds meditation loop"
    ]
    private let mockDrafts = [
        "Draft: Quick reply to @creator",
        "Draft: Forest walking session",
        "Draft: Sage cooking recipe"
    ]

    private let gridColumns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.loopPanel.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        if let user = session.currentUser {
                            ProfileHeader(user: user, isCurrentUser: true)

                            HStack(spacing: 8) {
                                Button {
                                    showingEditProfile = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Color.loopGreen, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                                .buttonStyle(.plain)

                                Button(role: .destructive) {
                                    session.logout()
                                } label: {
                                    Label("Exit", systemImage: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(Color.loopSubtext)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Color.loopMist, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Picker("Profile tabs", selection: $profileTab) {
                            Text("Posts").tag(0)
                            Text("Saved").tag(1)
                            Text("Drafts").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 4)

                        if profileTab == 0 {
                            if loops.isEmpty {
                                ContentUnavailableView("No posts yet", systemImage: "video.badge.plus")
                                    .frame(minHeight: 180)
                                    .loopCard(radius: 18)
                            } else {
                                LazyVGrid(columns: gridColumns, spacing: 3) {
                                    ForEach(loops) { loop in
                                        Button {
                                            selectedLoop = loop
                                        } label: {
                                            LoopGridTile(loop: loop)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if profileTab == 1 {
                            // Saved Bookmarks Tab
                            LazyVStack(spacing: 8) {
                                ForEach(mockBookmarks, id: \.self) { bookmark in
                                    HStack(spacing: 12) {
                                        Image(systemName: "bookmark.fill")
                                            .foregroundStyle(Color.loopGreen)
                                        Text(bookmark)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.loopInk)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Color.loopSubtext)
                                    }
                                    .padding(14)
                                    .loopCard(radius: 12)
                                }
                            }
                        } else {
                            // Drafts Tab
                            LazyVStack(spacing: 8) {
                                ForEach(mockDrafts, id: \.self) { draft in
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundStyle(Color.loopGreen)
                                        Text(draft)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(Color.loopInk)
                                        Spacer()
                                        Image(systemName: "camera.fill")
                                            .foregroundStyle(Color.loopGreen)
                                    }
                                    .padding(14)
                                    .loopCard(radius: 12)
                                }
                            }
                        }

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
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await load()
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedLoop) { loop in
            LoopDetailView(loop: loop)
                .presentationDetents([.large])
        }
    }

    private func load() async {
        guard let token = try? session.requireToken(),
              let userID = session.currentUser?.id else {
            return
        }
        do {
            let response = try await session.apiClient.userLoops(userID: userID, token: token)
            loops = response.loops
            await session.refreshMe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LoopGridTile: View {
    let loop: LoopClip

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [.loopMist, .loopGreen.opacity(0.55), .loopGreenDeep.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.26), in: Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(loop.caption.isEmpty ? "Loop" : loop.caption)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(7)
                .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
        }
        .aspectRatio(0.72, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.loopLine, lineWidth: 1)
        }
        .accessibilityLabel(loop.caption.isEmpty ? "Loop video" : loop.caption)
    }
}

private struct EditProfileSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var bio = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        if let user = session.currentUser {
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                VStack(spacing: 8) {
                                    AvatarView(user: user, size: 92)
                                    Text("Change photo")
                                        .font(.caption.weight(.black))
                                }
                            }
                        }
                        Spacer()
                    }
                }

                Section("Profile") {
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.loopWarm)
                    }
                }
            }
            .navigationTitle("Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            displayName = session.currentUser?.displayName ?? ""
            bio = session.currentUser?.bio ?? ""
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
    }

    private func save() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let response = try await session.apiClient.updateProfile(displayName: displayName, bio: bio, token: token)
            session.currentUser = response.user
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let token = try? session.requireToken() else {
            return
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.82) else {
                errorMessage = "That photo could not be loaded."
                return
            }
            let response = try await session.apiClient.uploadAvatar(imageData: jpeg, fileName: "avatar.jpg", token: token)
            session.currentUser = response.user
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
