import SwiftUI

// Group G3, the studio side: the parts its screens share. All drawn from the design system's tokens.

// MARK: Page furniture

/// A full-screen step in a flow (publishing, the review). Content hangs from the top and the footer,
/// usually one key, stays at the bottom. There is no tab bar.
struct G3Flow<Content: View, Footer: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: spacing, content: content)
                .padding(.top, 6)
            Spacer(minLength: 0)
            footer()
                .padding(.bottom, 8)
        }
        .padding(.horizontal, DL.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DL.body.ignoresSafeArea())
    }
}

/// A display title on tight lines. A mark can follow the first line, and a close button sits opposite.
struct G3Title<Mark: View>: View {
    var lines: [String]
    var size: CGFloat = 44
    var close: Bool = true
    @ViewBuilder var mark: () -> Mark

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(lines[index].uppercased())
                            .font(DL.display(size))
                            .foregroundStyle(DL.ink)
                            .fixedSize()
                            // The face has tall line spacing. Clamp it so two lines sit close.
                            .frame(height: size * 0.9)
                        if index == 0 { mark() }
                    }
                }
            }
            Spacer(minLength: 0)
            if close {
                DLIconButton(symbol: "xmark")
                    .tap { LiveNav.shared.closeFlow() }
                    .accessibilityLabel("Close")
            }
        }
    }
}

extension G3Title where Mark == EmptyView {
    init(lines: [String], size: CGFloat = 44, close: Bool = true) {
        self.init(lines: lines, size: size, close: close) { EmptyView() }
    }
}

/// The review's seal: gold with an ink tick, the same in both appearances.
struct G3Seal: View {
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .symbolRenderingMode(.palette)
            .foregroundStyle(DL.onGold, DL.gold)
            .accessibilityLabel("Reviewed")
    }
}

// MARK: Controls

/// Chooses a period. One ink capsule slides along a surface track.
struct G3Segmented: View {
    var options: [String]
    var selected: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let chosen = index == selected
                Text(options[index])
                    .font(DL.text(14, .semibold))
                    .foregroundStyle(chosen ? DL.onInk : DL.ink2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Capsule().fill(chosen ? DL.ink : .clear))
            }
        }
        .padding(3)
        .background(Capsule().fill(DL.surface))
    }
}

/// How far through publishing you are, as segments.
struct G3Steps: View {
    var step: Int
    var total: Int = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { number in
                Capsule()
                    .fill(number <= step ? DL.ink : DL.sunken)
                    .frame(height: 6)
            }
        }
        .accessibilityLabel("Step \(step) of \(total)")
    }
}

/// A filled field: a mono label above a surface box holding the value.
struct G3Field<Trailing: View>: View {
    var label: String
    var value: String
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).dlLabel(10.5).padding(.leading, 4)
            HStack(spacing: 10) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DL.ink3)
                }
                Text(value).font(DL.text(17)).foregroundStyle(DL.ink).lineLimit(1)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DL.surface))
        }
    }
}

extension G3Field where Trailing == Text {
    /// A field that counts its characters against a limit.
    init(label: String, value: String, limit: Int) {
        self.init(label: label, value: value) {
            Text("\(value.count)/\(limit)").font(DL.label(11)).foregroundStyle(DL.ink3)
        }
    }
}

/// A category that can be picked. Picked, it turns ink and gains a tick.
struct G3Chip: View {
    var text: String
    var selected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if selected {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .black))
            }
            Text(text).font(DL.text(15, .semibold))
        }
        .foregroundStyle(selected ? DL.onInk : DL.ink)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(selected ? DL.ink : DL.surface))
        .fixedSize()
    }
}

