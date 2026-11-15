import Foundation

// The avatar catalog, the same list as convex/items.ts. The server decides prices and ownership;
// the app uses this list to draw items and show their prices.

enum AvatarSlot: String, CaseIterable, Codable {
    case body, face, hair, hat, outfit, gadget

    var title: String {
        switch self {
        case .body: "Body"
        case .face: "Faces"
        case .hair: "Hair"
        case .hat: "Hats"
        case .outfit: "Outfits"
        case .gadget: "Gadgets"
        }
    }

    /// Body and face are never empty. The rest can be taken off.
    var removable: Bool { self != .body && self != .face }
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
        }
        return next
    }

    func wearing(_ item: AvatarItem) -> AvatarLook { with(item.slot, item.id) }

    /// The same pick as defaultLook in convex/items.ts, so a new player looks the same before the server answers.
    static func starter(handle: String) -> AvatarLook {
        let bodies = ["body.porcelain", "body.peach", "body.honey", "body.umber", "body.cocoa"]
        let hair = ["hair.short", "hair.bob", "hair.spiky", "hair.bun"]
        var sum = 0
        for unit in handle.utf16 { sum = (sum * 31 + Int(unit)) % 100003 }
        return AvatarLook(body: bodies[sum % bodies.count], face: "face.happy",
                          hair: hair[(sum / 7) % hair.count], outfit: "outfit.tee")
    }
}

enum AvatarCatalog {
    static let items: [AvatarItem] = [
        AvatarItem(id: "body.porcelain", slot: .body, name: "Porcelain", price: 0, rarity: .common, detail: "A light skin tone."),
        AvatarItem(id: "body.peach", slot: .body, name: "Peach", price: 0, rarity: .common, detail: "A warm skin tone."),
        AvatarItem(id: "body.honey", slot: .body, name: "Honey", price: 0, rarity: .common, detail: "A golden skin tone."),
        AvatarItem(id: "body.umber", slot: .body, name: "Umber", price: 0, rarity: .common, detail: "A deep skin tone."),
        AvatarItem(id: "body.cocoa", slot: .body, name: "Cocoa", price: 0, rarity: .common, detail: "A rich dark skin tone."),
        AvatarItem(id: "body.mint", slot: .body, name: "Mint", price: 0, rarity: .common, detail: "For a day off from being human."),
        AvatarItem(id: "body.sky", slot: .body, name: "Sky", price: 0, rarity: .common, detail: "Calm and blue."),
        AvatarItem(id: "body.lilac", slot: .body, name: "Lilac", price: 0, rarity: .common, detail: "Soft purple, like dusk."),
        AvatarItem(id: "body.coral", slot: .body, name: "Coral", price: 0, rarity: .common, detail: "Bright and friendly."),
        AvatarItem(id: "body.gold", slot: .body, name: "Gold", price: 0, rarity: .common, detail: "Our colour, head to toe."),

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
        AvatarItem(id: "hat.cap", slot: .hat, name: "Cap", price: 80, rarity: .common, detail: "An ink cap with a gold bill."),
        AvatarItem(id: "hat.catears", slot: .hat, name: "Cat Ears", price: 150, rarity: .rare, detail: "Ears that hear a combo coming."),
        AvatarItem(id: "hat.headset", slot: .hat, name: "Gamer Headset", price: 180, rarity: .rare, detail: "Gold cups and a mic for callouts."),
        AvatarItem(id: "hat.halo", slot: .hat, name: "Halo", price: 300, rarity: .epic, detail: "A floating gold ring. Very well behaved."),
        AvatarItem(id: "hat.wizard", slot: .hat, name: "Wizard Hat", price: 350, rarity: .epic, detail: "Purple, tall and full of stars."),
        AvatarItem(id: "hat.crown", slot: .hat, name: "Crown", price: 800, rarity: .legendary, detail: "Solid gold with three gems."),

        AvatarItem(id: "outfit.tee", slot: .outfit, name: "Signature Tee", price: 0, rarity: .common, detail: "A tee in your own colour."),
        AvatarItem(id: "outfit.overalls", slot: .outfit, name: "Overalls", price: 70, rarity: .common, detail: "Teal overalls over a cream tee."),
        AvatarItem(id: "outfit.sweater", slot: .outfit, name: "Cozy Sweater", price: 80, rarity: .common, detail: "Coral knit with cream stripes."),
        AvatarItem(id: "outfit.hoodie", slot: .outfit, name: "Gold Hoodie", price: 90, rarity: .common, detail: "Our gold, with a hood and a pocket."),
        AvatarItem(id: "outfit.tracksuit", slot: .outfit, name: "Tracksuit", price: 140, rarity: .rare, detail: "Teal with cream side stripes."),
        AvatarItem(id: "outfit.varsity", slot: .outfit, name: "Varsity Jacket", price: 160, rarity: .rare, detail: "Purple and cream with a gold D."),
        AvatarItem(id: "outfit.cape", slot: .outfit, name: "Hero Cape", price: 200, rarity: .rare, detail: "A red cape and a gold star."),
        AvatarItem(id: "outfit.tux", slot: .outfit, name: "Tux", price: 320, rarity: .epic, detail: "Ink tux and a gold bow tie."),
        AvatarItem(id: "outfit.astronaut", slot: .outfit, name: "Astronaut Suit", price: 900, rarity: .legendary, detail: "White suit, gold panel, air for days."),

        AvatarItem(id: "gadget.phone", slot: .gadget, name: "Phone", price: 50, rarity: .common, detail: "For one more round on the bus."),
        AvatarItem(id: "gadget.controller", slot: .gadget, name: "Controller", price: 60, rarity: .common, detail: "An ink pad with gold and teal buttons."),
        AvatarItem(id: "gadget.joystick", slot: .gadget, name: "Joystick", price: 70, rarity: .common, detail: "Arcade stick with a red ball top."),
        AvatarItem(id: "gadget.boba", slot: .gadget, name: "Bubble Tea", price: 80, rarity: .common, detail: "Milk tea with pearls."),
        AvatarItem(id: "gadget.mic", slot: .gadget, name: "Microphone", price: 130, rarity: .rare, detail: "For the post-game speech."),
        AvatarItem(id: "gadget.trophy", slot: .gadget, name: "Trophy Cup", price: 260, rarity: .epic, detail: "A gold cup to hold up high."),
        AvatarItem(id: "gadget.goldpad", slot: .gadget, name: "Golden Controller", price: 700, rarity: .legendary, detail: "Solid gold pad with ink buttons."),
    ]

    static func item(_ id: String?) -> AvatarItem? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    static func items(in slot: AvatarSlot) -> [AvatarItem] { items.filter { $0.slot == slot } }

    /// Today's three drops. Everyone sees the same three, picked from the day number, and they leave at midnight.
    static func drops(day: Int) -> [AvatarItem] {
        let paid = items.filter { !$0.isFree }
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
