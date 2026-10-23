import AVFoundation
import CryptoKit
import AppKit
import SwiftUI
import EyeblinkCore
import CEyeFlow
import CFaceDetector
import OSLog

private let cameraLifecycleLog = Logger(subsystem: "org.reeyeblink.app", category: "Termination")

struct CameraDevice: Identifiable, Hashable {
    let id: String
    let name: String
}


/// Session configuration belongs to sessionQueue; ordered frame/model state
/// belongs to queue. Session setup/stop synchronizes analysis only after detaching
/// the old delegate. The preview layer uses the immutable session reference.
/// Images never leave this process. Sendability relies on this queue boundary.
final class CameraPipeline: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "org.reeyeblink.app.session", qos: .userInitiated)
    private let queue = DispatchQueue(label: "org.reeyeblink.app.camera", qos: .userInitiated)
    private var handler: ((CameraObservation) -> Void)?
    private var generation = UUID()
    private var predictor: DlibShapePredictor?
    private let captureQueue = DispatchQueue(label: "org.reeyeblink.app.capture", qos: .userInitiated)
    private var source: CameraFrameSource<CVPixelBuffer>?
    private var receiver: CameraFrameReceiver?
    private var faceModelLoaded = false
    private var failures: CameraFailureObserver?
    private let frameRun = CameraFrameRun()


    static func devices() -> [CameraDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
            .devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func start(deviceID: String, generation: UUID, isPreview: Bool, noFaceTimeout: TimeInterval?, measurementDuration: TimeInterval?, handler: @escaping (CameraObservation) -> Void) {
        let emitFailure: (String) -> Void = { [weak self] message in
            self?.finishSetupFailure(message, generation: generation)
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.stopCapture()
            guard self.queue.sync(execute: { self.prepare(generation: generation, isPreview: isPreview, noFaceTimeout: noFaceTimeout, measurementDuration: measurementDuration, handler: handler) }) else { return }
            self.session.beginConfiguration()
            var configuring = true
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            let available = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
            let selected = deviceID.isEmpty ? available.first : available.first(where: { $0.uniqueID == deviceID })
            guard let device = selected else {
                self.session.commitConfiguration()
                emitFailure(deviceID.isEmpty ? "没有可用的摄像头。请连接设备后重试。" : "所选摄像头已断开。请重新连接，或选择其他摄像头。")
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard self.session.canAddInput(input) else { throw CameraError.inputUnavailable }
                self.session.addInput(input)
                // The shipped OpenCV backend starts at Medium, then requests
                // 640x480 through output videoSettings, accepting the actual format.
                guard self.session.canSetSessionPreset(.medium) else { throw CameraError.inputUnavailable }
                self.session.sessionPreset = .medium
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                let source = CameraFrameSource<CVPixelBuffer>()
                let receiver = CameraFrameReceiver(source: source)
                self.source = source; self.receiver = receiver
                output.setSampleBufferDelegate(receiver, queue: self.captureQueue)
                guard self.session.canAddOutput(output) else { throw CameraError.outputUnavailable }
                self.session.addOutput(output)
                self.session.commitConfiguration()
                configuring = false
                let failures = CameraFailureObserver(queue: self.captureQueue) { _, failure in
                    switch failure {
                    case .runtime(let detail): source.close(.device("摄像头采集发生错误。" + (detail ?? "")))
                    case .disconnected: source.close(.device("所选摄像头已断开。"))
                    case .interrupted: source.close(.device("摄像头采集被系统中断。"))
                    }
                }
                self.failures = failures
                self.captureQueue.sync { failures.start(generation: generation, session: self.session, device: device) }
                self.session.startRunning()
                guard self.session.isRunning else { throw CameraError.inputUnavailable }
                // Backend open and setWidthHeight each flush one frame, before
                // Model's separate seven reads and checked priming image.
                _ = try? source.read()
                var width = 640, height = 480
                repeat {
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height]
                    let actual = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                    if Int(actual.width) == width && Int(actual.height) == height { break }
                    width = Int(actual.width); height = Int(actual.height)
                } while width > 0 && height > 0
                _ = try? source.read()
                self.queue.async { self.detectFrames(source: source, generation: generation) }

            } catch {
                if configuring { self.session.commitConfiguration() }
                emitFailure("无法打开摄像头：\(error.localizedDescription)")
            }
        }
    }

    /// Analysis state is accessed only on the ordered sample queue.
    private func prepare(generation: UUID, isPreview: Bool, noFaceTimeout: TimeInterval?, measurementDuration: TimeInterval?, handler: @escaping (CameraObservation) -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        self.generation = generation
        self.handler = handler
        self.frameRun.reset(generation: generation, isPreview: isPreview, noFaceTimeout: noFaceTimeout, measurementDuration: measurementDuration)
        if self.predictor == nil {
            do {
                guard let url = Bundle.main.url(forResource: "data", withExtension: "dat") else { throw PipelineError.missingModel }
                let predictor = try DlibShapePredictor(contentsOf: url)
                guard predictor.metadata.sha256 == "c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888" else { throw PipelineError.invalidModel }
                self.predictor = predictor
            } catch { self.report(error: "眨眼检测模型无法加载：\(error.localizedDescription)"); return false }
        }
        if !self.faceModelLoaded {
            do {
                guard let url = Bundle.main.url(forResource: "eyeblink-face-v3", withExtension: "bin") else { throw PipelineError.missingModel }
                let data = try Data(contentsOf: url)
                let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                guard sha == "835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767" else { throw PipelineError.invalidModel }
                var error = [CChar](repeating: 0, count: 512)
                let loaded = url.path.withCString { eyeface_load_model($0, &error, error.count) }
                guard loaded == 1 else { throw PipelineError.faceModel(String(cString: error)) }
                self.faceModelLoaded = true
            } catch { self.report(error: "人脸检测模型无法加载：\(error.localizedDescription)"); return false }
        }
        return true
    }

    func stop() {
        cameraLifecycleLog.notice("camera stop queued")
        sessionQueue.async { [weak self] in self?.stopCapture() }
    }

    /// Session work must not wait behind an AVFoundation sample-delivery drain.
    /// Detach its delegate upstream, then wait for the finite remaining analysis.
    private func stopCapture() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        cameraLifecycleLog.notice("camera stop entered session queue")
        session.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }.forEach { $0.setSampleBufferDelegate(nil, queue: nil) }
        cameraLifecycleLog.notice("camera output delegate cleared")
        // Wake a synchronous read before waiting for the detector to drain.
        source?.close()
        // Invalidate registrations on their owning capture queue. Notification
        // callbacks never synchronously enter sessionQueue, so this cannot form
        // the old stopRunning/sample-delivery circular wait.
        if let failures { captureQueue.sync { failures.stop() } }
        failures = nil
        cameraLifecycleLog.notice("camera failure observers removed")
        session.stopRunning()
        cameraLifecycleLog.notice("camera stopRunning returned")
        if !session.inputs.isEmpty || !session.outputs.isEmpty {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
        }
        cameraLifecycleLog.notice("camera stop configuration committed")
        queue.sync {
            handler = nil
            frameRun.reset(generation: generation, isPreview: false, noFaceTimeout: nil, measurementDuration: nil)
        }
        source = nil; receiver = nil
        cameraLifecycleLog.notice("camera analysis drained")
    }

    func stopAndWait() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.stopCapture()
                continuation.resume()
            }
        }
    }

    private func report(error: String, generation: UUID? = nil, captureFailure: Bool = false) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let handler, let observation = frameRun.fail(generation: generation ?? self.generation, message: error,
            at: ProcessInfo.processInfo.systemUptime, captureFailure: captureFailure) else { return }
        handler(observation)
    }

    private func finishSetupFailure(_ message: String, generation: UUID) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let result = queue.sync { () -> (CameraObservation, (CameraObservation) -> Void)? in
            guard let handler, let value = frameRun.fail(generation: generation, message: message,
                at: ProcessInfo.processInfo.systemUptime, captureFailure: true) else { return nil }
            return (value, handler)
        }
        stopCapture()
        if let (value, handler) = result { handler(value) }
    }

    /// The worker checks completion before waiting for the next camera callback.
    /// Neither analysis nor a slow main thread can block AVFoundation delivery.
    private func detectFrames(source: CameraFrameSource<CVPixelBuffer>, generation: UUID) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let handler, let predictor else { return }
        while true {
            let observation: CameraObservation? = autoreleasepool {
                do { try source.check() }
                catch CameraReadError.cancelled { return nil }
                catch { /* Device failure is observed by read(), after loop completion checks. */ }
                var lockedBuffer: CVPixelBuffer?
                func unlock() {
                    if let buffer = lockedBuffer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                    lockedBuffer = nil
                }
                defer { unlock() }
                return frameRun.process(predictor: predictor, receivedAt: ProcessInfo.processInfo.systemUptime, clock: {
                    let raw = ef_clock_stamp()
                    return FrameTimestamp(ticks: raw.ticks, frequency: raw.frequency)
                }, acquirePixels: {
                    unlock()
                    let buffer = try source.read()
                    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
                        throw CameraFrameAnalysis.AnalysisError.normalization
                    }
                    lockedBuffer = buffer
                    guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw CameraFrameAnalysis.AnalysisError.normalization }
                    return CameraFrameInput(pixels: address.assumingMemoryBound(to: UInt8.self),
                        width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), stride: CVPixelBufferGetBytesPerRow(buffer))
                })
            }
            guard let observation else { return }
            if observation.endsRun {
                // Original releases capture before sending completion/failure.
                // Never synchronously enter sessionQueue from the worker.
                sessionQueue.async { [weak self] in
                    guard let self, self.source === source else { return }
                    self.stopCapture()
                    handler(observation)
                }
                return
            }
            handler(observation)
        }
    }

    enum PipelineError: LocalizedError {
        case missingModel, invalidModel, faceModel(String)
        var errorDescription: String? {
            switch self {
            case .missingModel: return "安装包缺少 data.dat。请重新构建完整应用包。"
            case .invalidModel: return "检测模型与已确认的原版基线不一致。"
            case .faceModel(let message): return message
            }
        }
    }

    enum CameraError: LocalizedError {
        case inputUnavailable, outputUnavailable
        var errorDescription: String? { "设备不支持当前采集配置。" }
    }
}

final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); previewLayer.frame = bounds }
}

struct CameraPreviewView: NSViewRepresentable {
    @ObservedObject var model: AppModel
    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView(frame: .zero)
        view.previewLayer.session = model.cameraPipeline.session
        return view
    }
    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = model.cameraPipeline.session
    }
}
