import SwiftUI
import UIKit
import AVFoundation
import CoreImage
import ReplayKit
import Vision
import os

// What the Create camera films with: the front camera, the screen recorder that puts the camera and
// the game in one file, and a still of the screen for photos.

/// The camera. Its frames are drawn by a sample buffer layer, which the screen recorder captures,
/// and they are kept for stills. With `cutout` on, the person is cut out of each frame and drawn on a
/// clear background, so the game shows around them. When the screen recorder is missing it writes the
/// camera to a file itself.
final class CreateCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                          AVCaptureAudioDataOutputSampleBufferDelegate {
    enum Access { case unknown, granted, denied }

    /// false on a simulator, which has no camera.
    static let hasHardware: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
        #endif
    }()

    @Published private(set) var access: Access = .unknown
    @Published private(set) var front = true
    @Published private(set) var torch = false
    /// Quarter turns clockwise applied to the camera's frames, kept between launches. 0 is upright on an iPhone 17 Pro.
    @Published private(set) var turns = UserDefaults.standard.integer(forKey: CreateCamera.turnsKey)
    private static let turnsKey = "dailies.create.cameraTurns"
    /// The angle the camera queue applies. Touched only on the camera queue.
    private var angle = Double(UserDefaults.standard.integer(forKey: CreateCamera.turnsKey) % 4) * 90

    let display = AVSampleBufferDisplayLayer()
    /// The person alone, on a clear background.
    let cutoutLayer = CALayer()

    /// Set on the main thread, read on the camera queue.
    var cutout: Bool {
        get { cutoutLock.withLock { cutoutOn } }
        set { cutoutLock.withLock { cutoutOn = newValue } }
    }
    private var cutoutOn = true
    private let cutoutLock = NSLock()
    private let segmentQueue = DispatchQueue(label: "dailies.create.segment")
    private let segmenter: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let renderer = CIContext()
    /// Touched only on the camera queue. A frame is skipped while the last one is still being cut out.
    private var segmenting = false

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dailies.create.camera")
    private let videoOut = AVCaptureVideoDataOutput()
    private let audioOut = AVCaptureAudioDataOutput()
    private var configured = false

    // Touched only on the queue.
    private var lastFrame: CVPixelBuffer?
    private var writer: AVAssetWriter?
    private var videoIn: AVAssetWriterInput?
    private var audioIn: AVAssetWriterInput?
    private var writing = false

    override init() {
        super.init()
        display.videoGravity = .resizeAspectFill
        cutoutLayer.contentsGravity = .resizeAspect
    }

    var micGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }

    /// Asks for the camera and the microphone, then starts the camera.
    /// With `ownAudio` the camera also listens, for recording without the screen recorder.
    func start(ownAudio: Bool) async {
        guard Self.hasHardware else { return }
        let video = await AVCaptureDevice.requestAccess(for: .video)
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run { access = video ? .granted : .denied }
        guard video else { return }
        let audio = ownAudio && micGranted
        queue.async {
            if !self.configured { self.configure(audio: audio) }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        queue.async {
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flip() {
        let toFront = !front
        front = toFront
        torch = false
        queue.async {
            guard self.configured else { return }
            self.session.beginConfiguration()
            for input in self.session.inputs {
                if let device = (input as? AVCaptureDeviceInput)?.device, device.hasMediaType(.video) {
                    self.session.removeInput(input)
                }
            }
            if let input = Self.input(front: toFront), self.session.canAddInput(input) { self.session.addInput(input) }
            self.orient()
            self.session.commitConfiguration()
        }
    }

    /// Turns the picture a quarter turn clockwise.
    func rotate() {
        turns = (turns + 1) % 4
        UserDefaults.standard.set(turns, forKey: Self.turnsKey)
        let next = Double(turns) * 90
        queue.async {
            self.angle = next
            self.orient()
        }
    }

    /// The flash is the back camera's torch. Returns false when the camera in use has none.
    @discardableResult
    func setFlash(_ on: Bool) -> Bool {
        guard !front, let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else { return false }
        torch = on
        queue.async { self.setTorch(on) }
        return true
    }

    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    private static func input(front: Bool) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: front ? .front : .back)
        else { return nil }
        return try? AVCaptureDeviceInput(device: device)
    }

    private func configure(audio: Bool) {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let input = Self.input(front: front), session.canAddInput(input) { session.addInput(input) }
        if audio, let mic = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(input), session.canAddOutput(audioOut) {
            session.addInput(input)
            session.addOutput(audioOut)
            audioOut.setSampleBufferDelegate(self, queue: queue)
        }
        videoOut.alwaysDiscardsLateVideoFrames = true
        videoOut.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOut) { session.addOutput(videoOut) }
        videoOut.setSampleBufferDelegate(self, queue: queue)
        orient()
        session.commitConfiguration()
    }

    /// Frames turned by `angle`, mirrored for the front camera like a mirror.
    private func orient() {
        guard let connection = videoOut.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = front
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sample: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === videoOut {
            lastFrame = CMSampleBufferGetImageBuffer(sample)
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary],
               let first = attachments.first {
                first[kCMSampleAttachmentKey_DisplayImmediately] = true
            }
            let shown = display.sampleBufferRenderer
            if shown.status == .failed { shown.flush() }
            shown.enqueue(sample)
            if cutout, !segmenting, let frame = lastFrame {
                segmenting = true
                segmentQueue.async { self.cutOut(frame) }
            }
        }
        guard writing, let writer else { return }
        if writer.status == .unknown {
            guard output === videoOut, writer.startWriting() else { return }
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
        }
        guard writer.status == .writing else { return }
        if output === videoOut, let input = videoIn, input.isReadyForMoreMediaData {
            input.append(sample)
        } else if output === audioOut, let input = audioIn, input.isReadyForMoreMediaData {
            input.append(sample)
        }
    }

    /// Cuts the person out of one frame and shows them on a clear background.
    private func cutOut(_ frame: CVPixelBuffer) {
        defer { queue.async { self.segmenting = false } }
        let handler = VNImageRequestHandler(cvPixelBuffer: frame, options: [:])
        guard (try? handler.perform([segmenter])) != nil, let mask = segmenter.results?.first?.pixelBuffer else { return }
        let image = CIImage(cvPixelBuffer: frame)
        var matte = CIImage(cvPixelBuffer: mask)
        matte = matte.transformed(by: CGAffineTransform(scaleX: image.extent.width / matte.extent.width,
                                                        y: image.extent.height / matte.extent.height))
        let person = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: matte,
        ])
        guard let picture = renderer.createCGImage(person, from: image.extent) else { return }
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.cutoutLayer.contents = picture
            CATransaction.commit()
        }
    }

    /// The camera on its own, written to a file. Used only where the screen recorder is missing.
    func startRecording() {
        queue.async {
            let url = CreateFiles.newURL("mp4")
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
            let video = AVAssetWriterInput(mediaType: .video,
                                           outputSettings: self.videoOut.recommendedVideoSettingsForAssetWriter(writingTo: .mp4))
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else { return }
            writer.add(video)
            if self.session.outputs.contains(self.audioOut),
               let settings = self.audioOut.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as? [String: Any] {
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                audio.expectsMediaDataInRealTime = true
                if writer.canAdd(audio) {
                    writer.add(audio)
                    self.audioIn = audio
                }
            }
            self.writer = writer
            self.videoIn = video
            self.writing = true
        }
    }

    func stopRecording() async -> URL? {
        await withCheckedContinuation { done in
            queue.async {
                self.writing = false
                let writer = self.writer
                self.writer = nil
                guard let writer, writer.status == .writing else {
                    self.videoIn = nil
                    self.audioIn = nil
                    done.resume(returning: nil)
                    return
                }
                self.videoIn?.markAsFinished()
                self.audioIn?.markAsFinished()
                self.videoIn = nil
                self.audioIn = nil
                writer.finishWriting { done.resume(returning: writer.status == .completed ? writer.outputURL : nil) }
            }
        }
    }

    /// The newest camera frame as an image.
    func still() -> UIImage? {
        guard let frame = queue.sync(execute: { lastFrame }) else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        guard let cg = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Shows the camera's frames.
/// Shows the camera's frames, or with `cutout` the person alone on a clear background.
struct CreateCameraView: UIViewRepresentable {
    let camera: CreateCamera
    var cutout = false

    func makeUIView(context: Context) -> Host { Host(full: camera.display, cutout: camera.cutoutLayer) }

    func updateUIView(_ view: Host, context: Context) {
        view.showCutout(cutout)
    }

    final class Host: UIView {
        private let full: CALayer
        private let cutout: CALayer

        init(full: CALayer, cutout: CALayer) {
            self.full = full
            self.cutout = cutout
            super.init(frame: .zero)
            clipsToBounds = true
            layer.addSublayer(full)
            layer.addSublayer(cutout)
        }

        required init?(coder: NSCoder) { fatalError("Host is created in code") }

        func showCutout(_ on: Bool) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            full.isHidden = on
            cutout.isHidden = !on
            backgroundColor = on ? .clear : .black
            CATransaction.commit()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            full.frame = bounds
            cutout.frame = bounds
            CATransaction.commit()
        }
    }
}

