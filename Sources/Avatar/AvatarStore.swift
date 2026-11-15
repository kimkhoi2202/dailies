import SwiftUI
import Combine
import ConvexMobile

// The player's Dailie: what it wears and which items they own, from Convex. Equipping changes the look
// here at once and then on the server; buying waits for the server, which checks the price and the gold.

/// `avatar:locker`
struct ConvexLocker: Decodable, Equatable {
    let look: AvatarLook
    let owned: [String]
    let color: String
    let decor: [String]?
}

/// `avatar:profile`: anyone's profile, by handle.
struct ConvexProfile: Decodable, Equatable {
    struct Best: Decodable, Equatable {
        let gameSlug: String
        let score: Double
        let text: String?
        let unit: String?
    }

    let name: String
    let handle: String
    let color: String
    let gold: Double
    let streak: Double
    let rounds: Double
    let look: AvatarLook
    let decor: [String]?
    let you: Bool
    let bests: [Best]
}

final class AvatarStore: ObservableObject {
    static let shared = AvatarStore()

    @Published private(set) var look: AvatarLook
    @Published private(set) var owned: Set<String>
    @Published private(set) var color: String
    /// Decor placed in the room, in spot order. At most AvatarCatalog.roomSpots.
    @Published private(set) var decor: [String]
    /// The colour of the player's room wall, kept on this phone. Empty is the default dark wall.
    @Published var wall: String = UserDefaults.standard.string(forKey: "dailies.room.wall") ?? "" {
        didSet { UserDefaults.standard.set(wall, forKey: "dailies.room.wall") }
    }

    static let walls: [(name: String, hex: String)] = [
        ("Dusk", ""), ("Teal", "1F5F5A"), ("Plum", "4A2F66"), ("Navy", "22305C"), ("Rose", "6B2F45"), ("Forest", "2F4A2A"), ("Gold", "6B5212"),
    ]

    var wallColor: Color? { wall.isEmpty ? nil : Color(hex: wall) }

    private static let cacheKey = "dailies.avatar.v1"
    private struct Cached: Codable {
        var look: AvatarLook
        var owned: [String]
        var color: String
        var decor: [String]?
    }