/// A checkbox. Ticked, it is an ink tile. Empty, an outline.
struct G3Checkbox: View {
    var on: Bool = true
    var size: CGFloat = 26

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        ZStack {
            if on {
                tile.fill(DL.ink)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.48, weight: .black))
                    .foregroundStyle(DL.onInk)
            } else {
                tile.strokeBorder(DL.ink3, lineWidth: 2)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: Figures

/// A bar for each day. Today, the last one, is gold. The days before it sit back.
struct G3BarChart: View {
    var values: [Double]
    var labels: [String]
    var barHeight: CGFloat = 64

    var body: some View {
        let tallest = values.max() ?? 1
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(values.indices, id: \.self) { day in
                let isToday = day == values.count - 1
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isToday ? DL.gold : DL.sunken)
                        .frame(height: max(6, barHeight * values[day] / tallest))
                    Text(labels[day])
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isToday ? DL.ink : DL.ink3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Plays over the last seven days")
    }
}

/// Every test session the reviewer played, one cell each. The sessions it flagged are inked.
struct G3SessionGrid: View {
    var total: Int = 240
    var flagged: Int = 31
    var columns: Int = 30
    var gap: CGFloat = 3

    var body: some View {
        let inked = flaggedCells
        VStack(spacing: gap) {
            ForEach(0..<(total / columns), id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<columns, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(inked.contains(row * columns + column) ? DL.ink : DL.sunken)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityLabel("\(flagged) of \(total) sessions")
    }

    /// Which cells are inked: scattered unevenly, but the same cells on every launch.
    private var flaggedCells: Set<Int> {
        // A small linear congruential generator, seeded with the day of the hackathon.
        var state: UInt32 = 20261114
        var picked: Set<Int> = []
        while picked.count < min(flagged, total) {
            state = state &* 1664525 &+ 1013904223
            picked.insert(Int((state >> 9) % UInt32(total)))
        }
        return picked
    }
}

/// Where one of the review's checks has got to.
enum G3CheckState { case done, running, waiting }

/// The mark at the start of a check's row: a tick, a filling ring, or an empty ring.
struct G3StateMark: View {
    var state: G3CheckState
    var progress: Double = 0.62
    var size: CGFloat = 26

    var body: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.46, weight: .black))
                .foregroundStyle(DL.onInk)
                .frame(width: size, height: size)
                .background(Circle().fill(DL.ink))
        case .running:
            DLRing(progress: progress, size: size, line: 4.5, showTick: false)
        case .waiting:
            Circle()
                .strokeBorder(DL.sunken, lineWidth: 4.5)
                .frame(width: size, height: size)
        }
    }
}

// MARK: Clip editing

/// A strip of frames from the clip. The part that is kept is framed in ink, with a grip at each end.
struct G3TrimBar: View {
    let game: MockGame
    var start: CGFloat = 0.1
    var end: CGFloat = 0.9
    var playhead: CGFloat = 0.4
    var height: CGFloat = 48

    private let frameCount = 9
    private let corner: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shade = DL.surface.opacity(0.74)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<frameCount, id: \.self) { index in
                        let moment = 0.06 + 0.88 * Double(index) / Double(frameCount - 1)
                        ClipStill(game: game, phase: moment, showHUD: false, focusY: 0.42)
                            .frame(width: width / CGFloat(frameCount), height: height)
                    }
                }
                // What is cut away, before and after, is washed out.
                shade.frame(width: width * start)
                shade.frame(width: width * (1 - end)).offset(x: width * end)
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    grip(onLeft: true)
                    Spacer(minLength: 0)
                    grip(onLeft: false)
                }
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).strokeBorder(DL.ink, lineWidth: 3))
                .frame(width: width * (end - start), height: height)
                .offset(x: width * start)
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height - 10)
                    .offset(x: width * playhead)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Trim the clip")
    }

    private func grip(onLeft: Bool) -> some View {
        let outer = onLeft ? corner : 0
        let inner = onLeft ? 0 : corner
        return UnevenRoundedRectangle(topLeadingRadius: outer, bottomLeadingRadius: outer,
                                      bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
            .fill(DL.ink)
            .frame(width: 15)
            .overlay(Capsule().fill(DL.onInk).frame(width: 2.5, height: 16))
    }
}

/// A Play key that cannot be pressed yet. In a preview it keeps the real gold key the only one on screen.
struct G3GhostPlayKey: View {
    var trailing: String

    var body: some View {
        DLKey(style: .neutral, radius: 20, depth: 5) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .black))
                Text("PLAY").font(DL.display(26)).tracking(0.8)
                Spacer(minLength: 8)
                Text(trailing).font(DL.label(10)).foregroundStyle(DL.ink2).lineLimit(1)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 56)
    }
}

extension MockGame {
    /// This game as it is before release: nobody has played it and nobody has voted.
    var g3Unpublished: MockGame {
        MockGame(id: "\(id)-draft", kind: kind, title: title, tagline: tagline, category: category,
                 players: players, mode: mode, studio: studio, goldPerMinute: goldPerMinute,
                 avgSession: avgSession, seedEarned: 0, plays: "0", likes: "0", dislikes: "0", approval: 0,
                 bestScore: bestScore, clipPhase: clipPhase, tint: tint)
    }
}
