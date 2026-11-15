import SwiftUI
import UIKit

// What happens when a like lands. A like is a rare, deliberate tap, so it earns half a second of
// celebration: the thumb kicks, a ring and eight short strokes fly out of it, a "+1" lifts off the
// count and the phone gives a success tap. With Reduce Motion on, only the icon changes.

/// Goes on the like icon. Plays once each time `active` turns true.
struct LikeCelebration: ViewModifier {
    var active: Bool
    /// The ring and strokes: white on video, ink on a page.
    var tint: Color = .white
    /// false leaves only the kick, for a small icon inside a pill.
    var burst: Bool = true
    @State private var runs = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pose {
        var scale = 1.0
        var tilt = 0.0
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: Pose(), trigger: runs) { icon, pose in
                icon.scaleEffect(pose.scale).rotationEffect(.degrees(pose.tilt), anchor: .bottomLeading)
            } keyframes: { _ in
                // dip, overshoot, settle
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.86, duration: 0.07)
                    SpringKeyframe(1.24, duration: 0.16, spring: Spring(duration: 0.16, bounce: 0))
                    SpringKeyframe(1.0, duration: 0.36, spring: Spring(duration: 0.36, bounce: 0.3))
                }
                KeyframeTrack(\.tilt) {
                    CubicKeyframe(0, duration: 0.07)
                    CubicKeyframe(-16, duration: 0.14)
                    SpringKeyframe(0, duration: 0.38, spring: Spring(duration: 0.38, bounce: 0.3))
                }
            }
            .background {
                if burst { LikeBurst(runs: runs, tint: tint).allowsHitTesting(false) }
            }
            .onChange(of: active) { before, after in
                guard after, !before else { return }
                if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                if !reduceMotion { runs += 1 }
            }
    }
}

/// A ring and eight short strokes that leave the icon and fade.
private struct LikeBurst: View {
    var runs: Int
    var tint: Color

    var body: some View {
        // `travel` runs from 0 to 1 during a burst and rests at 1, where nothing is visible.
        KeyframeAnimator(initialValue: 1.0, trigger: runs) { travel in
            ZStack {
                Circle().strokeBorder(tint, lineWidth: 2)
                    .scaleEffect(0.75 + 0.95 * travel)
                    .opacity(0.55 * (1 - travel))
                ForEach(0..<8, id: \.self) { spoke in
                    Capsule().fill(tint)
                        .frame(width: 3, height: 9)
                        .scaleEffect(1 - 0.45 * travel)
                        .offset(y: -(24 + 20 * travel))
                        .rotationEffect(.degrees(22.5 + 45 * Double(spoke)))
                        .opacity(travel < 0.999 ? min(1, 1.6 * (1 - travel)) : 0)
                }
            }
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                // most of the distance in the first 0.2 s, then a slow finish
                CubicKeyframe(0.72, duration: 0.2)
                CubicKeyframe(1.0, duration: 0.3)
            }
        }
    }
}

/// A "+1" that lifts off the like count and fades. Goes on the count.
struct LikePlusOne: ViewModifier {
    var active: Bool
    var tint: Color = .white
    @State private var runs = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Lift {
        var rise = 0.0
        var opacity = 0.0
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                // It rises to the left of the count, where nothing else is drawn.
                KeyframeAnimator(initialValue: Lift(), trigger: runs) { lift in
                    Text("+1").font(DL.text(15, .bold)).foregroundStyle(tint)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: -30, y: 4 - lift.rise)
                        .opacity(lift.opacity)
                } keyframes: { _ in
                    KeyframeTrack(\.rise) {
                        MoveKeyframe(0)
                        CubicKeyframe(16, duration: 0.25)
                        CubicKeyframe(22, duration: 0.35)
                    }
                    KeyframeTrack(\.opacity) {
                        MoveKeyframe(0)
                        CubicKeyframe(1, duration: 0.1)
                        CubicKeyframe(1, duration: 0.2)
                        CubicKeyframe(0, duration: 0.3)
                    }
                }
                .fixedSize()
                .allowsHitTesting(false)
            }
            .onChange(of: active) { before, after in
                if after, !before, !reduceMotion { runs += 1 }
            }
    }
}

extension View {
    func likeCelebration(_ active: Bool, tint: Color = .white, burst: Bool = true) -> some View {
        modifier(LikeCelebration(active: active, tint: tint, burst: burst))
    }

    func likePlusOne(_ active: Bool, tint: Color = .white) -> some View {
        modifier(LikePlusOne(active: active, tint: tint))
    }
}
