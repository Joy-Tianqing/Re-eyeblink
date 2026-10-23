import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable { case simplifiedChinese = "zh-CN", english = "en" }
public enum TrainingMode: String, Codable, CaseIterable, Sendable { case simple, interactive }

/// Fixed controller timings; these were never editable original Mac controls.
public enum OriginalSchedule {
    public static let exerciseInterval: TimeInterval = 1140
    public static let measurementInterval: TimeInterval = 1800
    public static let measurementDuration: TimeInterval = 180
}

/// Original QSpinBox limits, recovered with each widget's object name.
/// Units match the controls; the engine itself also accepts controlled test clocks.
public enum OriginalControlRanges {
    public static let trainingSeconds: ClosedRange<Double> = 2...60
    public static let breakMinutes: ClosedRange<Double> = 15...80
    public static let naturalMinutes: ClosedRange<Double> = 2...9
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage = .simplifiedChinese
    public var trainingEnabled = true
    public var trainingInterval: TimeInterval = 30
    public var trainingMode: TrainingMode = .interactive
    public var mgdEnabled = false
    public var reminderSoundEnabled = false
    public var exerciseEnabled = true
    // Original UI says 20 minutes; recovered scheduler uses 1,140,000 ms (19 min).
    public var exerciseInterval: TimeInterval = OriginalSchedule.exerciseInterval
    public var breakEnabled = true
    public var breakInterval: TimeInterval = 50 * 60
    public var naturalBreaksEnabled = true
    public var naturalBreakDuration: TimeInterval = 3 * 60
    public var measurementEnabled = true
    public var measurementInterval: TimeInterval = OriginalSchedule.measurementInterval
    public var measurementDuration: TimeInterval = OriginalSchedule.measurementDuration
    public var measurementNotifications = true
    public var cameraEnabled = true
    public var launchAtLogin = false
    public var researchSharingEnabled = false
    public var pauseCameraKeywords: [String] = []
    public var pauseProcessKeywords: [String] = []
    public var pauseWindowKeywords: [String] = []
    public var pauseCameraFrontmostOnly = true
    public init() {}

    /// Reject malformed persisted intervals; production defaults remain unchanged.
    public func validated() -> AppSettings {
        var copy = self
        let defaults = AppSettings()
        for key in [\AppSettings.trainingInterval, \.exerciseInterval, \.breakInterval, \.naturalBreakDuration, \.measurementInterval, \.measurementDuration] {
            if !copy[keyPath: key].isFinite || copy[keyPath: key] <= 0 { copy[keyPath: key] = defaults[keyPath: key] }
        }
        return copy
    }

    /// The native interface and persisted user preferences share the source
    /// controls' bounds. Older rebuild preferences outside them are normalized.
    public func validatedForInterface() -> AppSettings {
        var copy = validated()
        func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
            min(range.upperBound, max(range.lowerBound, value.rounded(.towardZero)))
        }
        copy.trainingInterval = clamp(copy.trainingInterval, to: OriginalControlRanges.trainingSeconds)
        copy.breakInterval = clamp(copy.breakInterval / 60, to: OriginalControlRanges.breakMinutes) * 60
        copy.naturalBreakDuration = clamp(copy.naturalBreakDuration / 60, to: OriginalControlRanges.naturalMinutes) * 60
        copy.exerciseInterval = OriginalSchedule.exerciseInterval
        copy.measurementInterval = OriginalSchedule.measurementInterval
        copy.measurementDuration = OriginalSchedule.measurementDuration
        return copy
    }
}

public enum PauseReason: Hashable, Codable, Sendable {
    case user, systemSleep, process(String), window(String), custom(String)
}
public enum CameraPauseReason: Hashable, Codable, Sendable {
    case user, window(String), permissionDenied, unavailable, custom(String)
}
public enum ExerciseKind: String, Codable, CaseIterable, Sendable {
    case lookFar, squeezeBlink, lookSideways, rotateEyes
}
public enum Reminder: Equatable, Sendable {
    case training(TrainingMode, mgd: Bool)
    /// A real, accepted training blink has completed. Keep the panel until the
    /// one-shot visual acknowledgement finishes, without retaining the camera.
    case trainingFeedback(UUID)
    /// Detection stopped without accepting a blink. Keep the prompt visible so
    /// an unsuccessful attempt cannot look like successful completion.
    case trainingInterrupted(CameraDetectionFailure)
    case exercise(ExerciseKind, secondsRemaining: TimeInterval)
    // Completion is driven by sampled idle time, not a wall-clock countdown.
    case rest

