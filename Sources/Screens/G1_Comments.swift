import SwiftUI

// COMMENTS, a sheet over the video. It is kept small: a one line header, a like and a dislike under
// each comment, and a tick beside the name of whoever posted the clip.

struct G1Comment: Identifiable {
    let id: String
    let name: String
    let time: String
    let text: String
    let likes: String
    var isClipOwner: Bool = false
    var isReply: Bool = false
    var liked: Bool = false
}

enum G1CommentsData {
    static let clip = Mock.clips[0]
    static let comments: [G1Comment] = [
        G1Comment(id: "k1", name: "kaz", time: "2h", text: "the slab at 0:31 had no business landing like that", likes: "214", liked: true),
        G1Comment(id: "k2", name: "devon.plays", time: "2h", text: "I looked away for that one", likes: "133", isClipOwner: true, isReply: true),
        G1Comment(id: "k3", name: "noor.runs", time: "1h", text: "held my breath for the whole last ten seconds", likes: "96"),
        G1Comment(id: "k4", name: "wordnerd.sam", time: "47m", text: "tried it straight after. 14 floors", likes: "61"),
        G1Comment(id: "k5", name: "tofu", time: "12m", text: "ok fine, playing it now", likes: "17"),
    ]
}

struct G1CommentRow: View {
    let comment: G1Comment
    @ObservedObject private var live = LiveStore.shared

    /// In the app a like is whatever the player has tapped. In a screenshot it is part of the story.
    private var isLiked: Bool {
        LiveMode.on ? live.s.likedComments.contains(comment.id) : comment.liked
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DLAvatar(name: comment.name, size: comment.isReply ? 26 : 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    author
                    Text(comment.time).font(DL.text(13)).foregroundStyle(DL.ink3)
                }
                .frame(height: 22)
                Text(comment.text)
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        Text(comment.likes).monospacedDigit()
                    }
                    .foregroundStyle(isLiked && LiveMode.on ? DL.ink : DL.ink2)
                    .tap(toggleLike)
                    Image(systemName: "hand.thumbsdown")
                    Text("Reply").fontWeight(.semibold)
                }
                .font(DL.text(13))
                .foregroundStyle(DL.ink2)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A reply steps in under the comment it answers.
        .padding(.leading, comment.isReply ? 46 : 0)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var author: some View {
        if comment.isClipOwner {
            // Whoever posted the clip gets their name on an ink pill, with a tick.
            HStack(spacing: 4) {
                Text("@\(comment.name)").font(DL.text(13, .semibold))
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12))
            }
            .foregroundStyle(DL.onInk)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(DL.ink))
        } else {
            Text("@\(comment.name)").font(DL.text(13, .semibold)).foregroundStyle(DL.ink2)
        }
    }

    private func toggleLike() {
        guard LiveNav.shared.hasAccount(to: "like comments") else { return }
        var liked = live.s.likedComments
        if let index = liked.firstIndex(of: comment.id) {
            liked.remove(at: index)
        } else {
            liked.append(comment.id)
        }
        live.s.likedComments = liked
    }
}

/// Where a comment is written. It stays at the bottom of the sheet.
struct G1CommentField: View {
    var body: some View {
        HStack(spacing: 10) {
            DLAvatar(name: Mock.handle, size: 36)
            HStack(spacing: 8) {
                Text("Add a comment").font(DL.text(15)).foregroundStyle(DL.ink3)
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DL.ink3)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DL.sunken))
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .frame(height: 44)
            .background(Capsule().fill(DL.body))
        }
    }
}

struct G1CommentsScreen: View {
    var clip: MockClip = Mock.clips[0]

    var body: some View {
        DLSheet(height: 560) {
            FeedScreen()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Comments").font(DL.text(17, .semibold)).foregroundStyle(DL.ink)
                    Text(G1CommentsData.clip.comments).font(DL.text(17)).foregroundStyle(DL.ink2)
                    Spacer()
                    DLIconButton(symbol: "xmark", size: 32)
                }
                .padding(.horizontal, 20)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(G1CommentsData.comments) { comment in
                        G1CommentRow(comment: comment)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
                DL.line.frame(height: 1)
                G1CommentField()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
            }
        }
    }
}
