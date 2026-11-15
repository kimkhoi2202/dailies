import SwiftUI

// THE FEED, OFFLINE. The screen is dark but the deck still works: saved clips are one key away.
// There is never a spinner.

enum G2OfflineData {
    static let savedClips: [MockClip] = Array(Mock.clips.prefix(5))
    static let lastUpdated = "09:12"
}

/// Where the clip would be, with nothing to show: a panel that is switched off, not one that is loading.
struct G2OfflinePanel: View {
    var body: some View {
        ZStack {
            DL.surface
            dotGrid
            VStack(spacing: 0) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(.white.opacity(0.08)))
                Text("YOU'RE OFFLINE")
                    .font(DL.display(46))
                    .foregroundStyle(.white)
                    .padding(.top, 14)
                Text("New clips will be here when you're back.")
                    .font(DL.text(15, .medium))
                    .foregroundStyle(.white.opacity(0.66))
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold))
                    Text("Try again").font(DL.text(14, .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(.white.opacity(0.14)))
                .padding(.top, 20)
            }
            .padding(.top, 30)
            // In the caption's place: when the feed was last fresh.
            HStack(spacing: 8) {
                Text("OFFLINE")
                    .font(DL.label(10.5))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(.white.opacity(0.14)))
                Text("Last updated \(G2OfflineData.lastUpdated)").font(DL.text(14, .medium)).opacity(0.66)
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .environment(\.colorScheme, .dark)
        .clipShape(DL.screenShape)
    }

    /// The faint grid of dots on a display that is off.
    private var dotGrid: some View {
        Canvas { context, size in
            let pitch: CGFloat = 9
            let dot: CGFloat = 1.5
            let shade = GraphicsContext.Shading.color(.white.opacity(0.05))
            for y in stride(from: pitch / 2, to: size.height, by: pitch) {
                for x in stride(from: pitch / 2, to: size.width, by: pitch) {
                    context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)), with: shade)
                }
            }
        }
    }
}

struct G2OfflineScreen: View {
    private let saved = G2OfflineData.savedClips
    private let thumb: CGFloat = 40

    var body: some View {
        DLTabs(selected: 1) {
            VStack(spacing: 0) {
                G2OfflinePanel().frame(height: 598)
                VStack(spacing: 14) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(saved.count) CLIPS SAVED")
                                .font(DL.display(34))
                                .foregroundStyle(DL.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill").font(.system(size: 11)).foregroundStyle(DL.ink2)
                                Text("On this phone, ready to play").font(DL.text(13, .medium)).foregroundStyle(DL.ink2)
                            }
                        }
                        Spacer(minLength: 4)
                        savedPile
                    }
                    DLPlayKey(title: "PLAY SAVED CLIPS", trailing: nil, style: .ink)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DL.body)
            .ignoresSafeArea()
        }
    }

    /// The saved clips as a small overlapping pile, ending in a count of the rest.
    private var savedPile: some View {
        let shown = Array(saved.prefix(3))
        let tile = RoundedRectangle(cornerRadius: thumb * 0.28, style: .continuous)
        // Each tile is ringed in the page colour, so the one in front looks cut out of the one behind.
        let ring = tile.strokeBorder(DL.body, lineWidth: 2).padding(-1)
        return HStack(spacing: -12) {
            ForEach(shown.indices, id: \.self) { index in
                DLThumb(game: shown[index].game, size: thumb)
                    .overlay(ring)
                    .zIndex(Double(shown.count - index))
            }
            Text("+\(saved.count - shown.count)")
                .font(DL.display(18))
                .foregroundStyle(DL.ink)
                .frame(width: thumb, height: thumb)
                .background(tile.fill(DL.surface))
                .overlay(ring)
        }
        .accessibilityLabel("\(saved.count) saved clips")
    }
}
