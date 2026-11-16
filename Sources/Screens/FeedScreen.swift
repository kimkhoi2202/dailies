import SwiftUI

// VIDEOS, the feed. A clip fills the whole screen, with no app name and no balance on it.
// Down the right edge: the round gold Play key, then like, dislike, comments and share.
// Bottom left: who can play, the game's name and maker, and the clip's caption.

extension MockGame {
    /// "1 gold a min" or "0.9 gold a min". Where the full word is wanted, the caller adds "ute".
    var rateText: String {
        let isWhole = goldPerMinute.rounded() == goldPerMinute
        let rate = isWhole ? "\(Int(goldPerMinute))" : String(format: "%.1f", goldPerMinute)
        return rate + " gold a min"
    }
}

/// One clip, full screen, with everything that sits on it. The feed and the animated demos both use it.
struct VideoPage: View {
    let clip: MockClip
    var progress: CGFloat = 0.38
    /// nil = no vote yet, true = liked, false = disliked
    var voted: Bool? = nil
    /// A moving phase makes the gameplay move. nil holds the game's best still.
    var phase: Double? = nil
    var pressed: Bool = false
    /// A player's own recording, shown in place of the game's replay.
    var media: AnyView? = nil
    /// The run's score, for a player's clip.
    var tag: String? = nil
    /// The key the bookmark saves this clip under. nil shows no bookmark.
    var saveKey: String? = nil
    /// For the poster's own clip: opens its menu to edit or delete it.
    var onMore: (() -> Void)? = nil
    /// Takes the clip to a place in its length, 0 to 1, as a finger drags the line, with true as the finger lifts.
    /// nil leaves the line as a picture of the time played.
    var onSeek: ((Double, Bool) -> Void)? = nil

    private var game: MockGame { clip.game }