    private let live = !ProcessInfo.processInfo.arguments.contains("-screen")
    private var bag = Set<AnyCancellable>()
    private var watch: AnyCancellable?
    /// Equips sent to the server and not answered yet. The server's look waits until this is 0.
    private var pending = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(Cached.self, from: data) {
            look = cached.look; owned = Set(cached.owned); color = cached.color; decor = cached.decor ?? []
        } else {
            look = AvatarLook.starter(handle: "mira"); owned = []; color = "#7C5CFF"; decor = []
        }
        guard live else { return }
        ConvexLink.shared.signedIn.sink { [weak self] on in
            guard let self else { return }
            if on { self.open() } else { self.watch = nil }
        }.store(in: &bag)
    }

    var shirt: VoxelColor { VoxelColor(hex: color) }

    func owns(_ item: AvatarItem) -> Bool { item.isFree || owned.contains(item.id) }

    func wears(_ item: AvatarItem) -> Bool {
        item.slot == .decor ? decor.contains(item.id) : look.item(in: item.slot) == item.id
    }

    private func open() {
        watch = ConvexLink.shared.watch("avatar:locker", as: ConvexLocker?.self) { [weak self] value in
            guard let self, let value, self.pending == 0 else { return }
            self.apply(look: value.look, owned: Set(value.owned), color: value.color, decor: value.decor ?? [])
        }
    }

    private func apply(look: AvatarLook, owned: Set<String>, color: String, decor: [String]? = nil) {
        let decor = decor ?? self.decor
        if look != self.look { self.look = look }
        if owned != self.owned { self.owned = owned }
        if color != self.color { self.color = color }
        if decor != self.decor { self.decor = decor }
        let cached = Cached(look: look, owned: Array(owned), color: color, decor: decor)
        if let data = try? JSONEncoder().encode(cached) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
    }

    /// Puts an owned decor item in the room, or takes it out. Says so when the room is full.
    func toggleDecor(_ item: AvatarItem) {
        guard item.slot == .decor, owns(item) else { return }
        let placing = !decor.contains(item.id)
        if placing && decor.count >= AvatarCatalog.roomSpots {
            LiveNav.shared.say("Your room is full. Take something out first.")
            return
        }
        apply(look: look, owned: owned, color: color, decor: placing ? decor + [item.id] : decor.filter { $0 != item.id })
        if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        guard live else { return }
        pending += 1
        let args: [String: ConvexEncodable?] = ["itemId": item.id, "placed": placing]
        Task { @MainActor in
            do { try await ConvexLink.shared.mutate("avatar:placeDecor", args) } catch {
                LiveNav.shared.say(Self.message(error) ?? "That did not save. Try again.")
            }
            self.pending -= 1
        }
    }

    /// Wears an owned item, or places it in the room if it is decor.
    func use(_ item: AvatarItem) {
        if item.slot == .decor { if !decor.contains(item.id) { toggleDecor(item) } } else { equip(item, slot: item.slot) }
    }

    /// Buys every item of a bundle not owned yet. Returns a message when it did not work.
    @MainActor
    func buy(_ bundle: AvatarBundle) async -> String? {
        let ids = Set(bundle.items)
        guard live else {
            apply(look: look, owned: owned.union(ids), color: color)
            return nil
        }
        do {
            _ = try await ConvexLink.shared.mutate("shop:buyBundle", ["bundleId": bundle.id], as: ConvexSpend.self)
            apply(look: look, owned: owned.union(ids), color: color)
            if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return nil
        } catch {
            return Self.message(error) ?? "The shop did not answer. Try again."
        }
    }

    /// Puts an owned item on, or takes off whatever is in the slot when `item` is nil.
    func equip(_ item: AvatarItem?, slot: AvatarSlot) {
        guard slot.worn else { return }
        if let item, !owns(item) { return }
        if item == nil && !slot.removable { return }
        apply(look: look.with(slot, item?.id), owned: owned, color: color)
        if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        guard live else { return }
        pending += 1
        let args: [String: ConvexEncodable?] = ["slot": slot.rawValue, "itemId": item?.id]
        Task { @MainActor in
            do { try await ConvexLink.shared.mutate("avatar:equip", args) } catch {
                LiveNav.shared.say(Self.message(error) ?? "That did not save. Try again.")
            }
            self.pending -= 1
        }
    }

    /// Buys an item. The server sets the price and takes the gold. Returns a message when it did not work.
    @MainActor
    func buy(_ item: AvatarItem) async -> String? {
        guard !owns(item) else { return nil }
        guard live else {
            apply(look: look, owned: owned.union([item.id]), color: color)
            return nil
        }
        do {
            _ = try await ConvexLink.shared.mutate("shop:buy", ["itemId": item.id], as: ConvexSpend.self)
            apply(look: look, owned: owned.union([item.id]), color: color)
            if LiveStore.shared.s.haptics { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return nil
        } catch {
            return Self.message(error) ?? "The shop did not answer. Try again."
        }
    }

    /// The text of a ConvexError, without its JSON quotes.
    private static func message(_ error: Error) -> String? {
        guard let client = error as? ClientError, case .ConvexError(let data) = client else { return nil }
        return data.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

/// Someone else's profile, kept live while their page is open.
final class ProfileLoader: ObservableObject {
    @Published private(set) var profile: ConvexProfile?
    private var watch: AnyCancellable?
    private var bag = Set<AnyCancellable>()

    init(handle: String) {
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        ConvexLink.shared.signedIn.sink { [weak self] on in
            guard let self, on else { return }
            self.watch = ConvexLink.shared.watch("avatar:profile", ["handle": handle], as: ConvexProfile?.self) { [weak self] value in
                self?.profile = value
            }
        }.store(in: &bag)
    }
}
