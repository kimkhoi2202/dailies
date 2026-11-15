import SwiftUI

// Group G1: the small pieces shared by the screens about one game. Its page, its leaderboard,
// search, comments, the spend sheet and posting a run.

/// A quiet link and its chevron. It has no container of its own, so it lays out as two items of the row it is in.
private struct G1LinkTail: View {
    let text: String
    var body: some View {
        Text(text).font(DL.text(13, .semibold)).foregroundStyle(DL.ink)
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(DL.ink2)
    }
}

/// A section title on the page: display capitals, with an optional link at the far end.
struct G1SectionTitle: View {
    var title: String
    var link: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .font(DL.display(24))
                .foregroundStyle(DL.ink)
            Spacer(minLength: 8)
            if let link { G1LinkTail(text: link) }
        }
    }
}

/// The top line of a card: a mono label, with an optional link at the far end.
struct G1CardHeader: View {
    var label: String
    var link: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(label).dlLabel(10.5)
            Spacer(minLength: 8)
            if let link { G1LinkTail(text: link) }
        }
    }
}

/// A switch between two or three views of the same thing. The chosen one is an ink pill in a well.
struct G1Segmented: View {
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
        .padding(4)
        .background(Capsule().fill(DL.surface))
        .accessibilityElement(children: .combine)
    }
}

/// An on/off switch in ink. Gold stays the only colour on a screen.
struct G1Switch: View {
    var isOn: Bool = true

    var body: some View {
        Capsule()
            .fill(isOn ? DL.ink : DL.sunken)
            .frame(width: 52, height: 32)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? DL.onInk : DL.raised)
                    .frame(width: 26, height: 26)
                    .padding(3)
            }
            .accessibilityLabel(isOn ? "On" : "Off")
    }
}

/// The likes against the dislikes as a short split bar, for list rows.
struct G1ApprovalMini: View {
    var approval: Int
    var width: CGFloat = 56

    var body: some View {
        let gap: CGFloat = 2
        HStack(spacing: gap) {
            Capsule().fill(DL.ink).frame(width: (width - gap) * CGFloat(approval) / 100)
            Capsule().fill(DL.sunken)
        }
        .frame(width: width, height: 5)
    }
}

/// A mono label on a dark translucent capsule, for text that sits on game art.
struct G1MediaLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(DL.label(10.5))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(.black.opacity(0.4)))
    }
}
