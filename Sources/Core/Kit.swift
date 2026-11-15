import SwiftUI
import UIKit

extension Color {
    /// A Display P3 colour from six hex digits, with or without a leading "#".
    init(hex: String, opacity: Double = 1) {
        let rgb = UInt32(hex.drop { $0 == "#" }, radix: 16) ?? 0
        func channel(_ shift: UInt32) -> Double { Double((rgb >> shift) & 0xFF) / 255 }
        self.init(.displayP3, red: channel(16), green: channel(8), blue: channel(0), opacity: opacity)
    }

    /// One colour with a value for each appearance.
    init(light: String, dark: String) {
        let lightValue = UIColor(Color(hex: light)), darkValue = UIColor(Color(hex: dark))
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? darkValue : lightValue })
    }
}

/// One frame of a game's gameplay clip. The scene is always laid out on a 402 x 874 phone screen,
/// then scaled until it covers the frame and cropped, the way a portrait video is aspect-filled.
struct ClipStill: View {
    let game: MockGame
    var phase: Double? = nil
    var showHUD: Bool = true
    /// Which part of the tall clip survives the crop when the frame is shorter: 0 keeps the top, 1 the bottom.
    var focusY: CGFloat = 0.12

    private static let stage = CGSize(width: 402, height: 874)

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size, stage = Self.stage
            let zoom = max(frame.width / stage.width, frame.height / stage.height)
            game.scene(phase: phase, showHUD: showHUD)
                .frame(width: stage.width, height: stage.height)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .offset(x: (frame.width - stage.width * zoom) / 2, y: (frame.height - stage.height * zoom) * focusY)
        }
        .clipped()
        // The scene is larger than its frame. Without this the cropped part would take touches meant for its neighbours.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 12345 becomes "12,345", whatever the phone's region.
func groupedNumber(_ n: Int) -> String {
    n.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
}
