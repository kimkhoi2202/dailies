import SwiftUI
import UIKit

// Filming a room round: with "Film me while I play" on in the room, the player's face sits in a bubble
// over the game and the screen is recorded, so the clip holds the face and the multiplayer round together.

enum CreateFilm {
    static let wantedKey = "dailies.create.filmRooms"
    static var wanted: Bool { UserDefaults.standard.bool(forKey: wantedKey) }
}

/// One filmed round: the camera, and the recording that runs while the round plays.
final class CreateFilmSession: ObservableObject {
    let camera = CreateCamera()
    private(set) var cameraOnly = false
    private var recording = false

    /// Starts the camera and the recording. Call when the round starts.
    func begin() async {
        camera.cutout = false
        await camera.start(ownAudio: !CreateScreenRecorder.isAvailable)
        if CreateScreenRecorder.isAvailable, (try? await CreateScreenRecorder.start(mic: camera.micGranted)) != nil {
            recording = true
        } else if CreateCamera.hasHardware && camera.access == .granted {
            camera.startRecording()
            recording = true
            cameraOnly = true
        }
    }

    /// Stops the recording and the camera. nil when nothing was recorded.
    func finish() async -> URL? {
        defer { camera.stop() }
        guard recording else { return nil }
        recording = false
        if cameraOnly { return await camera.stopRecording() }
        do { return try await CreateScreenRecorder.stop() } catch {
            CreateScreenRecorder.log.error("Screen recording failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Drops a recording nobody wants, such as a round left early.
    func discard() {
        if recording && !cameraOnly { CreateScreenRecorder.discard() }
        recording = false
        camera.stop()
    }
}

/// The player's face in a bubble over a running game. Drag it anywhere; pinch it to size it.
struct CreateFilmBubble: View {
    @ObservedObject var session: CreateFilmSession
    @State private var at = CGPoint(x: 0.8, y: 0.24)
    @State private var scale: CGFloat = 1
    @State private var drag: CGSize = .zero
    @State private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let side = min(size.width * 0.8, max(72, 120 * scale * pinch))
            face
                .frame(width: side, height: side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        Circle().fill(DL.danger).frame(width: 7, height: 7)
                        Text("REC").font(DL.label(9)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(.black.opacity(0.55)))
                }
                .contentShape(Circle())
                .gesture(move(size).simultaneously(with: resize))
                .offset(drag)
                .position(x: at.x * size.width, y: at.y * size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder private var face: some View {
        if CreateCamera.hasHardware {
            CreateCameraView(camera: session.camera, cutout: false)
        } else {
            CreateCameraPlaceholder()
        }
    }

    private func move(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { drag = value.translation }
            }
            .onEnded { value in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    at = CGPoint(x: at.x + value.translation.width / size.width, y: at.y + value.translation.height / size.height)
                    drag = .zero
                }
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    at = CGPoint(x: min(0.9, max(0.1, at.x)), y: min(0.9, max(0.12, at.y)))
                }
            }
    }

    private var resize: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { pinch = value.magnification }
            }
            .onEnded { value in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    scale = min(2.6, max(0.6, scale * value.magnification))
                    pinch = 1
                }
            }
    }
}
