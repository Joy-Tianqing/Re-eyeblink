import Foundation
import AVFoundation

enum CameraReadError: Error {
    case cancelled, timeout
    case device(String)
}

/// Shipped OpenCV CaptureDelegate waits for the next callback at each read,
/// retaining only the latest buffer. It does not replay a queue of old images.
/// Producer delivery and the synchronous detector run on separate queues.
final class CameraFrameSource<Frame>: @unchecked Sendable {
    private let condition = NSCondition()
    private var latest: Frame?
    private var revision: UInt64 = 0
    private var failure: CameraReadError?

    func publish(_ frame: Frame) {
        condition.lock(); defer { condition.unlock() }
        guard failure == nil else { return }
        latest = frame; revision &+= 1
        condition.signal()
    }

    func close(_ error: CameraReadError = .cancelled) {
        condition.lock(); defer { condition.unlock() }
        guard failure == nil else { return }
        failure = error; latest = nil
        condition.broadcast()
    }

    func check() throws {
        condition.lock(); defer { condition.unlock() }
        if let failure { throw failure }
    }

    /// One second is CvCaptureCAM::grabFrame's actual read timeout, not a
    /// training/no-face watchdog. onWait permits deterministic rendezvous tests.
    func read(timeout: TimeInterval = 1, onWait: () -> Void = {}) throws -> Frame {
        condition.lock(); defer { condition.unlock() }
        if let failure { throw failure }
        let initial = revision
        let deadline = Date(timeIntervalSinceNow: timeout)
        onWait()
        while revision == initial, failure == nil {
            if !condition.wait(until: deadline) { throw CameraReadError.timeout }
        }
        if let failure { throw failure }
        guard let latest else { throw CameraReadError.timeout }
        return latest
    }
}

final class CameraFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let source: CameraFrameSource<CVPixelBuffer>
    init(source: CameraFrameSource<CVPixelBuffer>) { self.source = source }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            source.close(.device("摄像头返回了空图像。")); return
        }
        source.publish(buffer)
    }
}
