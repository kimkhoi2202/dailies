import SwiftUI

// Screens the tab bar and the Home avatar lead to before their own features land:
// the camera (Create), Messages and the profile.

/// What the Create key opens until the camera is built.
struct CreatePlaceholderScreen: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            DL.body.ignoresSafeArea()
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "camera.fill").font(.system(size: 56, weight: .semibold)).foregroundStyle(DL.ink3)
                Text("CAMERA COMING SOON").font(DL.display(38)).foregroundStyle(DL.ink).multilineTextAlignment(.center)
                Text("Soon you can film yourself playing and post it to Reels.")
                    .font(DL.text(16)).foregroundStyle(DL.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                DLTextKey(title: "Close", style: .neutral).goesBack()
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            DLIconButton(symbol: "xmark").goesBack().accessibilityLabel("Close")
                .padding(.horizontal, DL.margin).padding(.top, 6)
        }
    }
}

/// The Messages tab until chats are built.
struct MessagesTabScreen: View {
    var body: some View {
        DLPage(spacing: 18) {
            HStack(alignment: .center) {
                Text("MESSAGES").font(DL.display(44)).foregroundStyle(DL.ink)
                Spacer()
                DLGoldChip(onMedia: false).opens(.gold)
            }
            DLEmptyState(symbol: "bubble.left.and.bubble.right.fill", title: "No chats yet",
                         detail: "Talk to friends, send game invites and share your scores here.",
                         key: "Find friends") {
                LiveNav.shared.share("Come and play with me on DEGEN")
            }
        }
    }
}

/// The profile the Home avatar opens. Until the avatar room is built it shows the You screen.
struct ProfilePlaceholderScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            DLNavBar(title: "Profile")
                .padding(.horizontal, DL.margin).padding(.top, 4).padding(.bottom, 4)
            G2YouScreen()
        }
        .background(DL.body.ignoresSafeArea())
    }
}
