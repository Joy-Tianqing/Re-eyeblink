import Foundation

/// Legacy history provenance only. The restored original detector does not
/// calibrate contours or use coverage metadata to accept/reject a measurement.
public enum EyeObservationMode: String, Codable, Sendable {
    case both, left, right, mixed
    public var isEstimated: Bool { self != .both }
}

public struct MeasurementDetection: Codable, Equatable, Sendable {
    public var algorithm: String
    public var validFrameFraction: Double
    public var targeting: String?
    public var observationMode: EyeObservationMode?
    public init(algorithm: String, validFrameFraction: Double, observationMode: EyeObservationMode? = nil, targeting: String? = nil) {
        self.algorithm = algorithm; self.validFrameFraction = validFrameFraction; self.observationMode = observationMode; self.targeting = targeting
    }
    public var isMonocularEstimate: Bool { observationMode?.isEstimated == true }
}
