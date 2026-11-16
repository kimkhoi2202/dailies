import SwiftUI
import UIKit

// A game's own icon on the Home Screen. iOS only lets Safari add one, so the app draws the icon,
// saves it in Convex and opens a page there (convex/http.ts, /shortcut) for Safari to add.
// Opened from the Home Screen, that page hands over to the app on a degen://play/<game id> address.

enum HomeShortcut {
    /// Draws the game's icon, saves it and opens the page that adds it. false when that did not work.
    @MainActor static func add(_ game: MockGame) async -> Bool {
        let picture = ImageRenderer(content: ClipStill(game: game, showHUD: false, focusY: 0.3).frame(width: 180, height: 180))
        picture.scale = 2
        guard let icon = picture.uiImage?.pngData() else { return false }
        do {
            let link = ConvexLink.shared
            let address: String = try await link.mutate("clips:generateUploadUrl", as: String.self)
            guard let url = URL(string: address) else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.upload(for: request, from: icon)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            struct Answer: Decodable { let storageId: String }
            let stored = try JSONDecoder().decode(Answer.self, from: data).storageId
            let shortcut: String = try await link.mutate("shortcuts:save", ["gameSlug": game.id, "icon": stored], as: String.self)
            let site = ConvexConfig.deploymentURL.replacingOccurrences(of: ".convex.cloud", with: ".convex.site")
            guard let page = URL(string: site + "/shortcut?id=" + shortcut) else { return false }
            return await UIApplication.shared.open(page)
        } catch {
            return false
        }
    }

    /// Opens the game a Home Screen icon points at. A round already going is left alone.
    static func open(_ url: URL) {
        guard url.scheme == "degen", url.host == "play",
              let game = Mock.games.first(where: { $0.id == url.lastPathComponent }) else { return }
        let nav = LiveNav.shared
        if nav.isPlaying { return }
        nav.layers = [Layer(route: .play(game.id, solo: game.playerRange.lowerBound == 1))]
    }
}

/// The round button that puts the game on the Home Screen.
struct HomeShortcutButton: View {
    let game: MockGame
    @State private var working = false

    var body: some View {
        DLMediaButton(symbol: "plus.app", size: 40)
            .opacity(working ? 0.5 : 1)
            .tap {
                guard !working else { return }
                working = true
                Task { @MainActor in
                    let added = await HomeShortcut.add(game)
                    if !added { LiveNav.shared.say("Could not make the icon. Try again.") }
                    working = false
                }
            }
            .accessibilityLabel("Add \(game.title) to your Home Screen")
    }
}
