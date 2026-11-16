import SwiftUI
import Combine
import ConvexMobile

// Clips players make with the Create camera: the take waiting in the preview, the posting, and the
// feed of posted clips that Videos shows ahead of the catalog clips.

/// How the player sits on the game, which always fills the screen.
enum CreateLayout: String, CaseIterable {
    /// Green screen: the player cut out of the camera's background, dragged and pinched anywhere over the game.
    case cutout
    /// The whole camera, background and all, in a card dragged and pinched anywhere over the game.
    case window
    /// The player's face in a circle that sits in a corner.
    case bubble
    /// The camera in a band across the top third, the game below it.
    case top

    var title: String {
        switch self {
        case .cutout: "Green screen"
        case .window: "Background"
        case .bubble: "Bubble"
        case .top: "Cam on top"
        }
    }

    var symbol: String {
        switch self {
        case .cutout: "person.fill"
        case .window: "person.crop.rectangle"
        case .bubble: "pip"
        case .top: "rectangle.split.1x2"
        }
    }

    /// The player can be dragged and pinched.
    var movable: Bool { self != .top }
}

/// One recording, on its way from the camera to the preview.
struct CreateTake {
    var gameID: String
    var layout: CreateLayout
    /// The recording. nil when this phone could not record (a simulator without screen recording).
    var videoURL: URL?
    /// The recording holds the camera alone, so the preview plays the game beside it.
    var cameraOnly = false
    var photo: UIImage?
    var roundID: String?
    var result: GameResult?
    var isBest = false
    var seconds: Double = 0

    /// "58 FLOORS". nil when the round did not reach its end.
    var scoreLine: String? {
        guard let result, result.score > 0 else { return nil }
        let number = result.scoreText ?? groupedNumber(result.score)
        return result.unit.isEmpty ? number : "\(number) \(result.unit.uppercased())"
    }
}

