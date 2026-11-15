import Foundation

// The avatar catalog, the same list as convex/items.ts. The server decides prices and ownership;
// the app uses this list to draw items and show their prices.

enum AvatarSlot: String, CaseIterable, Codable {
    case body, face, hair, hat, outfit, gadget, decor

    var title: String {
        switch self {
        case .body: "Looks"
        case .face: "Faces"
        case .hair: "Hair"
        case .hat: "Hats"
        case .outfit: "Outfits"
        case .gadget: "Gadgets"
        case .decor: "Room"
        }
    }

    /// Body and face are never empty. The rest can be taken off.
    var removable: Bool { self != .body && self != .face }

    /// Room decor is placed in the room, not worn.
    var worn: Bool { self != .decor }
}

enum AvatarRarity: String, Codable {
    case common, rare, epic, legendary

    var label: String { rawValue.uppercased() }
}

struct AvatarItem: Identifiable, Hashable {
    let id: String
    let slot: AvatarSlot
    let name: String
    let price: Int
    let rarity: AvatarRarity
    let detail: String

    var isFree: Bool { price == 0 }
}

/// Items sold together. Owned items are left out of the price, and the rest cost 20 percent less.
struct AvatarBundle: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let items: [String]

    static let discount = 0.8

    func price(owned: Set<String>) -> Int {
        let full = items.compactMap { AvatarCatalog.item($0) }.filter { !owned.contains($0.id) }.reduce(0) { $0 + $1.price }
        return Int((Double(full) * Self.discount).rounded(.down))
    }

    func fullPrice(owned: Set<String>) -> Int {
        items.compactMap { AvatarCatalog.item($0) }.filter { !owned.contains($0.id) }.reduce(0) { $0 + $1.price }
    }
}

/// What a Dailie wears: one item id per slot.
struct AvatarLook: Codable, Equatable, Hashable {
    var body: String
    var face: String
    var hair: String?
    var hat: String?
    var outfit: String?
    var gadget: String?

    func item(in slot: AvatarSlot) -> String? {
        switch slot {
        case .body: body
        case .face: face
        case .hair: hair
        case .hat: hat
        case .outfit: outfit
        case .gadget: gadget
        case .decor: nil
        }
    }

    /// This look with one slot changed. nil takes the item off, where the slot allows it.
    func with(_ slot: AvatarSlot, _ id: String?) -> AvatarLook {
        var next = self
        switch slot {
        case .body: if let id { next.body = id }
        case .face: if let id { next.face = id }
        case .hair: next.hair = id
        case .hat: next.hat = id
        case .outfit: next.outfit = id
        case .gadget: next.gadget = id
        case .decor: break
        }
        return next
    }

    func wearing(_ item: AvatarItem) -> AvatarLook { with(item.slot, item.id) }

    /// A player's look before they pick one: a character picked from the handle.
    static func starter(handle: String) -> AvatarLook {
        let bodies = [Bitmoji.character(handle: handle)]
        let hair = ["hair.short", "hair.bob", "hair.spiky", "hair.bun"]
        var sum = 0
        for unit in handle.utf16 { sum = (sum * 31 + Int(unit)) % 100003 }
        return AvatarLook(body: bodies[sum % bodies.count], face: "face.happy",
                          hair: hair[(sum / 7) % hair.count], outfit: "outfit.tee")
    }
}