/// In-app screen recording: the file holds exactly what is on screen, the camera and the game together.
enum CreateScreenRecorder {
    static let log = Logger(subsystem: "com.kimkhoi2202.dailies", category: "create")

    /// false on a simulator, where the recorder writes black frames.
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return RPScreenRecorder.shared().isAvailable
        #endif
    }

    static func start(mic: Bool) async throws {
        let recorder = RPScreenRecorder.shared()
        recorder.isMicrophoneEnabled = mic
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            recorder.startRecording { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
    }

    static func stop() async throws -> URL {
        let url = CreateFiles.newURL("mp4")
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            RPScreenRecorder.shared().stopRecording(withOutput: url) { error in
                if let error { done.resume(throwing: error) } else { done.resume() }
            }
        }
        return url
    }

    /// Stops a recording that is no longer wanted, and drops it.
    static func discard() {
        guard RPScreenRecorder.shared().isRecording else { return }
        RPScreenRecorder.shared().stopRecording { _, _ in }
    }
}

enum CreateFiles {
    static func newURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "dailies-\(UUID().uuidString).\(ext)")
    }

    /// Everything on screen right now, as an image.
    static func snapshotScreen() -> UIImage? {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard let window = windows.first else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }

    /// The system share sheet with files or text, from whichever controller is in front.
    static func share(_ items: [Any]) {
        let windows = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }
        guard var front = windows.first?.rootViewController else { return }
        while let above = front.presentedViewController { front = above }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = front.view
        front.present(sheet, animated: true)
    }
}
