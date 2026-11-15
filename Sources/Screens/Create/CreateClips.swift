import SwiftUI
import Combine
import ConvexMobile

// Clips players make with the Create camera: the take waiting in the preview, the posting, and the
// feed of posted clips that Videos shows ahead of the catalog clips.

enum CreateLayout: String, CaseIterable {
    /// Camera on the top half, game on the bottom half.
    case split
    /// Game full screen, the face in a circle that can sit in any corner.
    case bubble
    /// Camera full screen, the game over it in the lower two thirds.
    case overlay

    var title: String {
        switch self {
        case .split: "Split"
        case .bubble: "Bubble"
        case .overlay: "Overlay"
        }
    }

    var symbol: String {
        switch self {
        case .split: "rectangle.split.1x2"
        case .bubble: "pip"
        case .overlay: "square.on.square"
        }
    }

    var next: CreateLayout {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
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
    let likes: Double
    let comments: Double
    let handle: String
    let color: String
    let mine: Bool

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case at, gameSlug, gameTitle, unit, kind, url, score, seed, caption, layout, durationMs, likes, comments,
             handle, color, mine
    }

    var scoreText: String? {
        guard let score, score > 0 else { return nil }
        let number = groupedNumber(Int(score.rounded()))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

final class CreateClips: ObservableObject {
    static let shared = CreateClips()

    /// Newest first.
    @Published private(set) var feed: [ConvexClip] = []
    /// The recording waiting in the preview.
    @Published var take: CreateTake?

    private let link = ConvexLink.shared
    private var bag = Set<AnyCancellable>()
    private var watch: AnyCancellable?

    private init() {
        guard !ProcessInfo.processInfo.arguments.contains("-screen") else { return }
        link.signedIn.sink { [weak self] on in
            guard let self else { return }
            self.watch = on ? self.link.watch("clips:feed", as: [ConvexClip].self) { [weak self] rows in
                self?.feed = rows
            } : nil
        }
        .store(in: &bag)
    }

    /// Uploads the take and posts it. `progress` runs from 0 to 1 on the main thread. Returns the clip's id.
    func post(_ take: CreateTake, caption: String, everyone: Bool, progress: @escaping (Double) -> Void) async throws -> String {
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
            "visibility": everyone ? "everyone" : "friends",
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