enum AvatarCatalog {
    static let items: [AvatarItem] = [
        AvatarItem(id: "char.me", slot: .body, name: "Grey Hoodie", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.khoi", slot: .body, name: "Specs", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.ben", slot: .body, name: "Ginger Flannel", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.dylan", slot: .body, name: "Orange Tee", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.nyx", slot: .body, name: "Purple Punk", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.kiko", slot: .body, name: "Pink Pigtails", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.vanessa", slot: .body, name: "Cream Cardigan", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.kaz", slot: .body, name: "Puffer Vest", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.devon", slot: .body, name: "Varsity", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.noor", slot: .body, name: "Green Hijab", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.tofu", slot: .body, name: "Silver Hair", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.juno", slot: .body, name: "Curly Denim", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.sam", slot: .body, name: "Sweater Vest", price: 0, rarity: .common, detail: "A whole look, head to toe."),
        AvatarItem(id: "char.blond", slot: .body, name: "Blond Tee", price: 0, rarity: .common, detail: "A whole look, head to toe."),

        AvatarItem(id: "face.happy", slot: .face, name: "Happy", price: 0, rarity: .common, detail: "Big eyes and a big smile."),
        AvatarItem(id: "face.smirk", slot: .face, name: "Smirk", price: 0, rarity: .common, detail: "You know something they do not."),
        AvatarItem(id: "face.wink", slot: .face, name: "Wink", price: 0, rarity: .common, detail: "One eye on the leaderboard."),
        AvatarItem(id: "face.determined", slot: .face, name: "Determined", price: 0, rarity: .common, detail: "Focus brows for the last ten floors."),
        AvatarItem(id: "face.sleepy", slot: .face, name: "Sleepy", price: 50, rarity: .common, detail: "One more round, then bed."),
        AvatarItem(id: "face.shades", slot: .face, name: "Cool Shades", price: 150, rarity: .rare, detail: "Ink shades with a gold glint."),
        AvatarItem(id: "face.stars", slot: .face, name: "Star Eyes", price: 280, rarity: .epic, detail: "For when the perfect drop lands."),

        AvatarItem(id: "hair.short", slot: .hair, name: "Short Crop", price: 0, rarity: .common, detail: "Neat on top, easy every day."),
        AvatarItem(id: "hair.bob", slot: .hair, name: "Bob", price: 0, rarity: .common, detail: "A sharp ink bob."),
        AvatarItem(id: "hair.spiky", slot: .hair, name: "Spiky", price: 0, rarity: .common, detail: "Four spikes, always up."),
        AvatarItem(id: "hair.bun", slot: .hair, name: "Top Bun", price: 0, rarity: .common, detail: "Up and out of the way."),
        AvatarItem(id: "hair.buzz", slot: .hair, name: "Buzz", price: 0, rarity: .common, detail: "Nothing to get in your eyes."),
        AvatarItem(id: "hair.curly", slot: .hair, name: "Curly", price: 60, rarity: .common, detail: "Bouncy auburn curls."),
        AvatarItem(id: "hair.long", slot: .hair, name: "Long Lilac", price: 90, rarity: .common, detail: "Lilac hair down to the shoulders."),
        AvatarItem(id: "hair.mohawk", slot: .hair, name: "Pink Mohawk", price: 140, rarity: .rare, detail: "Loud, proud and pink."),

        AvatarItem(id: "hat.party", slot: .hat, name: "Party Hat", price: 60, rarity: .common, detail: "Striped, with a gold pom."),
        AvatarItem(id: "hat.beanie", slot: .hat, name: "Beanie", price: 70, rarity: .common, detail: "A teal knit with a cream pom."),
        AvatarItem(id: "hat.cap", slot: .hat, name: "Cap", price: 80, rarity: .common, detail: "A teal cap with a gold bill."),
        AvatarItem(id: "hat.catears", slot: .hat, name: "Cat Ears", price: 150, rarity: .rare, detail: "Ears that hear a combo coming."),
        AvatarItem(id: "hat.headset", slot: .hat, name: "Gamer Headset", price: 180, rarity: .rare, detail: "Gold cups and a mic for callouts."),
        AvatarItem(id: "hat.halo", slot: .hat, name: "Halo", price: 300, rarity: .epic, detail: "A floating gold ring. Very well behaved."),
        AvatarItem(id: "hat.wizard", slot: .hat, name: "Wizard Hat", price: 350, rarity: .epic, detail: "Purple, tall and full of stars."),
        AvatarItem(id: "hat.crown", slot: .hat, name: "Crown", price: 800, rarity: .legendary, detail: "Solid gold with three gems."),
        AvatarItem(id: "hat.bucket", slot: .hat, name: "Bucket Hat", price: 70, rarity: .common, detail: "Soft cream bucket hat for sunny days."),
        AvatarItem(id: "hat.chef", slot: .hat, name: "Chef Hat", price: 90, rarity: .common, detail: "Tall, white and ready to cook."),
        AvatarItem(id: "hat.bunny", slot: .hat, name: "Bunny Ears", price: 120, rarity: .rare, detail: "Long ears with pink insides."),
        AvatarItem(id: "hat.flowers", slot: .hat, name: "Flower Crown", price: 140, rarity: .rare, detail: "A ring of pink and gold flowers."),
        AvatarItem(id: "hat.pirate", slot: .hat, name: "Pirate Hat", price: 260, rarity: .epic, detail: "Ink tricorn with a gold trim."),
        AvatarItem(id: "hat.viking", slot: .hat, name: "Viking Helmet", price: 380, rarity: .epic, detail: "Silver dome with two cream horns."),

        AvatarItem(id: "outfit.tee", slot: .outfit, name: "Signature Tee", price: 0, rarity: .common, detail: "A tee in your own colour."),
        AvatarItem(id: "outfit.overalls", slot: .outfit, name: "Overalls", price: 70, rarity: .common, detail: "Teal overalls over a cream tee."),
        AvatarItem(id: "outfit.sweater", slot: .outfit, name: "Cozy Sweater", price: 80, rarity: .common, detail: "Coral knit with cream stripes."),
        AvatarItem(id: "outfit.hoodie", slot: .outfit, name: "Gold Hoodie", price: 90, rarity: .common, detail: "Our gold, with a hood and a pocket."),
        AvatarItem(id: "outfit.tracksuit", slot: .outfit, name: "Tracksuit", price: 140, rarity: .rare, detail: "Teal with cream side stripes."),
        AvatarItem(id: "outfit.varsity", slot: .outfit, name: "Varsity Jacket", price: 160, rarity: .rare, detail: "Purple and cream with a gold D."),
        AvatarItem(id: "outfit.cape", slot: .outfit, name: "Hero Cape", price: 200, rarity: .rare, detail: "A red cape and a gold star."),
        AvatarItem(id: "outfit.tux", slot: .outfit, name: "Tux", price: 320, rarity: .epic, detail: "Ink tux and a gold bow tie."),
        AvatarItem(id: "outfit.astronaut", slot: .outfit, name: "Astronaut Suit", price: 900, rarity: .legendary, detail: "White suit, gold panel, air for days."),
        AvatarItem(id: "outfit.pajamas", slot: .outfit, name: "Star Pajamas", price: 80, rarity: .common, detail: "Sky blue with little gold stars."),
        AvatarItem(id: "outfit.denim", slot: .outfit, name: "Denim Jacket", price: 90, rarity: .common, detail: "Blue denim over a cream tee."),
        AvatarItem(id: "outfit.jersey", slot: .outfit, name: "Gold Jersey", price: 120, rarity: .rare, detail: "Number 1, in our gold."),
        AvatarItem(id: "outfit.puffer", slot: .outfit, name: "Puffer Jacket", price: 150, rarity: .rare, detail: "Puffy coral jacket, warm all day."),
        AvatarItem(id: "outfit.dino", slot: .outfit, name: "Dino Onesie", price: 340, rarity: .epic, detail: "Green onesie with a row of spikes."),

        AvatarItem(id: "gadget.phone", slot: .gadget, name: "Phone", price: 50, rarity: .common, detail: "For one more round on the bus."),
        AvatarItem(id: "gadget.controller", slot: .gadget, name: "Controller", price: 60, rarity: .common, detail: "An ink pad with gold and teal buttons."),
        AvatarItem(id: "gadget.joystick", slot: .gadget, name: "Joystick", price: 70, rarity: .common, detail: "Arcade stick with a red ball top."),
        AvatarItem(id: "gadget.boba", slot: .gadget, name: "Bubble Tea", price: 80, rarity: .common, detail: "Milk tea with pearls."),
        AvatarItem(id: "gadget.mic", slot: .gadget, name: "Microphone", price: 130, rarity: .rare, detail: "For the post-game speech."),
        AvatarItem(id: "gadget.trophy", slot: .gadget, name: "Trophy Cup", price: 260, rarity: .epic, detail: "A gold cup to hold up high."),
        AvatarItem(id: "gadget.goldpad", slot: .gadget, name: "Golden Controller", price: 700, rarity: .legendary, detail: "Solid gold pad with ink buttons."),
        AvatarItem(id: "gadget.icecream", slot: .gadget, name: "Ice Cream", price: 50, rarity: .common, detail: "Two scoops in a crispy cone."),
        AvatarItem(id: "gadget.balloon", slot: .gadget, name: "Gold Balloon", price: 60, rarity: .common, detail: "A shiny balloon on a string."),
        AvatarItem(id: "gadget.plush", slot: .gadget, name: "Plush Bear", price: 90, rarity: .common, detail: "A soft bear to hug after a close round."),
        AvatarItem(id: "gadget.camera", slot: .gadget, name: "Camera", price: 120, rarity: .rare, detail: "For clips worth keeping."),
        AvatarItem(id: "gadget.wand", slot: .gadget, name: "Star Wand", price: 300, rarity: .epic, detail: "A wand with a glowing gold star."),

        AvatarItem(id: "decor.plant", slot: .decor, name: "Potted Plant", price: 40, rarity: .common, detail: "A leafy friend for the corner."),
        AvatarItem(id: "decor.lamp", slot: .decor, name: "Floor Lamp", price: 50, rarity: .common, detail: "Warm light for late rounds."),
        AvatarItem(id: "decor.rug", slot: .decor, name: "Round Rug", price: 60, rarity: .common, detail: "A soft striped rug."),
        AvatarItem(id: "decor.beanbag", slot: .decor, name: "Bean Bag", price: 70, rarity: .common, detail: "Sink in and play one more."),
        AvatarItem(id: "decor.poster", slot: .decor, name: "Game Poster", price: 80, rarity: .common, detail: "Tippy Tower, framed."),
        AvatarItem(id: "decor.fridge", slot: .decor, name: "Mini Fridge", price: 90, rarity: .common, detail: "Snacks within reach."),
        AvatarItem(id: "decor.lavalamp", slot: .decor, name: "Lava Lamp", price: 120, rarity: .rare, detail: "Slow purple blobs."),
        AvatarItem(id: "decor.bookshelf", slot: .decor, name: "Bookshelf", price: 140, rarity: .rare, detail: "Books, games and a tiny cactus."),
        AvatarItem(id: "decor.neon", slot: .decor, name: "GG Neon Sign", price: 180, rarity: .rare, detail: "Glowing gold letters for the wall."),
        AvatarItem(id: "decor.arcade", slot: .decor, name: "Arcade Cabinet", price: 300, rarity: .epic, detail: "Your own cabinet with a glowing screen."),
        AvatarItem(id: "decor.cat", slot: .decor, name: "Pet Cat", price: 360, rarity: .epic, detail: "An orange cat that naps on the floor."),
        AvatarItem(id: "decor.robot", slot: .decor, name: "Pet Robot", price: 420, rarity: .epic, detail: "A little robot with a blinking light."),
        AvatarItem(id: "decor.goldtrophy", slot: .decor, name: "Gold Trophy Stand", price: 800, rarity: .legendary, detail: "A tall gold cup on a stand."),
    ]

