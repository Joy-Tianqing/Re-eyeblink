import Foundation

/// Preserve the capture queue's submission order across the main-actor bridge.
/// In particular, ready must reach the controller before analyzed frames.
enum CameraObservationDelivery {
    static func send(_ observation: CameraObservation,
                     to receive: @MainActor @Sendable @escaping (CameraObservation) -> Void) {
        DispatchQueue.main.async { receive(observation) }
    }
}