    public var trainingFeedbackID: UUID? {
        if case .trainingFeedback(let id) = self { return id }
        return nil
    }
    public var isTraining: Bool {
        switch self {
        case .training, .trainingFeedback, .trainingInterrupted: return true
        case .exercise, .rest: return false
        }
    }
}
public enum CameraDetectionFailure: Equatable, Sendable { case noFace }

public enum CameraPurpose: String, Codable, CaseIterable, Sendable { case preview, measurement, training }
public enum MeasurementTiming: Equatable, Sendable { case originalElapsedTime, validSamples }

/// Recovered scheduler defaults, with configurable timing for controlled tests.
/// Camera preview arbitration follows the original explicit preview mode; all
/// feature scheduling is non-preemptive. See evidence/static/recovered-rules/.
public struct EnginePolicy: Equatable, Sendable {
    public var cameraPriority: [CameraPurpose] = [.preview, .measurement, .training]
    public var exerciseSequence = ExerciseKind.allCases
    public var exerciseStepDuration: TimeInterval = 10
    public var snoozeDuration: TimeInterval = 5 * 60
    public var naturalBreakResetsExercise = true
    public var startupQuietPeriod: TimeInterval = 15
    public var featurePollingInterval: TimeInterval = 2
    public var naturalBreakCheckInterval: TimeInterval = 60
    public var trainingObservationDuration: TimeInterval = 4.001
    public var simpleReminderDuration: TimeInterval = 3
    public var trainingDelayAfterBreakOrExercise: TimeInterval = 20
    public var exerciseBreakSeparation: TimeInterval = 301
    public var measurementTiming: MeasurementTiming = .originalElapsedTime
    public var firstMeasurementDelay: TimeInterval = 120
    public var measurementFailureDelay: TimeInterval = 480
    public var measurementNoFaceTimeout: TimeInterval = 8
    public var trainingNoFaceTimeout: TimeInterval = 1
    public init() {}
}

public struct EngineState: Equatable, Sendable {
    public var pauseReasons: Set<PauseReason> = []
    public var cameraPauseReasons: Set<CameraPauseReason> = []
    public var reminder: Reminder?
    public var cameraPurpose: CameraPurpose?
    public var cameraToken: UUID?
    public var measurement: MeasurementSession?
    public var measurementRequested = false
    public var trainingRemaining: TimeInterval = 30
    public var exerciseRemaining: TimeInterval = 19 * 60
    public var breakRemaining: TimeInterval = 50 * 60
    public var measurementRemaining: TimeInterval = 30 * 60
    public var previewRequested = false
    public var trainingSessionActive = false
    public var cameraHasStarted = false
    public var lastDetectionFailure: String?
    public var isPaused: Bool { !pauseReasons.isEmpty }
    public var cameraPaused: Bool { isPaused || !cameraPauseReasons.isEmpty }
    public init() {}
}

public enum EngineEffect: Equatable, Sendable {
    case playReminderSound
    case measurementCompleted(MeasurementRecord)
    case measurementCancelled(UUID)
    case restTransition(RestTransition)
}

/// Emitted by the branch that changes a production rest, never inferred from a
/// reset countdown. Preview reminders do not enter the scheduler's rest state.
public struct RestTransition: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case started, idleCompletion, skipped, snoozed, disabled, paused, cameraPreview
    }
    public let kind: Kind
    public let uptime: TimeInterval
    public let idleDuration: TimeInterval?
    public init(kind: Kind, uptime: TimeInterval, idleDuration: TimeInterval? = nil) {
        self.kind = kind; self.uptime = uptime; self.idleDuration = idleDuration
    }
}
