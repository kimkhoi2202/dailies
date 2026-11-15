import SwiftUI

// The sheet a game opens from the Library: everything you can do with that game in one place.

/// A game's sheet from the Library: its cover, your best, and every way to play it.
struct LibraryGameSheet: View {
    let game: MockGame
    @ObservedObject private var store = LiveStore.shared
    @State private var starting = false
    @State private var problem: String?

    var body: some View {
        let best = LiveBoard.yourBest(game)
        let played = best.value != "0"
        let saved = store.saved.contains(game.id)
        let multiplayer = game.playerRange.upperBound > 1
        DLSheet(height: multiplayer ? 590 : 522) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                ClipStill(game: game, showHUD: false, focusY: 0.3)
                    .frame(height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        DLMediaButton(symbol: "xmark", size: 36).goesBack().padding(10).accessibilityLabel("Close")
                    }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title.uppercased()).font(DL.display(38)).foregroundStyle(DL.ink)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(game.players), \(game.mode.lowercased())").font(DL.text(14)).foregroundStyle(DL.ink2)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("Your best").dlLabel()
                        Text(played ? best.value : "None yet").font(DL.display(played ? 34 : 22)).foregroundStyle(DL.ink)
                            .monospacedDigit()
                        if played { Text(best.detail).font(DL.text(12)).foregroundStyle(DL.ink2) }
                    }
                }

                HStack(spacing: 8) {
                    DLMeter(value: Double(game.leftToday), total: Double(game.capToday), height: 4)
                    Text("\(game.leftToday) gold left today").font(DL.label(10)).foregroundStyle(DL.goldText).monospacedDigit()
                }
                .accessibilityElement(children: .combine)

                if let problem {
                    Text(problem).font(DL.text(14)).foregroundStyle(DL.danger)
                }

                DLPlayKey().tap { LiveNav.shared.replaceTop(.gameReady(game.id)) }

                if multiplayer {
                    HStack(spacing: 10) {
                        DLTextKey(title: starting ? "Starting" : "Start a room", symbol: "person.2.fill", style: .ink)
                            .tap(startRoom)
                        DLTextKey(title: "Join with a code", style: .neutral)
                            .tap { LiveNav.shared.replaceTop(.join) }
                    }
                }

                HStack(spacing: 10) {
                    DLTextKey(title: saved ? "Saved" : "Save", symbol: saved ? "bookmark.fill" : "bookmark", style: .neutral)
                        .tap { store.toggleSave(game.id) }
                        .accessibilityLabel(saved ? "Unsave" : "Save")
                    DLTextKey(title: "Game page", symbol: "info.circle", style: .neutral)
                        .tap { LiveNav.shared.replaceTop(.gameDetail(game.id)) }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func startRoom() {
        guard !starting else { return }
        starting = true
        problem = nil
        Task { @MainActor in
            do {
                let code = try await ConvexLink.shared.mutate("rooms:create", ["slug": game.id], as: String.self)
                LiveNav.shared.replaceTop(.room(code))
            } catch {
                problem = LiveRoomRound.message(for: error)
            }
            starting = false
        }
    }
}
