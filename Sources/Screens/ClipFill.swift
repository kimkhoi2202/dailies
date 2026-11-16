import SwiftUI
import AVFoundation

// A clip filmed while the camera drew its picture as a card holds that screen's black bands above and
// below the picture. ClipBands measures them in one frame, and clipFilled zooms the video until the
// picture fills its page, so a clip runs edge to edge like the catalog ones.

/// How much of a video's height is black band at the top and at the bottom, as fractions of the height.
struct ClipBands: Equatable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0

    @MainActor private static var kept: [URL: ClipBands] = [:]

    /// Measured once for each video, then kept.
    @MainActor static func find(_ url: URL) async -> ClipBands {
        if let known = kept[url] { return known }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 260)
        guard let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image else { return ClipBands() }
        let bands = measure(frame)
        kept[url] = bands
        return bands
    }

    private static func measure(_ frame: CGImage) -> ClipBands {
        let w = frame.width, h = frame.height
        guard w > 8, h > 8 else { return ClipBands() }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return ClipBands() }
        // The middle of a row only, so the card's rounded corners do not count as picture.
        func isBlack(_ row: Int) -> Bool {
            for x in (w / 5)..<(w * 4 / 5) {
                let at = (row * w + x) * 4
                if pixels[at] > 22 || pixels[at + 1] > 22 || pixels[at + 2] > 22 { return false }
            }
            return true
        }
        // A band is never a fifth of the screen. Black that deep is a dark frame, which is left alone.
        let limit = h / 5
        var top = 0, bottom = 0
        while top < limit, isBlack(top) { top += 1 }
        while bottom < limit, isBlack(h - 1 - bottom) { bottom += 1 }
        guard top < limit, bottom < limit else { return ClipBands() }
        // One row more than was measured, to cover the soft edge where a band meets the picture.
        func share(_ rows: Int) -> CGFloat { rows * 50 < h ? 0 : CGFloat(rows + 1) / CGFloat(h) }
        return ClipBands(top: share(top), bottom: share(bottom))
    }
}

private struct ClipFilled: ViewModifier {
    let url: URL
    @State private var bands = ClipBands()

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let zoom = 1 / (1 - bands.top - bands.bottom)
            content
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(zoom)
                .offset(y: (bands.bottom - bands.top) / 2 * geo.size.height * zoom)
        }
        .clipped()
        .task(id: url) {
            let found = await ClipBands.find(url)
            withAnimation(.easeOut(duration: 0.2)) { bands = found }
        }
    }
}

extension View {
    /// Zooms a video past the black bands it was filmed with, so its picture fills the space it is given.
    func clipFilled(_ url: URL) -> some View { modifier(ClipFilled(url: url)) }
}
