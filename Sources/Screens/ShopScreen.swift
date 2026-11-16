import SwiftUI

// The Shop: your Dailie small in its room at the top, and one long page under it. Shop has today's
// drops, bundles and every item by category. Closet shows what you own and what you wear.
// Tap anything to try it on. The floating key buys it, or puts it on when it is already yours.

struct ShopScreen: View {
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var store = LiveStore.shared
    @State private var segment: Int
    @State private var selected: AvatarItem?
    @State private var sheetItem: AvatarItem?
    @State private var sheetBundle: AvatarBundle?
    @State private var turn: Int
    @State private var pop = 0
    @State private var section: String?

    /// `focus` is an item id to open on its sheet, "closet" to open the Closet, or nil.
    init(focus: String?) {
        let item = AvatarCatalog.item(focus)
        let closet = focus == "closet"
        let tryOn = AvatarCatalog.item(MockArgs.value("-tryon"))
        _segment = State(initialValue: closet ? 1 : 0)
        _selected = State(initialValue: item ?? tryOn ?? (closet ? nil : Self.todaysDrops.first))
        _sheetItem = State(initialValue: item)
        _turn = State(initialValue: MockArgs.value("-shopturn") == nil ? 0 : 1)
    }

    static var todaysDrops: [AvatarItem] {
        let seconds = Date().timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT())
        return AvatarCatalog.drops(day: Int(seconds / 86400))
    }

    private static let shopSlots: [AvatarSlot] = [.hat, .gadget, .decor]
    private static let closetSlots: [AvatarSlot] = [.hat, .gadget, .decor]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    private struct ShopSection: Identifiable, Hashable {
        let id: String
        let title: String
    }

    private var sections: [ShopSection] {
        let slots = segment == 0 ? Self.shopSlots : Self.closetSlots
        let lead = segment == 0
            ? [ShopSection(id: "drops", title: "Drops"), ShopSection(id: "bundles", title: "Bundles")]
            : [ShopSection(id: "look", title: "Looks")]
        return lead + slots.map { ShopSection(id: Self.sectionID($0), title: $0.title) }
    }

    private static func sectionID(_ slot: AvatarSlot) -> String { "slot.\(slot.rawValue)" }

    private var previewLook: AvatarLook {
        guard let selected, selected.slot.worn else { return avatars.look }
        return avatars.look.wearing(selected)
    }

    /// The placed decor, plus the selected decor item while it is being tried.
    private var roomDecor: [String] {
        guard let selected, selected.slot == .decor, !avatars.decor.contains(selected.id) else { return avatars.decor }
        return avatars.decor + [selected.id]
    }

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top, bottom = proxy.safeAreaInsets.bottom
            let stageHeight = (proxy.size.height + top + bottom) * 0.38
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
                if let bundle = sheetBundle {
                    ShopBundleSheet(bundle: bundle, bottom: bottom) {
                        withAnimation(.snappy(duration: 0.3)) { sheetBundle = nil }
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
            AvatarRoom(floorAt: 0.78, decor: roomDecor, trophies: [], wall: avatars.wallColor)
            BitmojiFigure(look: previewLook, handle: Mock.handle, shirt: avatars.shirt)
                .padding(.top, top + 58)
                .padding(.bottom, 14)
                .padding(.leading, 150)
                .keyframeAnimator(initialValue: 1.0, trigger: pop) { content, scale in
                    content.scaleEffect(scale, anchor: .bottom)
                } keyframes: { _ in
                    SpringKeyframe(1.1, duration: 0.14)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
                }
            caption
                .padding(.leading, DL.margin).padding(.trailing, 70).padding(.bottom, 16)
                .allowsHitTesting(false)
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
        VStack(alignment: .leading, spacing: 4) {
            if let item = selected {
                RarityTag(rarity: item.rarity, size: 9)
                Text(item.name.uppercased())
                    .font(DL.display(30)).foregroundStyle(.white)
                    .lineLimit(2).minimumScaleFactor(0.6)
                    .frame(maxWidth: 190, alignment: .leading)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(status(item)).font(DL.label(11)).foregroundStyle(Color(hex: "FFC531"))
                }
            } else {
                Text("YOUR DAILIE").font(DL.display(30)).foregroundStyle(.white)
                Text("TAP AN ITEM TO TRY IT ON").font(DL.label(11)).foregroundStyle(Color(hex: "FFC531"))
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        .keyframeAnimator(initialValue: 1.0, trigger: pop) { content, scale in
            content.scaleEffect(scale, anchor: .bottomLeading)
        } keyframes: { _ in
            SpringKeyframe(1.06, duration: 0.12)
            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
        }
    }

    private func status(_ item: AvatarItem) -> String {
        if item.slot == .decor, avatars.wears(item) { return "IN YOUR ROOM" }
        if avatars.wears(item) { return "WEARING NOW" }
        if avatars.owns(item) { return "IN YOUR CLOSET" }
        if Self.todaysDrops.contains(item) { return "LEAVES IN \(store.resetIn.uppercased())" }
        return item.slot == .decor ? "TRYING IT IN YOUR ROOM" : "IN THE SHOP"
    }

    // MARK: Page

    private func panel(bottom: CGFloat) -> some View {
        ScrollViewReader { reader in
            VStack(spacing: 10) {
                G2Segmented(items: ["Shop", "Closet"], selected: segment)
                    .overlay {
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { index in
                                Color.clear.contentShape(Rectangle()).tap { switchTo(index, reader: reader) }
                            }
                        }
                    }
                    .padding(.horizontal, DL.margin)
                pills(reader)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if segment == 0 {
                            shopPage
                        } else {
                            closetPage(reader)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.top, 6)
                    .padding(.bottom, bottom + 112)
                }
                .scrollIndicators(.hidden)
                .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.3) { ids in
                    if let first = ids.first, first != section { section = first }
                }
            }
            .padding(.top, 12)
        }
    }

    private func pills(_ reader: ScrollViewProxy) -> some View {
        let current = section ?? sections.first?.id
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sections) { entry in
                    let chosen = entry.id == current
                    Text(entry.title)
                        .font(DL.text(14, .semibold))
                        .foregroundStyle(chosen ? DL.onInk : DL.ink)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Capsule().fill(chosen ? DL.ink : DL.surface))
                        .overlay(Capsule().strokeBorder(chosen ? Color.clear : DL.line))
                        .fixedSize()
                        .tap {
                            section = entry.id
                            withAnimation(.snappy(duration: 0.4)) { reader.scrollTo(entry.id, anchor: .top) }
                        }
                }
            }
            .padding(.horizontal, DL.margin)
            .animation(.snappy(duration: 0.2), value: current)
        }
    }

    private func header(_ title: String, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased()).font(DL.display(28)).foregroundStyle(DL.ink)
            Spacer(minLength: 8)
            Text(note).font(DL.label(11)).foregroundStyle(DL.ink2)
        }
        .padding(.horizontal, DL.margin)
    }

    private func switchTo(_ index: Int, reader: ScrollViewProxy, then target: String? = nil) {
        withAnimation(.snappy(duration: 0.25)) {
            segment = index
            section = nil
            if index == 1, let item = selected, !avatars.owns(item) { selected = nil }
        }
        let goal = target ?? (index == 0 ? "drops" : "look")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.snappy(duration: 0.4)) { reader.scrollTo(goal, anchor: .top) }
        }
    }

    private func choose(_ item: AvatarItem) {
        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { selected = item }
        pop += 1
    }

    // MARK: Shop

    @ViewBuilder private var shopPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("Today's drops", "LEAVES IN \(store.resetIn.uppercased())")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(Self.todaysDrops.enumerated()), id: \.element.id) { index, item in
                        dropCard(item, index: index)
                    }
                }
                .padding(.horizontal, DL.margin + 4).padding(.vertical, 18)
            }
            .scrollClipDisabled()
        }
        .id("drops")

        VStack(alignment: .leading, spacing: 12) {
            header("Bundles", "\(AvatarCatalog.bundles.count) SETS, 20% OFF")
            ForEach(AvatarCatalog.bundles) { bundle in bundleCard(bundle) }
        }
        .id("bundles")

        ForEach(Self.shopSlots, id: \.self) { slot in
            shopSection(slot).id(Self.sectionID(slot))
        }
    }

    private func dropCard(_ item: AvatarItem, index: Int) -> some View {
        let chosen = selected?.id == item.id
        let tilt = [-3.0, 2.5, -1.5][index % 3]
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                RarityTag(rarity: item.rarity, size: 9)
                Spacer()
                Text(item.slot.title.uppercased()).font(DL.label(10)).foregroundStyle(.white.opacity(0.6))
            }
            ZStack {
                Circle().fill(item.rarity.color.opacity(0.25))
                Circle().fill(.white.opacity(0.06)).padding(26)
                ItemArt(item: item, shirt: avatars.shirt).padding(24)
            }
            .frame(height: 150)
            Text(item.name.uppercased())
                .font(DL.display(26)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                priceLine(item, size: 24, ink: .white)
                Spacer()
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("LEAVES IN \(store.resetIn.uppercased())").font(DL.label(10)).foregroundStyle(Color(hex: "FFC531"))
            }
        }
        .padding(14)
        .frame(width: 210)
        .background {
            ZStack(alignment: .topLeading) {
                shape.fill(Color(hex: "2B2622"))
                shape.fill(LinearGradient(colors: [item.rarity.color.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                shape.fill(LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .center, endPoint: .bottom))
                Capsule().fill(.white.opacity(0.14)).frame(width: 70, height: 10)
                    .rotationEffect(.degrees(-20)).offset(x: 18, y: 14)
            }
        }
        .overlay(shape.strokeBorder(chosen ? DL.gold : item.rarity.color.opacity(0.8), lineWidth: chosen ? 4 : 2))
        .overlay(alignment: .topTrailing) {
            if index == 0 { sticker.offset(x: 12, y: -14) }
        }
        .rotationEffect(.degrees(chosen ? 0 : tilt))
        .scaleEffect(chosen ? 1.04 : 1)
        .animation(.spring(duration: 0.35, bounce: 0.45), value: chosen)
        .tap { choose(item) }
    }

    private var sticker: some View {
        VStack(spacing: 0) {
            Text("TODAY").font(DL.display(15))
            Text("ONLY").font(DL.display(15))
        }
        .foregroundStyle(.white)
        .frame(width: 58, height: 58)
        .background(Circle().fill(Color(hex: "FF6B57")))
        .background(Circle().fill(Color(hex: "C24A3A")).offset(y: 3))
        .rotationEffect(.degrees(14))
        .accessibilityHidden(true)
    }

    /// The gold price, or what the player already does with it.
    @ViewBuilder private func priceLine(_ item: AvatarItem, size: CGFloat, ink: Color) -> some View {
        if avatars.wears(item) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(DL.gold)
            Text(item.slot == .decor ? "PLACED" : "WEARING").font(DL.label(10)).foregroundStyle(ink.opacity(0.75))
        } else if avatars.owns(item) {
            Text(item.isFree ? "FREE" : "OWNED").font(DL.label(10)).foregroundStyle(ink.opacity(0.75))
        } else {
            DLCoin(size: size * 0.68)
            Text("\(item.price)").font(DL.display(size)).foregroundStyle(ink).monospacedDigit()
        }
    }

    private func bundleCard(_ bundle: AvatarBundle) -> some View {
        let items = bundle.items.compactMap { AvatarCatalog.item($0) }.filter { [.hat, .gadget, .decor].contains($0.slot) }
        let full = bundle.fullPrice(owned: avatars.owned)
        let price = bundle.price(owned: avatars.owned)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "2B2622"))
                        Circle().fill(item.rarity.color.opacity(0.2)).padding(6)
                        ItemArt(item: item, shirt: avatars.shirt).padding(9)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(alignment: .bottomTrailing) {
                        if avatars.owns(item) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 15, weight: .bold))
                                .foregroundStyle(DL.gold).padding(4)
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bundle.name.uppercased()).font(DL.display(26)).foregroundStyle(DL.ink)
                    Text(bundle.detail).font(DL.text(13)).foregroundStyle(DL.ink2)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if full == 0 {
                    Text("Owned").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(full)").font(DL.text(13, .semibold)).foregroundStyle(DL.ink3).strikethrough()
                        HStack(spacing: 5) {
                            DLCoin(size: 17)
                            Text("\(price)").font(DL.display(26)).foregroundStyle(DL.ink).monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(DL.surface, in: shape)
        .overlay(shape.strokeBorder(DL.line, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if full > 0 {
                Text("20% OFF").font(DL.label(10)).foregroundStyle(DL.onGold)
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(DL.gold))
                    .rotationEffect(.degrees(6))
                    .offset(x: 4, y: -9)
            }
        }
        .padding(.horizontal, DL.margin)
        .tap { withAnimation(.snappy(duration: 0.3)) { sheetBundle = bundle } }
    }

    private func shopSection(_ slot: AvatarSlot) -> some View {
        let items = AvatarCatalog.items(in: slot).filter { !$0.isFree }
        return VStack(alignment: .leading, spacing: 12) {
            header(slot.title, "\(items.count) ITEMS")
            LazyVGrid(columns: Self.columns, spacing: 10) {
                ForEach(items) { item in itemCard(item) }
            }
            .padding(.horizontal, DL.margin)
        }
    }

    private func itemCard(_ item: AvatarItem) -> some View {
        let chosen = selected?.id == item.id
        let edge = item.rarity == .common ? DL.line : item.rarity.color
        return VStack(alignment: .leading, spacing: 5) {
            itemTile(item)
            Text(item.name).font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            HStack(spacing: 4) { priceLine(item, size: 18, ink: DL.ink) }
                .frame(height: 20)
        }
        .padding(7)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(chosen ? DL.gold : edge, lineWidth: chosen ? 3 : 1.5))
        .scaleEffect(chosen ? 1.05 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: chosen)
        .tap { choose(item) }
    }

    /// The dark tile an item sits on: a soft glow in its rarity colour, one shine and one shade.
    private func itemTile(_ item: AvatarItem, tag: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(Color(hex: "2B2622"))
            shape.fill(RadialGradient(colors: [item.rarity.color.opacity(0.3), .clear], center: .center, startRadius: 4, endRadius: 52))
            shape.fill(LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom))
            Capsule().fill(.white.opacity(0.13)).frame(width: 34, height: 6)
                .rotationEffect(.degrees(-24)).offset(x: 46, y: 9)
            Group {
                ItemArt(item: item, shirt: avatars.shirt).padding(13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if tag, item.rarity != .common {
                RarityTag(rarity: item.rarity, size: 7.5).padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay(shape.strokeBorder(item.rarity.color.opacity(item.rarity == .common ? 0 : 0.55), lineWidth: 1.5))
    }

    // MARK: Closet

    @ViewBuilder private func closetPage(_ reader: ScrollViewProxy) -> some View {
        lookCard(reader).id("look")
        ForEach(Self.closetSlots, id: \.self) { slot in
            closetSection(slot, reader: reader).id(Self.sectionID(slot))
        }
    }

    /// Every look, as faces. Tapping one puts it on at once.
    private func lookCard(_ reader: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR LOOK").font(DL.display(28)).foregroundStyle(DL.ink)
                Spacer()
                Text("TAP ONE TO WEAR IT").font(DL.label(10)).foregroundStyle(DL.ink2)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 14) {
                ForEach(AvatarCatalog.items(in: .body)) { item in lookTile(item) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("ROOM COLOUR").font(DL.display(22)).foregroundStyle(DL.ink)
                Spacer()
            }
            .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AvatarStore.walls, id: \.hex) { wall in
                        let chosen = avatars.wall == wall.hex
                        VStack(spacing: 5) {
                            Circle().fill(wall.hex.isEmpty ? Color(hex: "2B2622") : Color(hex: wall.hex))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(chosen ? DL.gold : DL.line, lineWidth: chosen ? 3 : 1.5))
                            Text(wall.name).font(DL.text(11, .semibold)).foregroundStyle(DL.ink2)
                        }
                        .tap { withAnimation(.snappy(duration: 0.3)) { avatars.wall = wall.hex } }
                    }
                }
            }
        }
        .padding(16)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DL.cardRadius, style: .continuous).strokeBorder(DL.line, lineWidth: 1.5))
        .padding(.horizontal, DL.margin)
    }

    private func lookTile(_ item: AvatarItem) -> some View {
        let wearing = Bitmoji.name(avatars.look, handle: Mock.handle) == String(item.id.dropFirst(5))
        return VStack(spacing: 6) {
            ItemArt(item: item, shirt: avatars.shirt)
                .frame(width: 62, height: 62)
                .background(Color(hex: "FFC531").opacity(0.25), in: Circle())
                .overlay(Circle().strokeBorder(wearing ? DL.gold : DL.line, lineWidth: wearing ? 3.5 : 1.5))
                .overlay(alignment: .bottomTrailing) {
                    if wearing {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(DL.onGold, DL.gold).offset(x: 2, y: 2)
                    }
                }
            Text(item.name).font(DL.text(11, .semibold)).foregroundStyle(DL.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .tap {
            withAnimation(.snappy(duration: 0.25)) { selected = item }
            avatars.equip(item, slot: .body)
            pop += 1
        }
    }

    private func closetSection(_ slot: AvatarSlot, reader: ScrollViewProxy) -> some View {
        let items = AvatarCatalog.items(in: slot).filter { avatars.owns($0) }
        let note = slot == .decor
            ? "\(avatars.decor.count) OF \(AvatarCatalog.roomSpots) PLACED"
            : "\(items.count) OWNED"
        return VStack(alignment: .leading, spacing: 12) {
            header(slot.title, note)
            if items.isEmpty {
                emptyLine(slot, reader: reader)
            } else {
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    if slot.worn && slot.removable {
                        noneTile(slot)
                    }
                    ForEach(items) { item in closetTile(item) }
                }
                .padding(.horizontal, DL.margin)
            }
        }
    }

    private func emptyLine(_ slot: AvatarSlot, reader: ScrollViewProxy) -> some View {
        let count = AvatarCatalog.items(in: slot).filter { !$0.isFree }.count
        let line = slot == .decor
            ? "Your room is empty for now. The Shop has \(count) things to put in it."
            : "No \(slot.title.lowercased()) yet. The Shop has \(count) to try on."
        return VStack(alignment: .leading, spacing: 10) {
            Text(line).font(DL.text(15)).foregroundStyle(DL.ink2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Go to Shop").font(DL.text(15, .semibold))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(DL.goldText)
            .tap { switchTo(0, reader: reader, then: Self.sectionID(slot)) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DL.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(DL.line, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])))
        .padding(.horizontal, DL.margin)
    }

    private func closetTile(_ item: AvatarItem) -> some View {
        let on = avatars.wears(item)
        let chosen = selected?.id == item.id
        let decor = item.slot == .decor
        let hint = on ? (decor ? "PLACED" : "WEARING") : (decor ? "TAP TO PLACE" : "TAP TO WEAR")
        return VStack(alignment: .leading, spacing: 5) {
            itemTile(item, tag: !on)
            Text(item.name).font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            Text(hint).font(DL.label(9.5)).foregroundStyle(on ? DL.goldText : DL.ink3).frame(height: 18)
        }
        .padding(7)
        .background(on ? DL.goldWash : DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(on ? DL.gold : DL.line, lineWidth: on ? 3 : 1.5))
        .overlay(alignment: .topTrailing) {
            if on { checkBadge.offset(x: 5, y: -5) }
        }
        .scaleEffect(chosen ? 1.05 : 1)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: chosen)
        .animation(.spring(duration: 0.3, bounce: 0.5), value: on)
        .tap { wear(item) }
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(DL.onGold)
            .frame(width: 26, height: 26)
            .background(Circle().fill(DL.gold))
            .background(Circle().fill(DL.goldLip).offset(y: 2))
            .accessibilityLabel("Wearing")
    }

    private func noneTile(_ slot: AvatarSlot) -> some View {
        let empty = avatars.look.item(in: slot) == nil
        return VStack(alignment: .leading, spacing: 5) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(hex: "2B2622"))
                .overlay { Image(systemName: "nosign").font(.system(size: 28, weight: .semibold)).foregroundStyle(Color(hex: "8A8579")) }
                .aspectRatio(1, contentMode: .fit)
            Text("None").font(DL.text(12.5, .semibold)).foregroundStyle(DL.ink).lineLimit(1)
            Text(empty ? "WEARING" : "TAKE OFF").font(DL.label(9.5)).foregroundStyle(empty ? DL.goldText : DL.ink3).frame(height: 18)
        }
        .padding(7)
        .background(empty ? DL.goldWash : DL.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(empty ? DL.gold : DL.line, lineWidth: empty ? 3 : 1.5))
        .overlay(alignment: .topTrailing) {
            if empty { checkBadge.offset(x: 5, y: -5) }
        }
        .tap {
            withAnimation(.snappy(duration: 0.25)) { selected = nil }
            avatars.equip(nil, slot: slot)
            pop += 1
        }
    }

    /// In the Closet a tap puts the item on, or places or removes decor.
    private func wear(_ item: AvatarItem) {
        if item.slot == .decor {
            avatars.toggleDecor(item)
        } else if !avatars.wears(item) {
            avatars.use(item)
        }
        choose(item)
    }

    static func skin(_ id: String) -> Color {
        switch id {
        case "body.porcelain": Color(hex: "FFE3CC")
        case "body.peach": Color(hex: "F7C9A3")
        case "body.honey": Color(hex: "E0A86E")
        case "body.umber": Color(hex: "A9714A")
        case "body.cocoa": Color(hex: "6B4430")
        case "body.mint": Color(hex: "9BE6CF")
        case "body.sky": Color(hex: "A8CCFF")
        case "body.lilac": Color(hex: "C9B8FF")
        case "body.coral": Color(hex: "FF9F8F")
        case "body.gold": Color(hex: "FFD25A")
        default: Color(hex: "F7C9A3")
        }
    }

    // MARK: Key

    @ViewBuilder private var floatingKey: some View {
        if let item = selected, sheetItem == nil, sheetBundle == nil {
            if !avatars.owns(item) {
                DLKey(style: .gold, radius: 22, depth: 6) {
                    HStack(spacing: 8) {
                        Text("BUY FOR").font(DL.display(26)).tracking(0.8)
                        DLCoin(size: 22)
                        Text("\(item.price)").font(DL.display(26)).monospacedDigit()
                    }
                }
                .frame(height: 64)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .tap { withAnimation(.snappy(duration: 0.3)) { sheetItem = item } }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !avatars.wears(item) {
                DLTextKey(title: item.slot == .decor ? "Place in room" : "Equip",
                          symbol: item.slot == .decor ? "sofa.fill" : "checkmark", style: .ink)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .tap {
                        avatars.use(item)
                        pop += 1
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

/// A body colour as a round swatch: a flat fill with one shade at the lower right and one highlight.
private struct ShopSwatch: View {
    var color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(color).overlay(Circle().fill(.black.opacity(0.2)))
            Circle().fill(color).padding(.trailing, 5).padding(.bottom, 6)
            Ellipse().fill(.white.opacity(0.55))
                .frame(width: 12, height: 7)
                .rotationEffect(.degrees(-30))
                .offset(x: 9, y: 9)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// The card that rises from the bottom for the item and bundle sheets.
private struct ShopSheet<Content: View>: View {
    let bottom: CGFloat
    var onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var raised = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(spacing: 12) {
                Capsule().fill(DL.ink3.opacity(0.5)).frame(width: 36, height: 5)
                content()
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background(DL.raised, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 8)
            .padding(.bottom, bottom + 8)
            .offset(y: raised ? 0 : 700)
        }
        .onAppear { withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { raised = true } }
    }
}

private let shopConfettiColors: [Color] = [Color(hex: "FFC531"), Color(hex: "1FA89A"), Color(hex: "7C5CFF"), Color(hex: "FF7AB6"), Color(hex: "FF6B57")]

/// One piece of the burst after buying: it flies out from the middle and fades.
private struct ShopConfetti: View {
    let index: Int
    let burst: Bool

    var body: some View {
        let angle = Double(index) / 16.0 * 2.0 * Double.pi
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(shopConfettiColors[index % shopConfettiColors.count])
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(burst ? Double(index) * 40 : 0))
            .offset(x: burst ? CGFloat(cos(angle) * 150) : 0, y: burst ? CGFloat(sin(angle) * 100) : 0)
            .opacity(burst ? 0 : 1)
    }
}

/// The gold Buy key, with the price after a coin.
private struct ShopBuyKey: View {
    let price: Int
    let buying: Bool

    var body: some View {
        DLKey(style: .gold, radius: 22, depth: 6) {
            HStack(spacing: 8) {
                Text(buying ? "BUYING" : "BUY FOR").font(DL.display(26)).tracking(0.8)
                if !buying {
                    DLCoin(size: 22)
                    Text("\(price)").font(DL.display(26)).monospacedDigit()
                }
            }
        }
        .frame(height: 64)
    }
}

/// What shows when the player is short of gold: how much, and two ways to get more.
private struct ShopShortOfGold: View {
    let short: Int
    let price: Int
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("You need \(short) more gold.").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
            ShopBuyKey(price: price, buying: false).opacity(0.4).allowsHitTesting(false)
            HStack(spacing: 10) {
                DLTextKey(title: "Play a game", symbol: "play.fill", style: .neutral)
                    .tap { onClose(); LiveNav.shared.goToTab(0) }
                DLTextKey(title: "Gold", symbol: "list.bullet", style: .neutral)
                    .tap { onClose(); LiveNav.shared.open(.gold) }
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

    var body: some View {
        ShopSheet(bottom: bottom, onClose: onClose) {
            if bought { celebration } else { details }
        }
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
                DLTextKey(title: item.slot == .decor ? "Place in room" : "Equip", symbol: "checkmark", style: .ink).tap {
                    avatars.use(item)
                    onBought()
                    onClose()
                }
            } else if short > 0 {
                ShopShortOfGold(short: short, price: item.price, onClose: onClose)
            } else {
                ShopBuyKey(price: item.price, buying: buying).tap(buy)
            }
            if let problem {
                Text(problem).font(DL.text(14, .medium)).foregroundStyle(DL.danger).multilineTextAlignment(.center)
            }
        }
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
                ForEach(0..<16, id: \.self) { index in ShopConfetti(index: index, burst: burst) }
                art.scaleEffect(bought ? 1 : 0.3)
            }
            Text("YOURS NOW").font(DL.display(40)).foregroundStyle(DL.ink)
            Text(item.slot == .decor ? "\(item.name) is ready for your room." : "\(item.name) is in your Closet.")
                .font(DL.text(15)).foregroundStyle(DL.ink2)
            DLTextKey(title: item.slot == .decor ? "Place in room" : "Equip now", symbol: "checkmark").tap {
                avatars.use(item)
                onClose()
            }
            Text("Keep shopping").font(DL.text(15, .semibold)).foregroundStyle(DL.ink2)
                .padding(.vertical, 6)
                .tap(onClose)
        }
    }
}

/// The sheet for a bundle: its items, the struck full price, the bundle price and the Buy key.
struct ShopBundleSheet: View {
    let bundle: AvatarBundle
    let bottom: CGFloat
    var onClose: () -> Void
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var store = LiveStore.shared
    @State private var buying = false
    @State private var problem: String?
    @State private var bought = false
    @State private var burst = false

    var body: some View {
        ShopSheet(bottom: bottom, onClose: onClose) {
            if bought { celebration } else { details }
        }
    }

    private var items: [AvatarItem] { bundle.items.compactMap { AvatarCatalog.item($0) }.filter { [.hat, .gadget, .decor].contains($0.slot) } }
    private var price: Int { bundle.price(owned: avatars.owned) }
    private var full: Int { bundle.fullPrice(owned: avatars.owned) }
    private var short: Int { max(0, price - store.s.balance) }

    private var art: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 10), count: 2), spacing: 10) {
            ForEach(items) { item in
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "2B2622"))
                    Circle().fill(item.rarity.color.opacity(0.25)).padding(8)
                    ItemArt(item: item, shirt: avatars.shirt).padding(14)
                }
                .frame(width: 84, height: 84)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(item.rarity.color.opacity(item.rarity == .common ? 0.2 : 0.7), lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    if avatars.owns(item) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold))
                            .foregroundStyle(DL.gold).padding(5)
                    }
                }
            }
        }
        .frame(width: 180)
    }

    private var details: some View {
        VStack(spacing: 10) {
            art
            Text(bundle.name.uppercased()).font(DL.display(38)).foregroundStyle(DL.ink)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(bundle.detail).font(DL.text(15)).foregroundStyle(DL.ink2).multilineTextAlignment(.center)
            if full == 0 {
                Text("You own all of it.").font(DL.text(15, .semibold)).foregroundStyle(DL.ink)
                DLTextKey(title: "Close", style: .ink).tap(onClose)
            } else {
                HStack(spacing: 8) {
                    Text("\(full)").font(DL.text(16, .semibold)).foregroundStyle(DL.ink3).strikethrough()
                    DLCoin(size: 18)
                    Text("\(price) GOLD").font(DL.display(24)).foregroundStyle(DL.ink)
                    Text("You have \(groupedNumber(store.s.balance))").font(DL.text(13)).foregroundStyle(DL.ink2).padding(.leading, 4)
                }
                if short > 0 {
                    ShopShortOfGold(short: short, price: price, onClose: onClose)
                } else {
                    ShopBuyKey(price: price, buying: buying).tap(buy)
                }
            }
            if let problem {
                Text(problem).font(DL.text(14, .medium)).foregroundStyle(DL.danger).multilineTextAlignment(.center)
            }
        }
    }

    private func buy() {
        guard !buying else { return }
        buying = true
        problem = nil
        Task { @MainActor in
            let failure = await avatars.buy(bundle)
            buying = false
            if let failure {
                problem = failure
                return
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { bought = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.05)) { burst = true }
        }
    }

    private var celebration: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<16, id: \.self) { index in ShopConfetti(index: index, burst: burst) }
                art.scaleEffect(bought ? 1 : 0.3)
            }
            Text("YOURS NOW").font(DL.display(40)).foregroundStyle(DL.ink)
            Text("Everything in \(bundle.name) is in your Closet.").font(DL.text(15)).foregroundStyle(DL.ink2)
                .multilineTextAlignment(.center)
            DLTextKey(title: "Done", symbol: "checkmark").tap(onClose)
        }
    }
}
