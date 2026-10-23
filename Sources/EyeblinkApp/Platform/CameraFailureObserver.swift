import AVFoundation
import Foundation

/// AVFoundation notifications may arrive on any thread. Bind each registration
/// to its capture lease, then deliver failures on the same queue as frame analysis.
final class CameraFailureObserver {
    enum Failure: Equatable {
        case runtime(String?)
        case disconnected
        case interrupted
    }

    private let queue: DispatchQueue
    private let center: NotificationCenter
    private let handler: (UUID, Failure) -> Void
    private var observers: [NSObjectProtocol] = []
    private var generation: UUID?

    init(queue: DispatchQueue, center: NotificationCenter = .default, handler: @escaping (UUID, Failure) -> Void) {
        self.queue = queue; self.center = center; self.handler = handler
    }

    func start(generation: UUID, session: AnyObject, device: AnyObject) {
        dispatchPrecondition(condition: .onQueue(queue))
        stop()
        self.generation = generation
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.enqueue(.runtime(error?.localizedDescription), generation: generation)
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) { [weak self] _ in
            self?.enqueue(.disconnected, generation: generation)
        })
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.enqueue(.interrupted, generation: generation)
        })
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        generation = nil
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func enqueue(_ failure: Failure, generation: UUID) {
        queue.async { [weak self] in
            guard let self, self.generation == generation else { return }
            // A disconnect can also produce a runtime error. Deliver one terminal
            // result, and reject callbacks already queued before a later restart.
            self.stop()
            self.handler(generation, failure)
        }
    }

    deinit { observers.forEach(center.removeObserver) }
}