    /// Sets of items sold together for less. The price is worked out on the server.
    static let bundles: [AvatarBundle] = [
        AvatarBundle(id: "bundle.arcade", name: "Arcade Kid", detail: "Headset, gold hoodie, controller and an arcade cabinet.",
                     items: ["hat.headset", "outfit.hoodie", "gadget.controller", "decor.arcade"]),
        AvatarBundle(id: "bundle.cozy", name: "Cozy Day", detail: "Beanie, cozy sweater, bubble tea and a bean bag.",
                     items: ["hat.beanie", "outfit.sweater", "gadget.boba", "decor.beanbag"]),
        AvatarBundle(id: "bundle.royal", name: "Royal Court", detail: "Crown, tux, trophy cup and a gold trophy stand.",
                     items: ["hat.crown", "outfit.tux", "gadget.trophy", "decor.goldtrophy"]),
    ]

    static func bundle(_ id: String) -> AvatarBundle? { bundles.first { $0.id == id } }

    /// A room holds this many decor items at once.
    static let roomSpots = 4

    static func item(_ id: String?) -> AvatarItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    static func items(in slot: AvatarSlot) -> [AvatarItem] { items.filter { $0.slot == slot } }

    /// Today's three drops. Everyone sees the same three, picked from the day number, and they leave at midnight.
    static func drops(day: Int) -> [AvatarItem] {
        let paid = items.filter { !$0.isFree && [.hat, .gadget, .decor].contains($0.slot) }
        guard !paid.isEmpty else { return [] }
        var picks: [AvatarItem] = []
        var index = (day * 7) % paid.count
        while picks.count < 3 {
            let item = paid[index % paid.count]
            if !picks.contains(where: { $0.slot == item.slot }) || picks.count + index > paid.count * 2 { picks.append(item) }
            index += 5
        }
        return picks
    }
}
