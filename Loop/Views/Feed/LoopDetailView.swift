import SwiftUI

struct LoopDetailView: View {
    let loop: LoopClip
    @State private var isPaused = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            LoopPlayerView(url: loop.videoURL, isActive: !isPaused)
                .ignoresSafeArea()

            LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            if isPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.42), in: Circle())
            }

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        AvatarView(user: loop.creator, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(loop.creator.displayName)
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                            Text("@\(loop.creator.username)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }

                    Text(loop.displayCaption.isEmpty ? "Untitled loop" : loop.displayCaption)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)

                    HStack(spacing: 12) {
                        Label(loop.likeCount.compactCount, systemImage: "heart.fill")
                        Label(loop.commentCount.compactCount, systemImage: "bubble.left.fill")
                        Label(loop.durationLabel, systemImage: "timer")
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.18)) {
                isPaused.toggle()
            }
        }
    }
}