    var body: some View {
        ZStack {
            if let media {
                media
            } else {
                // Five Up carries its own header in its art, so it is the one clip shown without the game's HUD.
                ClipStill(game: game, phase: phase, showHUD: game.kind != .fiveUp, focusY: 0)
            }
            shade(from: .top, height: 130, strength: 0.42)
            shade(from: .bottom, height: 400, strength: 0.78)
            HStack(alignment: .bottom, spacing: 10) {
                about
                Spacer(minLength: 0)
                rail
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            // The app lifts the block a little, to keep the last button clear of the real tab bar.
            .padding(.bottom, LiveMode.on ? 118 : 108)
            .frame(maxHeight: .infinity, alignment: .bottom)
            ClipTimeline(progress: progress, onSeek: onSeek)
        }
        .environment(\.colorScheme, .dark)
    }

    /// Darkens one end of the clip so white text and buttons stay readable on any art.
    private func shade(from edge: VerticalEdge, height: CGFloat, strength: Double) -> some View {
        let dark = Color.black.opacity(strength)
        return LinearGradient(colors: edge == .top ? [dark, .clear] : [.clear, dark], startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DLMediaTag(text: game.players, symbol: "person.2.fill")
                DLMediaTag(text: game.mode)
                if let tag { DLMediaTag(text: tag, symbol: "trophy.fill") }
            }
            if game.isFullToday {
                DLMediaTag(text: "Limit reached. More gold in \(Mock.resetIn)", symbol: "checkmark")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(game.title.uppercased())
                    .font(DL.display(40))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Text("by \(game.studio)")
                        .font(DL.text(14, .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DL.gold)
                }
            }
            .opens(.gameDetail(game.id))
            Text("\(Text("@\(clip.player)").fontWeight(.semibold))  \(clip.caption)")
                .font(DL.text(15))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
    }

    private var rail: some View {
        VStack(spacing: 15) {
            VStack(spacing: 5) {
                // Once today's gold is all collected the key goes pale. It still plays.
                DLRoundPlayKey(size: 68, style: game.isFullToday ? .neutral : .gold)
                    .scaleEffect(pressed ? 0.9 : 1)
                Text("Play").font(DL.text(13, .bold)).foregroundStyle(.white)
            }
            .padding(.bottom, 4)
            .opens(.gameReady(game.id))
            .accessibilityLabel("Play \(game.title)")

            let liked = voted == true
            counted(game.likes) {
                DLMediaButton(symbol: liked ? "hand.thumbsup.fill" : "hand.thumbsup", size: 46)
                    .likeCelebration(liked)
                    .likePlusOne(liked)
            }
            .tap { LiveStore.shared.setVote(game.id, like: true) }
            .accessibilityLabel("Like")

            counted(game.dislikes) {
                DLMediaButton(symbol: voted == false ? "hand.thumbsdown.fill" : "hand.thumbsdown", size: 46)
            }
            .tap { LiveStore.shared.setVote(game.id, like: false) }
            .accessibilityLabel("Dislike")

            counted(clip.comments) { DLMediaButton(symbol: "bubble.fill", size: 46) }
                .opens(.comments(clip.id))
                .accessibilityLabel("Comments")

            counted(clip.shares) { DLMediaButton(symbol: "arrowshape.turn.up.right.fill", size: 46) }
                .tap { LiveNav.shared.share("Watch @\(clip.player) play \(game.title) on DEGEN") }
                .accessibilityLabel("Share")

            if let saveKey { ClipSaveButton(key: saveKey) }

            if let onMore {
                DLMediaButton(symbol: "ellipsis", size: 46)
                    .tap(onMore)
                    .accessibilityLabel("Edit or delete your clip")
            }
        }
        .frame(width: 72)
    }

    /// A rail button with its count underneath.
    private func counted<Icon: View>(_ count: String, @ViewBuilder button: () -> Icon) -> some View {
        VStack(spacing: 3) {
            button()
            Text(count)
                .font(DL.text(12, .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}

/// How far the clip has played: a thin line just above the tab bar. Drag a finger along it to go to any moment
/// of the clip. Under the finger the line thickens and grows a round handle.
private struct ClipTimeline: View {
    let progress: CGFloat
    let onSeek: ((Double, Bool) -> Void)?
    /// Where the finger is along the line while it drags. It clears itself when the drag ends or is taken away.
    @GestureState private var held: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = min(1, max(0, held ?? progress))
            Rectangle()
                .fill(.white.opacity(held == nil ? 0.22 : 0.4))
                .overlay(alignment: .leading) {
                    Rectangle().fill(.white).frame(width: width * shown)
                }
                .frame(height: held == nil ? 2 : 6)
                .overlay(alignment: .leading) {
                    if held != nil {
                        Circle().fill(.white).frame(width: 16, height: 16)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .offset(x: width * shown - 8)
                    }
                }
                // The strip a finger can land on is much taller than the line.
                .padding(.bottom, 10)
                .frame(width: width, height: 34, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4).updating($held) { value, held, _ in
                        held = min(1, max(0, value.location.x / max(1, width)))
                    }
                )
                .allowsHitTesting(onSeek != nil)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 94)
                .animation(.snappy(duration: 0.2), value: held != nil)
        }
        .onChange(of: held) { was, now in
            if let now {
                onSeek?(Double(now), false)
            } else if let was {
                onSeek?(Double(was), true)
            }
        }
    }
}

/// The bookmark on a clip. Gold once the clip is saved.
struct ClipSaveButton: View {
    let key: String
    @ObservedObject private var clips = CreateClips.shared
    @State private var pop = false

    var body: some View {
        let on = clips.isSaved(key)
        VStack(spacing: 3) {
            Image(systemName: on ? "bookmark.fill" : "bookmark")
                .font(.system(size: 46 * 0.44, weight: .semibold))
                .foregroundStyle(on ? DL.gold : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 46, height: 46)
                .background(MediaGlass(shape: Circle()))
                .scaleEffect(pop ? 1.18 : 1)
            Text(on ? "Saved" : "Save")
                .font(DL.text(12, .semibold))
                .foregroundStyle(.white)
        }
        .tap {
            clips.toggleSave(key)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { pop = false }
            }
        }
        .accessibilityLabel(on ? "Saved" : "Save")
    }
}

struct FeedScreen: View {
    var clip: MockClip = Mock.clips[0]
    var progress: CGFloat = 0.38
    var voted: Bool? = nil

    var body: some View {
        DLTabs(selected: 1, tint: .white) {
            VideoPage(clip: clip, progress: progress, voted: voted).ignoresSafeArea()
        }
    }
}
