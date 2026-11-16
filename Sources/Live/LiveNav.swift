import SwiftUI
import UIKit

// How the app moves between screens. The tabs are always underneath. Every other screen is
// a layer stacked on top of them: a pushed page, a full-screen cover or a sheet.

enum Route: Hashable {
    // playing
    case gameReady(String)
    case play(String, solo: Bool)
    case results
    // about one game
    case gameDetail(String)
    case leaderboard(String)
    case comments(String)
    case fairness(String)
    case spend(Int)
    case shareRun(String)
    // the player
    case gold
    case history
    case streak
    case search
    case inbox
    case settings
    /// Create an account or log in. The text says what the account is for, when something asked for one.
    case account(String?)
    case saveGold
    case notify
    // people who make games
    case studio
    case publish(Int)
    case reviewProgress
    case reviewResult
    case reviewChanges
    // the tab bar and the library
    case profile(String)
    case join
    case startRoom
    case room(String)
    case libraryGame(String)
    /// One of your own posted clips, by its id.
    case myClip(String)
    /// A list of clips full screen ("mine", "saved" or "user:<handle>"), starting at a clip.
    case clipList(String, String)
    // the avatar
    /// An item id to open on its sheet, "closet" for the Closet, or nil.
    case shop(String?)
    // making a clip
    case create(String?)
    case createPreview
    // making a game in the studio
    case makeGame
    case makeChat(String)
    case makePreview(String)
    // community
    case notifications
    case story(Int)
    case rate(String)
    /// Friends' videos full screen, starting at this feed entry.
    case friendVideos(String)
    // messages
    case messages
    case chat(String)
    case newGroup
    case workplace
    case playTogether(String)
    // money, through Whop
    case buyGold
    case earnings
    case sendEarnings
    case program(String)

    enum Style { case push, cover, sheet }

    var style: Style {
        switch self {
        case .gameDetail, .leaderboard, .gold, .history, .search, .inbox, .settings, .studio, .profile, .room, .shop, .makeChat, .makePreview, .notifications:
            .push
        case .story, .friendVideos, .myClip, .clipList:
            .cover
        case .rate:
            .sheet
        case .gameReady, .play, .results, .shareRun, .publish, .reviewProgress, .reviewResult, .reviewChanges,
             .create, .createPreview, .makeGame:
            .cover
        case .comments, .fairness, .spend, .streak, .saveGold, .notify, .join, .startRoom:
            .sheet
        case .messages, .chat, .newGroup, .workplace:
            .push
        case .playTogether, .libraryGame, .buyGold, .sendEarnings, .program, .account:
            .sheet
        case .earnings:
            .push
        }
    }

    fileprivate var isPublishing: Bool {
        switch self {
        case .publish, .reviewProgress, .reviewResult, .reviewChanges, .makeGame, .makeChat, .makePreview: true
        default: false
        }
    }
}

struct Layer: Identifiable, Equatable {
    let id = UUID()
    let route: Route
}

final class LiveNav: ObservableObject {
    static let shared = LiveNav()

    /// 0 Community (in place of Home), 1 Videos, 2 You (out of the bar, shown as the profile), 3 Messages, 4 Library
    /// The app opens on Reels.
    @Published var tab = 1
    @Published var layers: [Layer] = []
    /// The clip on screen in Videos, as an index into its endless column.
    @Published var videoIndex: Int? = 0
    /// A short message near the bottom of the screen. It clears itself.
    @Published var toast: String?

    private var toastClearing: DispatchWorkItem?

    var topRoute: Route? { layers.last?.route }

    var isPlaying: Bool {
        if case .play = topRoute { true } else { false }
    }

    func open(_ route: Route) {
        withAnimation(.snappy(duration: 0.32)) { layers.append(Layer(route: route)) }
    }

    /// true for someone with an account. A guest is shown the Account screen instead, saying what it is for.
    func hasAccount(to what: String) -> Bool {
        guard LiveMode.on, DeviceAccount.kind == nil else { return true }
        open(.account("Create an account to \(what)."))
        return false
    }

