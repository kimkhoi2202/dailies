import SwiftUI

// The Shop: your Dailie on a dark stage in the top half, turning in 3D, and the items under it.
// Tap an item to try it on. Shop sells; Closet holds what you own and equips it.

struct ShopScreen: View {
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var store = LiveStore.shared
    @State private var segment: Int
    @State private var shelf: Shelf
    @State private var selected: AvatarItem?
    @State private var sheetItem: AvatarItem?
    @State private var turn: Int

    enum Shelf: Hashable {
        case drops
        case slot(AvatarSlot)

        var title: String {
            switch self {
            case .drops: "Drops"
            case .slot(let slot): slot.title
            }
        }
    }

    /// `focus` is an item id to open on its sheet, "closet" to open the Closet, or nil.
    init(focus: String?) {
        let item = AvatarCatalog.item(focus)
        let closet = focus == "closet"
        let tryOn = AvatarCatalog.item(MockArgs.value("-tryon"))
        _segment = State(initialValue: closet ? 1 : 0)
        _shelf = State(initialValue: (item ?? tryOn).map { Shelf.slot($0.slot) } ?? (closet ? .slot(.hat) : .drops))
        _selected = State(initialValue: item ?? tryOn ?? (closet ? nil : Self.todaysDrops.first))
        _sheetItem = State(initialValue: item)
        _turn = State(initialValue: MockArgs.value("-shopturn") == nil ? 0 : 1)
    }

