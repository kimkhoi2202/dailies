import SwiftUI

// PUBLISHING: three short steps, each full screen. The game, the clip, then a check before sending.
// The key is ink until the last step. Gold is kept for the moment the game is sent.

private enum G3Draft {
    static let game = Mock.reviewGame
    static let link = "wobbleworks.games/spiral-drop"
    static let caption = "triple combo on level 7"
    static let clipLength = "0:35"
}

/// The top of every step: the bar with its close button, the progress segments, then the step's title.
private struct G3StepHeader: View {
    var step: Int
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DLNavBar(title: "Publish a game", trailingSymbol: "xmark", trailingAction: { LiveNav.shared.closeFlow() })
            G3Steps(step: step).padding(.top, 14)
            DLHeader(kicker: "Step \(step) of 3", title: title).padding(.top, 18)
        }
    }
}

/// A mono label over a block of the form, set in slightly so it lines up with rounded fields.
private struct G3Labelled<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).dlLabel(10.5).padding(.leading, 4)
            content()
        }
    }
}

// MARK: Step 1, the game

struct G3PublishGameScreen: View {
    private let categories = [["Arcade", "Puzzle", "Word", "Runner"], ["Casual", "Multiplayer", "Sport"]]
    private let chosenCategory = "Arcade"

    var body: some View {
        G3Flow(spacing: 18) {
            G3StepHeader(step: 1, title: "The game")
            linkField
            G3Field(label: "Title", value: G3Draft.game.title, limit: 24)
            G3Field(label: "One line pitch", value: G3Draft.game.tagline, limit: 40)
            G3Labelled(label: "Category") {
                ForEach(categories, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { name in
                            G3Chip(text: name, selected: name == chosenCategory)
                        }
                    }
                }
            }
        } footer: {
            VStack(spacing: 14) {
                Text("Nothing is public until the review is done.")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink2)
                DLTextKey(title: "Next", style: .ink).opens(.publish(2))
            }
        }
    }

    /// The link to the game, and under it what was found at the other end.
    private var linkField: some View {
        G3Labelled(label: "Game link") {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "link").font(.system(size: 15, weight: .semibold)).foregroundStyle(DL.ink3)
                    Text(G3Draft.link).font(DL.text(17)).foregroundStyle(DL.ink).lineLimit(1)
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                DL.line.frame(height: 1).padding(.leading, 16)
                HStack(spacing: 12) {
                    DLThumb(game: G3Draft.game, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Game found").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                        Text("It loads and plays in portrait.").font(DL.text(13)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(DL.ink)
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.surface))
        }
    }
}

// MARK: Step 2, the clip

struct G3PublishClipScreen: View {
    private let stillHeight: CGFloat = 224

    var body: some View {
        G3Flow(spacing: 16) {
            G3StepHeader(step: 2, title: "The clip")
            Text("Your first clip must be real play, recorded in the game.")
                .font(DL.text(17, .medium))
                .foregroundStyle(DL.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -6)
            clipCard
            G3Field(label: "Caption", value: G3Draft.caption, limit: 80)
        } footer: {
            DLTextKey(title: "Next", style: .ink).opens(.publish(3))
        }
    }

    private var clipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ClipStill(game: G3Draft.game, focusY: 0.1)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .black))
                            Text("0:18").font(DL.label(10.5))
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                    }
                    .frame(width: 144, height: stillHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                clipFacts.frame(height: stillHeight)
            }
            VStack(spacing: 6) {
                G3TrimBar(game: G3Draft.game, start: 0.09, end: 0.886, playhead: 0.41)
                HStack {
                    Text("0:04").dlLabel(10)
                    Spacer()
                    Text("Drag the ends to trim").dlLabel(10, color: DL.ink3)
                    Spacer()
                    Text("0:39").dlLabel(10)
                }
            }
        }
        .dlCard(padding: 12)
    }

    /// Beside the still: how long the clip is, what was checked about it, and a way to record again.
    private var clipFacts: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Length").dlLabel(10.5)
            Text(G3Draft.clipLength)
                .font(DL.display(64))
                .foregroundStyle(DL.ink)
                .fixedSize()
                .frame(height: 58)
            Text("Clips run 20 to 45 seconds.")
                .font(DL.text(13))
                .foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(["Recorded in the game", "Portrait, sound on"], id: \.self) { fact in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16)).foregroundStyle(DL.ink)
                        Text(fact).font(DL.text(14, .medium)).foregroundStyle(DL.ink)
                    }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .bold))
                Text("Record again").font(DL.text(14, .semibold))
            }
            .foregroundStyle(DL.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(Capsule().fill(DL.body))
        }
    }
}

// MARK: Step 3, check and send

struct G3PublishSendScreen: View {
    private let confirmations = [
        "It is my own work",
        "Gold cannot be collected without playing",
        "Suitable for ages 13 and up",
    ]

    var body: some View {
        G3Flow(spacing: 14) {
            G3StepHeader(step: 3, title: "Check and send")
            feedPreview
            checklist
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DL.ink2)
                    .padding(.top, 1)
                Text("We play it about \(Mock.reviewSessions) times before anyone else does. It usually takes ten minutes.")
                    .font(DL.text(14))
                    .foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        } footer: {
            DLTextKey(title: "Send for review", symbol: "paperplane.fill").opens(.reviewProgress)
        }
    }

    /// The feed in small: the clip on top, then the name, the maker, votes at zero and a Play key that is not live yet.
    private var feedPreview: some View {
        let game = G3Draft.game
        let frame = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return G3Labelled(label: "How it will look in Videos") {
            VStack(spacing: 0) {
                ClipStill(game: game, showHUD: false, focusY: 0.43)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom))
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Text("CLIP \(G3Draft.clipLength)")
                                    .font(DL.label(9.5))
                                    .padding(.horizontal, 6)
                                    .frame(height: 18)
                                    .background(Capsule().fill(.white.opacity(0.22)))
                                Text("@\(Mock.handle)").font(DL.text(12, .semibold))
                            }
                            Text(G3Draft.caption).font(DL.text(14, .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                    }
                    .frame(height: 142)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 16,
                                                      bottomTrailingRadius: 16, topTrailingRadius: 24, style: .continuous))
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.title.uppercased())
                                .font(DL.display(28))
                                .foregroundStyle(DL.ink)
                                .fixedSize()
                                .frame(height: 28)
                            Text("\(game.studio), rate set by review")
                                .font(DL.text(12, .medium))
                                .foregroundStyle(DL.ink2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        DLVotePill(game: game.g3Unpublished).scaleEffect(0.86, anchor: .trailing)
                    }
                    G3GhostPlayKey(trailing: "LIVE AFTER REVIEW")
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 6)
            }
            .padding(6)
            .background(frame.fill(DL.body))
            .overlay(frame.strokeBorder(DL.line, lineWidth: 1.5))
        }
    }

    private var checklist: some View {
        VStack(spacing: 0) {
            ForEach(confirmations.indices, id: \.self) { index in
                if index > 0 { DLDivider(inset: 38) }
                HStack(spacing: 12) {
                    G3Checkbox()
                    Text(confirmations[index]).font(DL.text(15, .medium)).foregroundStyle(DL.ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).fill(DL.surface))
    }
}