    func back() {
        guard !layers.isEmpty else { return }
        withAnimation(.snappy(duration: 0.3)) { _ = layers.removeLast() }
    }

    /// Puts another screen in place of the top one with a quick fade of the stack, not a slide.
    /// The play flow moves this way: ready, playing, results.
    func replaceTop(_ route: Route) {
        withAnimation(.easeInOut(duration: 0.25)) {
            layers = Array(layers.dropLast()) + [Layer(route: route)]
        }
    }

    func closeAll() {
        withAnimation(.snappy(duration: 0.32)) { layers.removeAll() }
    }

    /// Leaves publishing and its review in one step, however many of those screens are open.
    func closeFlow() {
        withAnimation(.snappy(duration: 0.32)) {
            while let top = topRoute, top.isPublishing { layers.removeLast() }
        }
    }

    func goToTab(_ index: Int) {
        closeAll()
        tab = index
    }

    /// Back to Videos, then on to the clip after the one that was showing.
    func nextClip() {
        let next = (videoIndex ?? 0) + 1
        goToTab(1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.snappy(duration: 0.4)) { self.videoIndex = next }
        }
    }

    /// Shows a toast for a little over two seconds. A newer toast takes over from an older one.
    func say(_ text: String) {
        toastClearing?.cancel()
        withAnimation(.snappy(duration: 0.25)) { toast = text }
        let clearing = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
        toastClearing = clearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: clearing)
    }

    /// The system share sheet, from whichever controller is in front.
    func share(_ text: String) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var front = windows.first?.rootViewController else { return }
        while let above = front.presentedViewController { front = above }
        let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = front.view
        front.present(sheet, animated: true)
    }
}

// MARK: Pressing

extension EnvironmentValues {
    /// true while the button around a view is held down. A 3D key reads it and travels down.
    @Entry var dlPressed: Bool = false
}

/// A 3D key sets this, to tell the button around it that the key shows the press itself.
struct DLHasKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// How a control answers a press. A 3D key goes down onto its edge. Anything flat dips a little.
struct DLPressStyle: ButtonStyle {
    /// Held true for a moment after a tap, so that even a quick tap shows.
    var flash = false

    func makeBody(configuration: Configuration) -> some View {
        Pressable(label: configuration.label, down: configuration.isPressed || flash)
    }

    private struct Pressable: View {
        let label: ButtonStyleConfiguration.Label
        let down: Bool
        @State private var keyInside = false

        var body: some View {
            let shrinks = down && !keyInside
            // About 4.5 points off the width whatever the size, so a wide card does not lurch.
            label
                .environment(\.dlPressed, down)
                .onPreferenceChange(DLHasKey.self) { keyInside = $0 }
                .visualEffect { content, proxy in
                    content.scaleEffect(shrinks ? max(0.95, 1 - 4.5 / max(proxy.size.width, 1)) : 1)
                }
                .animation(.easeOut(duration: down ? 0.15 : 0.3), value: down)
        }
    }
}

/// A control with an action. In a scrolling page iOS holds a touch back briefly to see whether it
/// is a scroll, so a quick tap would never look pressed. The flash keeps the press on screen for a beat.
private struct TapControl<Label: View>: View {
    let action: () -> Void
    let label: Label
    @State private var flash = false

    var body: some View {
        Button {
            if LiveStore.shared.s.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
            flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) { flash = false }
            action()
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(DLPressStyle(flash: flash))
    }
}

extension View {
    /// Makes this view a control: it takes taps over its whole frame, shows the press and gives a light haptic.
    func tap(_ action: @escaping () -> Void) -> some View {
        TapControl(action: action, label: self)
    }

    func opens(_ route: Route) -> some View {
        tap { LiveNav.shared.open(route) }
    }

    func goesBack() -> some View {
        tap { LiveNav.shared.back() }
    }

    /// For controls the design shows but nothing stands behind yet.
    func notYet(_ what: String) -> some View {
        tap { LiveNav.shared.say("\(what) is not part of this demo yet") }
    }
}
