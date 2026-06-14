import SwiftUI

struct CommentsSheet: View {
    @EnvironmentObject private var session: SessionStore
    let loop: LoopClip
    let onLoopUpdated: (LoopClip) -> Void

    @State private var comments: [LoopComment] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .tint(.loopGreen)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if comments.isEmpty {
                    ContentUnavailableView(
                        "No comments yet",
                        systemImage: "bubble.left",
                        description: Text("Start the conversation on this loop.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(comments) { comment in
                        HStack(alignment: .top, spacing: 12) {
                            AvatarView(user: comment.author, size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(comment.author.username)")
                                    .font(.subheadline.weight(.black))
                                Text(comment.body)
                                    .font(.body)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollDismissesKeyboard(.interactively)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.loopWarm)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                composer
            }
            .navigationTitle("\(loop.commentCount.compactCount) comments")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await loadComments()
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Add a comment", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            Button {
                Task { await postComment() }
            } label: {
                Image(systemName: isPosting ? "hourglass" : "arrow.up.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.loopGreen)
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
        }
        .padding()
        .background(.background)
    }

    private func loadComments() async {
        guard let token = try? session.requireToken() else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            comments = try await session.apiClient.comments(loopID: loop.id, token: token).comments
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func postComment() async {
        guard let token = try? session.requireToken() else {
            return
        }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return
        }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        do {
            let response = try await session.apiClient.addComment(loopID: loop.id, body: body, token: token)
            comments.append(response.comment)
            onLoopUpdated(response.loop)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
