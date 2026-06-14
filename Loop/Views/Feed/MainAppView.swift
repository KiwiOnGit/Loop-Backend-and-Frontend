import SwiftUI

struct MainAppView: View {
    @State private var selectedTab: AppTab = .home
    @State private var remixDraftCaption = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView { caption in
                remixDraftCaption = caption
                selectedTab = .create
            }
            .tag(AppTab.home)
            .tabItem {
                Label(AppTab.home.title, systemImage: AppTab.home.symbol)
            }

            ExploreView()
                .tag(AppTab.explore)
                .tabItem {
                    Label(AppTab.explore.title, systemImage: AppTab.explore.symbol)
                }

            CreateLoopView(draftCaption: $remixDraftCaption) {
                selectedTab = .home
            }
            .tag(AppTab.create)
            .tabItem {
                Label(AppTab.create.title, systemImage: AppTab.create.symbol)
            }

            InboxView()
                .tag(AppTab.inbox)
                .tabItem {
                    Label(AppTab.inbox.title, systemImage: AppTab.inbox.symbol)
                }

            ProfileView()
                .tag(AppTab.profile)
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.symbol)
                }
        }
        .tint(.loopGreen)
        .background(.loopPanel)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case explore
    case create
    case inbox
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .explore: "Discover"
        case .create: "Create"
        case .inbox: "Inbox"
        case .profile: "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .explore: "magnifyingglass"
        case .create: "plus.circle.fill"
        case .inbox: "bubble.left.and.bubble.right.fill"
        case .profile: "person.crop.circle"
        }
    }
}
