import SwiftUI

// SPEND: the one sheet a game may raise to ask for gold. It has two states. Either the balance
// covers the price, or you are still saving. Neither one sells anything: gold packs are on Your gold.

enum G1SpendData {
    /// Slow slab, 8 gold.
    static let boost = Mock.spendItem
    /// Gilded tower, 500 gold.
    static let skin = Mock.shop[4]
    static let game = Mock.tippyTower
}

/// What is on offer: its symbol in a tile, its name and what it does.
struct G1SpendItemHeader: View {
    let item: MockShopItem

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(DL.ink)
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DL.body))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title.uppercased())
                    .font(DL.display(38))
                    .foregroundStyle(DL.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(item.detail)
                    .font(DL.text(15))
                    .foregroundStyle(DL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The sheet's top line: which game the gold is being spent in, and a way out.
struct G1SpendSheetBar: View {
    var label: String

    var body: some View {
        HStack {
            Text(label).dlLabel(10.5)
            Spacer()
        }
        .frame(height: 36)
    }
}

/// A figure under a mono label. The coin can lead it.
struct G1Figure: View {
    var label: String
    var value: String
    var coin: Bool = false
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label).dlLabel(10.5)
            HStack(alignment: .center, spacing: 8) {
                if coin { DLCoin(size: 26) }
                Text(value).font(DL.display(44)).foregroundStyle(DL.ink).monospacedDigit()
            }
            .frame(height: 44)
        }
    }
}

private extension MockShopItem {
    /// "Spend in Tippy Tower"
    var spendLabel: String {
        let game = Mock.games.first { $0.kind == self.game } ?? G1SpendData.game
        return "Spend in \(game.title)"
    }
}

private extension View {
    /// The inset panel that holds a spend sheet's figures.
    func g1FiguresPanel() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(DL.body))
    }
}

/// The balance covers it: Slow slab for 8 gold.
struct G1SpendScreen: View {
    var item: MockShopItem = G1SpendData.boost

    var body: some View {
        DLSheet(height: 396) {
            GameScreen(hint: nil)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                G1SpendSheetBar(label: item.spendLabel)
                G1SpendItemHeader(item: item).padding(.top, 10)
                HStack(alignment: .center, spacing: 0) {
                    G1Figure(label: "Price", value: "\(item.price)", coin: true)
                    Spacer(minLength: 12)
                    DL.line.frame(width: 1, height: 48)
                    G1Figure(label: "Balance after", value: "\(Mock.balance - item.price)")
                        .padding(.leading, 18)
                        .frame(width: 164, alignment: .leading)
                }
                .g1FiguresPanel()
                .padding(.top, 18)
                DLTextKey(title: "Spend \(item.price) gold")
                    .padding(.top, 16)
                    .tap(buy)
                Text("You collect gold by playing. Packs are on Your gold.")
                    .font(DL.text(13))
                    .foregroundStyle(DL.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 20)
        }
    }

    private func buy() {
        guard LiveStore.shared.spend(item) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        LiveNav.shared.back()
        LiveNav.shared.say("\(item.title) is yours")
    }
}

/// Not enough yet: Gilded tower costs 500 and the balance is 412. No pressure and no offers.
struct G1SpendSavingScreen: View {
    var item: MockShopItem = G1SpendData.skin

    var body: some View {
        DLSheet(height: 444) {
            GameScreen(hint: nil)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                G1SpendSheetBar(label: item.spendLabel)
                G1SpendItemHeader(item: item).padding(.top, 10)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom) {
                        G1Figure(label: "Price", value: "\(item.price)", coin: true)
                        Spacer()
                        G1Figure(label: "Your balance", value: "\(Mock.balance)", alignment: .trailing)
                    }
                    DLMeter(value: Double(Mock.balance), total: Double(item.price), height: 10)
                    Text("\(item.price - Mock.balance) to go. \(Mock.savingEta).")
                        .font(DL.text(15, .semibold))
                        .foregroundStyle(DL.ink)
                }
                .g1FiguresPanel()
                .padding(.top, 18)
                DLTextKey(title: "Keep saving", style: .ink)
                    .padding(.top, 16)
                    .goesBack()
                HStack(spacing: 7) {
                    Image(systemName: "pin.fill").font(.system(size: 13, weight: .semibold))
                    Text("Pin as my saving goal").font(DL.text(15, .semibold))
                }
                .foregroundStyle(DL.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentShape(Rectangle())
                .tap {
                    LiveNav.shared.back()
                    LiveNav.shared.say("Pinned as your saving goal")
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
    }
}

/// The spend sheet in the app. It buys when the balance covers the price, and shows the saving state when it does not.
struct LiveSpendScreen: View {
    let item: MockShopItem
    @ObservedObject private var live = LiveStore.shared

    var body: some View {
        if live.s.balance >= item.price {
            G1SpendScreen(item: item)
        } else {
            G1SpendSavingScreen(item: item)
        }
    }
}
