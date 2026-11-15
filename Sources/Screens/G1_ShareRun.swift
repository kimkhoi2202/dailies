import SwiftUI

// POST THIS RUN: where the feed's clips come from. The run is already recorded. The player keeps
// its best stretch, writes a line and posts. Full screen, with no tab bar.

enum G1ShareData {
    static let game = Mock.roundGame
    static let captionLines = ["41 floors and a new best.", "coming for your 58, @devon.plays"]
    static let captionLimit = 150
    static let clipStart = "2:06"
    /// The round lasted 2m 48s, and the clip runs to its end.
    static let clipEnd = "2:48"
    static let clipSeconds = 42
    /// Where the kept part begins along the strip: the last 42 seconds of 168.
    static let trimStart: CGFloat = 0.75
}

/// The clip as the feed will show it: a tall card with the score on it.
struct G1RunPreview: View {
    let game: MockGame
    var showScore: Bool = true

    var body: some View {
        ZStack {
            ClipStill(game: game, phase: 0.95, showHUD: false, focusY: 0.24)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                G1MediaLabel(text: "Clip 0:\(G1ShareData.clipSeconds)")
                Spacer()
                if showScore {
                    Text(Mock.roundScore)
                        .font(DL.display(64))
                        .foregroundStyle(.white)
                        .frame(height: 54)
                    Text(Mock.roundScoreLabel.uppercased())
                        .font(DL.display(22))
                        .tracking(1.5)
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            DLMediaButton(symbol: "play.fill", size: 48)
        }
        .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
        .accessibilityLabel("Clip preview, \(Mock.roundScore) \(Mock.roundScoreLabel)")
    }
}

/// The whole run as a strip of frames in a black well. Two white grips frame the stretch that is kept.
struct G1TrimBar: View {
    let game: MockGame
    var start: CGFloat = G1ShareData.trimStart
    var frames: Int = 10
    var height: CGFloat = 52

    /// The black edge of the well around the strip.
    private let rim: CGFloat = 3
    private let gripWidth: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let stripWidth = geo.size.width - rim * 2
            let stripHeight = height - rim * 2
            let keptFrom = stripWidth * start
            let keptWidth = stripWidth - keptFrom
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<frames, id: \.self) { index in
                        let moment = 0.12 + 0.84 * Double(index) / Double(frames - 1)
                        ClipStill(game: game, phase: moment, showHUD: false, focusY: 0.32)
                            .frame(width: stripWidth / CGFloat(frames), height: stripHeight)
                    }
                }
                // Everything before the kept stretch is dimmed.
                Color.black.opacity(0.6).frame(width: keptFrom, height: stripHeight)
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: keptWidth, height: stripHeight)
                    .offset(x: keptFrom)
                grip(height: stripHeight).offset(x: keptFrom)
                grip(height: stripHeight).offset(x: stripWidth - gripWidth)
                // the playhead
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: stripHeight - 12)
                    .offset(x: keptFrom + keptWidth * 0.42)
            }
            .frame(width: stripWidth, height: stripHeight)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(rim)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black))
        }
        .frame(height: height)
        .accessibilityLabel("Trim: \(G1ShareData.clipSeconds) seconds kept")
    }

    private func grip(height: CGFloat) -> some View {
        Rectangle()
            .fill(.white)
            .frame(width: gripWidth, height: height)
            .overlay(Capsule().fill(.black.opacity(0.55)).frame(width: 2.5, height: 14))
    }
}

/// The caption being written: two typed lines and a caret.
struct G1CaptionField: View {
    var body: some View {
        let lines = G1ShareData.captionLines
        let typed = lines.joined(separator: " ").count
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Caption").dlLabel(10.5)
                Spacer()
                Text("\(typed) of \(G1ShareData.captionLimit)").dlLabel(10.5, color: DL.ink3)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lines[0]).font(DL.text(17)).foregroundStyle(DL.ink)
                HStack(spacing: 2) {
                    Text(lines[1]).font(DL.text(17)).foregroundStyle(DL.ink)
                    RoundedRectangle(cornerRadius: 1).fill(DL.ink).frame(width: 2, height: 22)
                }
            }
        }
        .dlCard(padding: 16)
    }
}

struct G1ShareRunScreen: View {
    var game: MockGame = G1ShareData.game

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DLNavBar(title: "Post this run", trailingSymbol: "xmark", showBack: false, trailingAction: { LiveNav.shared.back() })
            editor.padding(.top, 10)
            G1CaptionField().padding(.top, 12)
            options.padding(.top, 12)
            Spacer(minLength: 12)
            DLTextKey(title: "Post clip", symbol: "arrow.up")
                .tap {
                    LiveNav.shared.back()
                    LiveNav.shared.say("Your clip is posted")
                }
        }
        .padding(.horizontal, DL.margin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(DL.body.ignoresSafeArea())
    }

    /// The preview and the trim bar, as one module.
    private var editor: some View {
        VStack(spacing: 0) {
            G1RunPreview(game: game).frame(width: 176, height: 266)
            G1TrimBar(game: game, height: 48).padding(.top, 12)
            HStack {
                Text("Best \(G1ShareData.clipSeconds) seconds").font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
                Spacer()
                Text("\(G1ShareData.clipStart) to \(G1ShareData.clipEnd)").dlLabel(10.5)
            }
            .padding(.top, 8)
        }
        .dlCard(padding: 14)
    }

    private var options: some View {
        VStack(spacing: 0) {
            DLRow(title: "Posting as @\(Mock.handle)", detail: "Likes and dislikes go to \(game.title)") {
                DLAvatar(name: Mock.handle, size: 36)
            } trailing: {
                EmptyView()
            }
            DLDivider(inset: 48)
            DLRow(title: "Show my score", detail: "\(Mock.roundScore) \(Mock.roundScoreLabel), shown on the clip") {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DL.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DL.body))
            } trailing: {
                G1Switch(isOn: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .dlCard(padding: 0)
    }
}