/// `clips:feed`: a posted clip.
struct ConvexClip: Decodable, Equatable, Identifiable {
    let id: String
    let at: Double
    let gameSlug: String
    let gameTitle: String
    let unit: String
    let kind: String
    let url: String?
    let score: Double?
    let seed: Double?
    let caption: String
    let layout: String
    let durationMs: Double
    let visibility: String
    let likes: Double
    let comments: Double
    let handle: String
    let color: String
    let mine: Bool

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case at, gameSlug, gameTitle, unit, kind, url, score, seed, caption, layout, durationMs, visibility, likes,
             comments, handle, color, mine
    }

    /// The key this clip is saved under.
    var saveKey: String { id }

    var scoreText: String? {
        guard let score, score > 0 else { return nil }
        let number = groupedNumber(Int(score.rounded()))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// `clips:saved`: one saved clip. A catalog clip has a "sample:<id>" key and no clip.
struct ConvexSavedClip: Decodable, Equatable {
    let key: String
    let clip: ConvexClip?
}

/// A clip in a grid or the full-screen viewer: one a player posted, or a catalog clip from Videos.
enum ClipItem: Identifiable, Equatable {
    case posted(ConvexClip)
    case sample(MockClip)

    var id: String {
        switch self {
        case .posted(let clip): clip.id
        case .sample(let clip): CreateClips.sampleKey(clip.id)
        }
    }

    var gameID: String {
        switch self {
        case .posted(let clip): clip.gameSlug
        case .sample(let clip): clip.game.id
        }
    }

    static func == (a: ClipItem, b: ClipItem) -> Bool {
        switch (a, b) {
        case (.posted(let x), .posted(let y)): x == y
        case (.sample(let x), .sample(let y)): x.id == y.id
        default: false
        }
    }
}

final class CreateClips: ObservableObject {
    static let shared = CreateClips()

    /// Newest first.
    @Published private(set) var feed: [ConvexClip] = []
    /// The player's own clips, newest first.
    @Published private(set) var mine: [ConvexClip] = []
    /// Set when a clip was just saved privately, so the profile opens on Clips.
    @Published var showClips = false
    /// What the player saved, newest first.
    @Published private(set) var saved: [ClipItem] = []
    /// Every saved key, changed at once on a tap and then by the server.
    @Published private(set) var savedKeys: Set<String> = []
    /// The recording waiting in the preview.
    @Published var take: CreateTake?

    private let link = ConvexLink.shared
    private var bag = Set<AnyCancellable>()
    private var watches: [AnyCancellable] = []

    static func sampleKey(_ id: String) -> String { "sample:" + id }

    private init() {
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        link.signedIn.sink { [weak self] on in
            guard let self else { return }
            guard on else { return self.watches = [] }
            self.watches = [
                self.link.watch("clips:feed", as: [ConvexClip].self) { [weak self] rows in self?.feed = rows },
                self.link.watch("clips:mine", as: [ConvexClip].self) { [weak self] rows in self?.mine = rows },
                self.link.watch("clips:saved", as: [ConvexSavedClip].self) { [weak self] rows in
                    guard let self else { return }
                    self.saved = rows.compactMap { row in
                        if let clip = row.clip { return .posted(clip) }
                        let id = String(row.key.dropFirst("sample:".count))
                        return Mock.clips.first { $0.id == id }.map { .sample($0) }
                    }
                    self.savedKeys = Set(rows.map(\.key))
                },
            ]
        }
        .store(in: &bag)
    }

    /// The clips a player posted that someone else can see, or all of them for the player.
    func watchUser(_ handle: String, _ rows: @escaping ([ConvexClip]) -> Void) -> AnyCancellable {
        link.watch("clips:byUser", ["handle": handle], as: [ConvexClip].self, onValue: rows)
    }

    func isSaved(_ key: String) -> Bool { savedKeys.contains(key) }

    func toggleSave(_ key: String) {
        let now = !savedKeys.contains(key)
        if now { savedKeys.insert(key) } else { savedKeys.remove(key) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        LiveNav.shared.say(now ? "Saved" : "Removed from saved")
        Task {
            do {
                _ = try await link.mutate("clips:toggleSave", ["key": key], as: Bool.self)
            } catch {
                await MainActor.run {
                    if now { self.savedKeys.remove(key) } else { self.savedKeys.insert(key) }
                    LiveNav.shared.say("Could not save. Try again")
                }
            }
        }
    }

    /// visibility is "everyone", "friends" or "private".
    func update(_ clip: ConvexClip, caption: String, visibility: String) async throws {
        try await link.mutate("clips:update", [
            "clipId": clip.id,
            "caption": String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)),
            "visibility": visibility,
        ])
    }

    func remove(_ clip: ConvexClip) async throws {
        try await link.mutate("clips:remove", ["clipId": clip.id])
    }

    /// Uploads the take and posts it, or keeps it just for the player with visibility "private". Progress runs from 0 to 1 on the main thread. Returns the clip's id.
    func post(_ take: CreateTake, caption: String, visibility: String, progress: @escaping (Double) -> Void) async throws -> String {
        var storageID: String?
        var kind = "video"
        if let photo = take.photo {
            kind = "photo"
            guard let data = photo.jpegData(compressionQuality: 0.85) else { throw CreateError.noMedia }
            let file = CreateFiles.newURL("jpg")
            try data.write(to: file)
            storageID = try await upload(file, type: "image/jpeg", progress: progress)
        } else if let video = take.videoURL {
            storageID = try await upload(video, type: "video/mp4", progress: progress)
        }
        await MainActor.run { progress(1) }
        var args: [String: ConvexEncodable?] = [
            "gameSlug": take.gameID,
            "kind": kind,
            "caption": String(caption.trimmingCharacters(in: .whitespacesAndNewlines).prefix(140)),
            "layout": take.layout.rawValue,
            "durationMs": (take.seconds * 1000).rounded(),
            "visibility": visibility,
        ]
        if let storageID { args["storageId"] = storageID }
        if let round = take.roundID { args["roundId"] = round }
        return try await link.mutate("clips:create", args, as: String.self)
    }

    private func upload(_ file: URL, type: String, progress: @escaping (Double) -> Void) async throws -> String {
        let address: String = try await link.mutate("clips:generateUploadUrl", as: String.self)
        guard let url = URL(string: address) else { throw CreateError.upload }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        var watching: NSKeyValueObservation?
        defer { watching?.invalidate() }
        let data: Data = try await withCheckedThrowingContinuation { done in
            let task = URLSession.shared.uploadTask(with: request, fromFile: file) { data, response, error in
                if let error { return done.resume(throwing: error) }
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return done.resume(throwing: CreateError.upload) }
                done.resume(returning: data)
            }
            watching = task.progress.observe(\.fractionCompleted) { value, _ in
                let fraction = value.fractionCompleted
                DispatchQueue.main.async { progress(min(0.96, fraction)) }
            }
            task.resume()
        }
        struct Answer: Decodable { let storageId: String }
        return try JSONDecoder().decode(Answer.self, from: data).storageId
    }
}

enum CreateError: Error {
    case noMedia, upload
}