    static var todaysDrops: [AvatarItem] {
        let seconds = Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())
        return AvatarCatalog.drops(day: Int(seconds / 86400))
    }

    private var shelves: [Shelf] {
        segment == 0
            ? [.drops, .slot(.hat), .slot(.outfit), .slot(.gadget), .slot(.hair), .slot(.face)]
            : [.slot(.hat), .slot(.outfit), .slot(.gadget), .slot(.hair), .slot(.face), .slot(.body)]
    }

    private var shelfItems: [AvatarItem] {
        switch shelf {
        case .drops:
            return Self.todaysDrops
        case .slot(let slot):
            let items = AvatarCatalog.items(in: slot)
            return segment == 0 ? items.filter { !$0.isFree } : items.filter { avatars.owns($0) }
        }
    }

    /// In the Closet, a slot that can be left empty gets a None card first.
    private var removableSlot: AvatarSlot? {
        guard segment == 1, case .slot(let slot) = shelf, slot.removable else { return nil }
        return slot
    }

    private var previewLook: AvatarLook {
        guard let selected else { return avatars.look }
        return avatars.look.wearing(selected)
    }

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top, bottom = proxy.safeAreaInsets.bottom
            let stageHeight = top + min(430, proxy.size.height * 0.52)
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    stage(top: top, height: stageHeight)
                    panel(bottom: bottom)
                }
                floatingKey
                    .padding(.horizontal, 40)
                    .padding(.bottom, bottom + 12)
                if let item = sheetItem {
                    ShopItemSheet(item: item, bottom: bottom) {
                        withAnimation(.snappy(duration: 0.3)) { sheetItem = nil }
                    } onBought: {
                        selected = item
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .ignoresSafeArea()
        }
        .background(DL.body.ignoresSafeArea())
    }

    // MARK: Stage

    private func stage(top: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            AvatarRoom(floorAt: 0.76)
            AvatarStage(look: previewLook, shirt: avatars.shirt, control: .full, distance: 7.6, turnRequest: turn)
                .padding(.top, top + 34)
            caption
                .padding(.horizontal, DL.margin).padding(.bottom, 18)
                .allowsHitTesting(false)
            DLMediaButton(symbol: "arrow.triangle.2.circlepath", size: 42)
                .tap { turn += 1 }
                .accessibilityLabel("Turn around")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, DL.margin).padding(.bottom, 18)
            HStack(spacing: 10) {
                DLMediaButton(symbol: "chevron.left").goesBack().accessibilityLabel("Back")
                Text("SHOP").font(DL.display(30)).foregroundStyle(.white).tracking(1)
                Spacer()
                DLGoldChip(onMedia: true).opens(.gold)
            }
            .padding(.horizontal, DL.margin).padding(.top, top + 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .clipShape(DL.screenShape)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let item = selected {
                RarityTag(rarity: item.rarity, size: 10)
                Text(item.name.uppercased())
                    .font(DL.display(36)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .frame(maxWidth: 230, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(status(item)).font(DL.label(12)).foregroundStyle(Color(hex: "FFC531"))
                }
            } else {
                Text("YOUR DAILIE").font(DL.display(36)).foregroundStyle(.white)
                Text("TAP AN ITEM TO TRY IT ON").font(DL.label(12)).foregroundStyle(Color(hex: "FFC531"))
            }
        }
    }

    private func status(_ item: AvatarItem) -> String {
        if avatars.wears(item) { return "WEARING NOW" }
        if avatars.owns(item) { return "IN YOUR CLOSET" }
        if Self.todaysDrops.contains(item) { return "LEAVES IN \(store.resetIn.uppercased())" }
        return "IN THE SHOP"
    }

    // MARK: Items

    private func panel(bottom: CGFloat) -> some View {
        VStack(spacing: 12) {
            G2Segmented(items: ["Shop", "Closet"], selected: segment)
                .overlay {
                    HStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { index in
                            Color.clear.contentShape(Rectangle()).tap { switchTo(index) }
                        }
                    }
                }
                .padding(.horizontal, DL.margin)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(shelves, id: \.self) { entry in
                        let chosen = entry == shelf
                        Text(entry.title)
                            .font(DL.text(14, .semibold))
                            .foregroundStyle(chosen ? DL.onInk : DL.ink)
                            .padding(.horizontal, 13).frame(height: 34)
                            .background(Capsule().fill(chosen ? DL.ink : DL.surface))
                            .fixedSize()
                            .tap { withAnimation(.snappy(duration: 0.25)) { shelf = entry } }
                    }
                }
                .padding(.horizontal, DL.margin)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    if let slot = removableSlot {
                        noneCard(slot)
                    }
                    ForEach(shelfItems) { item in card(item) }
                }
                .padding(.horizontal, DL.margin)
                .padding(.bottom, bottom + 100)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 14)
    }

    private func switchTo(_ index: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            segment = index
            if index == 1, shelf == .drops { shelf = .slot(selected?.slot ?? .hat) }
            if index == 1, let item = selected, !avatars.owns(item) { selected = nil }
        }
    }

    private func choose(_ item: AvatarItem) {
        withAnimation(.snappy(duration: 0.25)) { selected = item }
        if segment == 1, avatars.owns(item), !avatars.wears(item) { avatars.equip(item, slot: item.slot) }
    }

    private func card(_ item: AvatarItem) -> some View {
        let owned = avatars.owns(item), wearing = avatars.wears(item), chosen = selected?.id == item.id
        let edge = item.rarity == .common ? DL.line : item.rarity.color
        return VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(hex: "2B2622"))
                    .overlay(alignment: .top) {
                        // a little shine strip in the rarity colour
                        Capsule().fill(item.rarity.color.opacity(0.85)).frame(height: 3).padding(.horizontal, 18).padding(.top, 4)
                    }
                ItemArt(item: item, shirt: avatars.shirt).padding(14)
                RarityTag(rarity: item.rarity, size: 7.5).padding(6).padding(.top, 4)
            }
            .aspectRatio(1, contentMode: .fit)
            Text(item.name).font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            HStack(spacing: 4) {
                if wearing {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(DL.success)
                    Text("WEARING").font(DL.label(10)).foregroundStyle(DL.ink2)
                } else if owned {
                    Text(item.isFree ? "FREE" : "OWNED").font(DL.label(10)).foregroundStyle(DL.ink2)
                } else {
                    DLCoin(size: 13)
                    Text("\(item.price)").font(DL.display(18)).foregroundStyle(DL.ink).monospacedDigit()
                }
            }
            .frame(height: 20)
        }
        .padding(7)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(chosen ? DL.gold : edge, lineWidth: chosen ? 3 : 1.5))
        .scaleEffect(chosen ? 1.03 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.45), value: chosen)
        .tap { choose(item) }
    }

    private func noneCard(_ slot: AvatarSlot) -> some View {
        let empty = avatars.look.item(in: slot) == nil
        return VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(hex: "2B2622"))
                .overlay { Image(systemName: "nosign").font(.system(size: 28, weight: .semibold)).foregroundStyle(Color(hex: "8A8579")) }
                .aspectRatio(1, contentMode: .fit)
            Text("None").font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            Text(empty ? "WEARING" : "TAKE OFF").font(DL.label(10)).foregroundStyle(DL.ink2).frame(height: 20)
        }
        .padding(7)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DL.line, lineWidth: 1.5))
        .tap {
            withAnimation(.snappy(duration: 0.25)) { selected = nil }
            avatars.equip(nil, slot: slot)
        }
    }

    @ViewBuilder private var floatingKey: some View {
        if let item = selected, sheetItem == nil {
            if !avatars.owns(item) {
                DLKey(style: .gold, radius: 22, depth: 6) {
                    HStack(spacing: 8) {
                        Text("BUY FOR").font(DL.display(26)).tracking(0.8)
                        DLCoin(size: 22)
                        Text("\(item.price)").font(DL.display(26)).monospacedDigit()
                    }
                }
                .frame(height: 64)
                .tap { withAnimation(.snappy(duration: 0.3)) { sheetItem = item } }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !avatars.wears(item) {
                DLTextKey(title: "Equip", symbol: "checkmark", style: .ink)
                    .tap { avatars.equip(item, slot: item.slot) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

/// The sheet for one item: a big look at it, its price, and the Buy key. After buying it celebrates.
struct ShopItemSheet: View {
    let item: AvatarItem
    let bottom: CGFloat
    var onClose: () -> Void
    var onBought: () -> Void
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var store = LiveStore.shared
    @State private var buying = false
    @State private var problem: String?
    @State private var bought = false
    @State private var burst = false
    @State private var raised = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: 12) {
                Capsule().fill(DL.ink3.opacity(0.5)).frame(width: 36, height: 5)
                if bought { celebration } else { details }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(DL.raised, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, bottom + 8)
            .offset(y: raised ? 0 : 600)
        }
        .onAppear { withAnimation(.snappy(duration: 0.32)) { raised = true } }
    }

    private var short: Int { max(0, item.price - store.s.balance) }

    private var art: some View {
        ZStack {
            Circle().fill(item.rarity.color.opacity(0.18))
            Circle().strokeBorder(item.rarity.color.opacity(0.6), lineWidth: 2)
            ItemArt(item: item, shirt: avatars.shirt).padding(34)
        }
        .frame(width: 170, height: 170)
    }

    private var details: some View {
        VStack(spacing: 10) {
            art
            RarityTag(rarity: item.rarity, size: 11)
            Text(item.name.uppercased()).font(DL.display(38)).foregroundStyle(DL.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(item.detail).font(DL.text(15)).foregroundStyle(DL.ink2).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                DLCoin(size: 18)
                Text("\(item.price) GOLD").font(DL.display(24)).foregroundStyle(DL.ink)
                Text("You have \(groupedNumber(store.s.balance))").font(DL.text(13)).foregroundStyle(DL.ink2).padding(.leading, 6)
            }
            if avatars.owns(item) {
                DLTextKey(title: "Equip", symbol: "checkmark", style: .ink).tap {
                    avatars.equip(item, slot: item.slot)
                    onBought()
                    onClose()
                }
            } else if short > 0 {
                Text("You need \(short) more gold.").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                buyKey.opacity(0.4).allowsHitTesting(false)
                HStack(spacing: 10) {
                    DLTextKey(title: "Play a game", symbol: "play.fill", style: .neutral)
                        .tap { LiveNav.shared.goToTab(0) }
                    DLTextKey(title: "Gold", symbol: "list.bullet", style: .neutral)
                        .tap { onClose(); LiveNav.shared.open(.gold) }
                }
            } else {
                buyKey.tap(buy)
            }
            if let problem {
                Text(problem).font(DL.text(14, .medium)).foregroundStyle(DL.danger)
            }
        }
    }

    private var buyKey: some View {
        DLKey(style: .gold, radius: 22, depth: 6) {
            HStack(spacing: 8) {
                Text(buying ? "BUYING" : "BUY FOR").font(DL.display(26)).tracking(0.8)
                if !buying {
                    DLCoin(size: 22)
                    Text("\(item.price)").font(DL.display(26)).monospacedDigit()
                }
            }
        }
        .frame(height: 64)
    }

    private func buy() {
        guard !buying else { return }
        buying = true
        problem = nil
        Task { @MainActor in
            let failure = await avatars.buy(item)
            buying = false
            if let failure {
                problem = failure
                return
            }
            onBought()
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { bought = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.05)) { burst = true }
        }
    }

    private var celebration: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<14, id: \.self) { index in
                    let angle = Double(index) / 14 * 2 * .pi
                    let colors = [Color(hex: "FFC531"), Color(hex: "1FA89A"), Color(hex: "7C5CFF"), Color(hex: "FF7AB6")]
                    Rectangle().fill(colors[index % colors.count])
                        .frame(width: 9, height: 9)
                        .offset(x: burst ? cos(angle) * 140 : 0, y: burst ? sin(angle) * 95 : 0)
                        .opacity(burst ? 0 : 1)
                }
                art.scaleEffect(bought ? 1 : 0.3)
            }
            Text("YOURS NOW").font(DL.display(40)).foregroundStyle(DL.ink)
            Text("\(item.name) is in your Closet.").font(DL.text(15)).foregroundStyle(DL.ink2)
            DLTextKey(title: "Equip now", symbol: "checkmark").tap {
                avatars.equip(item, slot: item.slot)
                onClose()
            }
            Text("Keep shopping").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                .padding(.vertical, 6)
                .tap(onClose)
        }
    }
}
