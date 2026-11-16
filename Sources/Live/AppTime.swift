import SwiftUI
import UIKit
import Combine
import ConvexMobile

// Time with the app open today, and the gold it gives. The server does the counting: the app sends
// a beat when it opens and every half minute after, and the server adds up the time between beats.
// Being away from the screen is fine. Closing the app stops the count until it is open again.

final class AppTime: ObservableObject {
    static let shared = AppTime()

    struct Mark: Equatable {
        let minutes: Int
        let gold: Int

        /// "15 minutes", "1 hour", "3 hours"
        var name: String {
            if minutes < 60 { return "\(minutes) minutes" }
            return minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
        }
    }

    /// The marks of a day, each giving its gold once. The same list as TIME_MARKS in convex/lib.ts.
    static let marks = [
        Mark(minutes: 15, gold: 5), Mark(minutes: 30, gold: 5), Mark(minutes: 60, gold: 10), Mark(minutes: 120, gold: 20),
        Mark(minutes: 180, gold: 20), Mark(minutes: 240, gold: 25), Mark(minutes: 300, gold: 25), Mark(minutes: 360, gold: 40),
    ]

    /// Seconds with the app open today, as of the server's last answer.
    @Published private(set) var seconds = 0.0
    /// How many of today's marks have given their gold.
    @Published private(set) var passed = 0

    private var day = ""
    private var beats: AnyCancellable?
    private var watching = Set<AnyCancellable>()

    private init() {}

    /// The mark being worked toward. nil once the last one of the day is in.
    var next: Mark? { passed < Self.marks.count ? Self.marks[passed] : nil }

    /// 0 to 1: how far today has come from the last mark to the next one.
    var progress: Double {
        guard let next else { return 1 }
        let from = passed == 0 ? 0 : Double(Self.marks[passed - 1].minutes * 60)
        return min(1, max(0, (seconds - from) / (Double(next.minutes * 60) - from)))
    }

    /// Gold the marks have given today.
    var goldToday: Int { Self.marks.prefix(passed).reduce(0) { $0 + $1.gold } }

    /// "12m to go"
    var leftText: String {
        guard let next else { return "" }
        let minutes = max(1, Int((Double(next.minutes * 60) - seconds) / 60 + 0.999))
        return minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60)h to go"
            : (minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m to go" : "\(minutes)m to go")
    }

    /// Follows the app to the front and away from it. Called when the app's first screen appears.
    func start() {
        guard LiveMode.on, watching.isEmpty else { return }
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.run(true) }.store(in: &watching)
        center.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.run(false) }.store(in: &watching)
        run(UIApplication.shared.applicationState == .active)
    }

    /// Starts the beats when the app is at the front and stops them when it is not.
    private func run(_ on: Bool) {
        if !on {
            beats = nil
            return
        }
        guard beats == nil else { return }
        beat()
        beats = Timer.publish(every: 30, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.beat() }
    }

    private func beat() {
        let today = LiveStore.dayKey(Date())
        if today != day {
            day = today
            seconds = 0
            passed = 0
        }
        Task { @MainActor in
            guard let answer = try? await ConvexLink.shared.mutate("time:beat", ["day": today], as: ConvexTimeBeat.self),
                  today == self.day else { return }
            self.seconds = answer.ms / 1000
            let reached = min(Int(answer.marks), Self.marks.count)
            if answer.gold > 0, reached > 0, !LiveNav.shared.isPlaying {
                LiveNav.shared.say("\(Self.marks[reached - 1].name) in DEGEN today. \(Int(answer.gold)) gold added.")
            }
            self.passed = reached
        }
    }
}

/// The marks of the day on the gold screen: the time so far, the way to the next mark, and every mark with its gold.
struct AppTimeCard: View {
    @ObservedObject private var time = AppTime.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time in DEGEN").dlLabel(10.5)
                Spacer()
                Text("\(LiveStore.playedText(time.seconds)) today").dlLabel(10.5).monospacedDigit()
            }
            if let next = time.next {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+\(next.gold)").font(DL.display(38)).foregroundStyle(DL.ink)
                    Text("gold at \(next.name)").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                    Spacer(minLength: 8)
                    Text(time.leftText).font(DL.text(13, .semibold)).foregroundStyle(DL.goldText)
                }
                .frame(height: 34)
                .lineLimit(1)
            } else {
                Text("Every mark is in for today.").font(DL.text(16, .semibold)).foregroundStyle(DL.ink)
            }
            HStack(spacing: 4) {
                ForEach(AppTime.marks.indices, id: \.self) { index in
                    let mark = AppTime.marks[index]
                    VStack(spacing: 5) {
                        DLMeter(value: index < time.passed ? 1 : (index == time.passed ? time.progress : 0), total: 1)
                        Text(mark.minutes < 60 ? "\(mark.minutes)m" : "\(mark.minutes / 60)h")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(index < time.passed ? DL.ink : DL.ink3)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("The app only has to be open. Each mark gives its gold once a day.")
                .font(DL.text(13)).foregroundStyle(DL.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .dlCard()
    }
}
