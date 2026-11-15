import SwiftUI

// GOLD HISTORY, the ledger: every gold that came in, every gold that went out, and how far each
// studio is toward its limit for the day.

enum G2HistoryData {
    /// Today's rows. A row from today is stamped with a clock time or "Just now".
    static var today: [MockTransaction] {
        Mock.transactions.filter { $0.time == "Just now" || $0.time.contains(":") }
    }
    static var collectedToday: Int { today.map(\.amount).filter { $0 > 0 }.reduce(0, +) }
    static var spentToday: Int { today.map(\.amount).filter { $0 < 0 }.reduce(0, +) }
}

struct G2HistoryScreen: View {
    @ObservedObject private var live = LiveStore.shared
    /// 0 = today, 1 = everything
    @State private var segment = 0

    var body: some View {
        DLTabs(selected: 0) {
            DLPage(spacing: 12) {
                DLNavBar(title: "Gold history")
                balanceRow
                G2Segmented(items: ["Today", "All"], selected: segment)
                    .overlay {
                        // The control only draws itself. A clear target over each half takes the tap.
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { index in
                                Color.clear.contentShape(Rectangle()).tap { segment = index }
                            }
                        }
                    }
                ledger
                studioLimits
            }
        }
    }

    private var balanceRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Balance").dlLabel(10.5)
                HStack(alignment: .center, spacing: 10) {
                    DLCoin(size: 32)
                    Text(groupedNumber(Mock.balance)).font(DL.display(72)).foregroundStyle(DL.ink)
                }
                .frame(height: 64)
            }
            Spacer(minLength: 8)
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow(alignment: .firstTextBaseline) {
                    Text("Collected today").dlLabel(10)
                    DLAmount(amount: G2HistoryData.collectedToday, size: 24)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Spent today").dlLabel(10)
                    DLAmount(amount: G2HistoryData.spentToday, size: 24)
                }
            }
            .padding(.bottom, 2)
        }
        .padding(.top, 2)
    }

    private var ledger: some View {
        let entries = segment == 0 ? G2HistoryData.today : Mock.transactions
        return VStack(spacing: 0) {
            ForEach(entries.indices, id: \.self) { index in
                let entry = entries[index]
                if index > 0 { DLDivider(inset: 56) }
                HStack(spacing: 12) {
                    DLThumb(game: Mock.g2Game(for: entry.game), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(DL.text(16, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
                        Text(entry.detail).font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: -2) {
                        DLAmount(amount: entry.amount, size: 24)
                        Text(entry.time).dlLabel(10, color: DL.ink3)
                    }
                }
                .padding(.vertical, 7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .dlCard(padding: 0)
    }

    private var studioLimits: some View {
        let studios = Mock.studioCapsToday
        return VStack(alignment: .leading, spacing: 12) {
            Text("Today's limits by studio").dlLabel(10.5)
            ForEach(studios.indices, id: \.self) { index in
                let entry = studios[index]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.studio).font(DL.text(15, .semibold)).foregroundStyle(DL.ink).fixedSize()
                        Text(entry.games).font(DL.text(13)).foregroundStyle(DL.ink2).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(entry.earned) of \(Mock.perStudioDailyCap)").dlLabel(10).fixedSize()
                    }
                    DLMeter(value: Double(entry.earned), total: Double(Mock.perStudioDailyCap))
                }
            }
        }
        .dlCard()
    }
}
