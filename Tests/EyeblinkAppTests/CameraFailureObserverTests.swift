import XCTest
import AVFoundation
@testable import EyeblinkApp

final class CameraFailureObserverTests: XCTestCase {
    func testRuntimeFailureUsesMatchingSessionAndDeliversOnCaptureQueue() {
        let center = NotificationCenter(), queue = DispatchQueue(label: "camera-failure-test")
        let session = NSObject(), device = NSObject(), generation = UUID()
        var received: [(UUID, CameraFailureObserver.Failure)] = []
        let observer = CameraFailureObserver(queue: queue, center: center) { token, error in
            dispatchPrecondition(condition: .onQueue(queue))
            received.append((token, error))
        }
        queue.sync { observer.start(generation: generation, session: session, device: device) }
        center.post(name: AVCaptureSession.runtimeErrorNotification, object: NSObject())
        let failure = NSError(domain: "fixture", code: 7, userInfo: [NSLocalizedDescriptionKey: "capture failed"])
        center.post(name: AVCaptureSession.runtimeErrorNotification, object: session, userInfo: [AVCaptureSessionErrorKey: failure])
        queue.sync {
            XCTAssertEqual(received.count, 1)
            XCTAssertEqual(received.first?.0, generation)
            XCTAssertEqual(received.first?.1, .runtime("capture failed"))
            observer.stop()
        }
    }

    func testDisconnectOnlyMatchesActiveDeviceAndDuplicateTerminalEventsAreCollapsed() {
        let center = NotificationCenter(), queue = DispatchQueue(label: "camera-disconnect-test")
        let session = NSObject(), device = NSObject()
        var received: [CameraFailureObserver.Failure] = []
        let observer = CameraFailureObserver(queue: queue, center: center) { _, error in received.append(error) }
        queue.sync {
            observer.start(generation: UUID(), session: session, device: device)
            center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: NSObject())
            center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: device)
            center.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
        }
        queue.sync {
            XCTAssertEqual(received, [.disconnected])
            observer.stop()
        }
    }

    func testAlreadyQueuedFailureCannotTerminateReplacementLease() {
        let center = NotificationCenter(), queue = DispatchQueue(label: "camera-restart-test")
        let session = NSObject(), device = NSObject(), old = UUID(), replacement = UUID()
        var received: [UUID] = []
        let observer = CameraFailureObserver(queue: queue, center: center) { token, _ in received.append(token) }
        queue.sync {
            observer.start(generation: old, session: session, device: device)
            center.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
            // The old callback is queued behind this block; restart first.
            observer.start(generation: replacement, session: session, device: device)
        }
        queue.sync { XCTAssertTrue(received.isEmpty) }
        center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: device)
        queue.sync {
            XCTAssertEqual(received, [replacement])
            observer.stop()
        }
    }

    func testIntentionalStopAndDestructionUnregisterNotifications() {
        let center = NotificationCenter(), queue = DispatchQueue(label: "camera-stop-test")
        let session = NSObject(), device = NSObject()
        var count = 0
        var observer: CameraFailureObserver? = CameraFailureObserver(queue: queue, center: center) { _, _ in count += 1 }
        queue.sync {
            observer?.start(generation: UUID(), session: session, device: device)
            center.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
            observer?.stop()
        }
        queue.sync { XCTAssertEqual(count, 0) }
        queue.sync { observer?.start(generation: UUID(), session: session, device: device); observer = nil }
        center.post(name: AVCaptureDevice.wasDisconnectedNotification, object: device)
        queue.sync { XCTAssertEqual(count, 0) }
    }

    func testInterruptionMatchesSessionAndCollapsesFollowingRuntimeError() {
        let center = NotificationCenter(), queue = DispatchQueue(label: "camera-interruption-test")
        let session = NSObject(), device = NSObject(), generation = UUID()
        var received: [CameraFailureObserver.Failure] = []
        let observer = CameraFailureObserver(queue: queue, center: center) { token, error in
            XCTAssertEqual(token, generation)
            received.append(error)
        }
        queue.sync {
            observer.start(generation: generation, session: session, device: device)
            center.post(name: AVCaptureSession.wasInterruptedNotification, object: NSObject())
            center.post(name: AVCaptureSession.wasInterruptedNotification, object: session)
            center.post(name: AVCaptureSession.runtimeErrorNotification, object: session)
        }
        queue.sync {
            XCTAssertEqual(received, [.interrupted])
            observer.stop()
        }
    }
}
