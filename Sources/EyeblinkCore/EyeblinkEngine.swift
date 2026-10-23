import Foundation

/// Monotonic-clock implementation of the recovered controller rules. OS work is
/// performed by one application adapter. Detection-model equivalence is separate.
public struct EyeblinkEngine: Sendable {
    public private(set) var settings: AppSettings
    public private(set) var state: EngineState
    public var policy: EnginePolicy
    private var previousTime: TimeInterval
    private var quietUntil: TimeInterval
    private var nextNaturalCheck: TimeInterval
    private var nextFeatureCheck: TimeInterval
    private var effects: [EngineEffect] = []
    private var exerciseIndex = 0
    private var trainingStartedAt: TimeInterval?
    private var simpleStartedAt: TimeInterval?
    private var lastTrainingSample: TimeInterval?
    private var latestIdleDuration: TimeInterval = 0

    public init(settings: AppSettings = .init(), now: TimeInterval = 0, policy: EnginePolicy = .init()) {
        self.settings = settings.validated(); self.policy = policy
        let now = now.isFinite ? now : 0
        previousTime = now; quietUntil = now + policy.startupQuietPeriod
        nextNaturalCheck = now + policy.naturalBreakCheckInterval
        nextFeatureCheck = now
        state = .init()
        state.trainingRemaining = self.settings.trainingInterval
        state.exerciseRemaining = self.settings.exerciseInterval
        state.breakRemaining = self.settings.breakInterval
        state.measurementRemaining = self.settings.measurementEnabled ? policy.firstMeasurementDelay : self.settings.measurementInterval
    }
    public var cameraNoFaceTimeout: TimeInterval? {
        switch state.cameraPurpose {
        case .measurement: return policy.measurementNoFaceTimeout
        case .training: return policy.trainingNoFaceTimeout
        case .preview, nil: return nil
        }
    }

    public mutating func cameraMeasurementFinished(token: UUID, at now: TimeInterval) {
        guard token == state.cameraToken, state.cameraPurpose == .measurement,
              state.cameraHasStarted, policy.measurementTiming == .originalElapsedTime,
              var session = state.measurement, now.isFinite, now >= session.startedAt else { return }
        // The capture sequence owns the raw-clock deadline. A main timer may
        // already have advanced progress while the last frame was in flight.
        _ = elapse(to: now)
        session.elapsedDuration = max(0, now - session.startedAt)
        completeMeasurement(session)
    }

    /// Model decides this at the top of its next worker iteration, before read().
    /// A UI tick or a frame notification cannot substitute for that decision.
    public mutating func cameraTrainingProgress(token: UUID, blinkDetected: Bool, at now: TimeInterval) {
        guard token == state.cameraToken, state.cameraPurpose == .training,
              state.cameraHasStarted, now.isFinite, now >= (trainingStartedAt ?? now) else { return }
        _ = elapse(to: now)
        if blinkDetected {
            state.reminder = nil
            stopTraining()
            reconcileCamera()
        } else if !settings.mgdEnabled {
            showTraining(.interactive)
        }
    }

    /// Original camera errors {2,3,5,6,8}: interactive -> three-second simple
    /// reminder, measurement -> retry after eight minutes. No permanent pause.
    public mutating func cameraCaptureFailed(token: UUID, at now: TimeInterval) {
        guard token == state.cameraToken, now.isFinite else { return }
        _ = elapse(to: now)
        switch state.cameraPurpose {
        case .training:
            stopTraining()
            state.lastDetectionFailure = "training-capture"
            state.reminder = nil
            simpleStartedAt = now
            showTraining(.simple)
        case .measurement:
            state.lastDetectionFailure = "measurement-capture"
            cancelMeasurementInternal()
        case .preview:
            state.previewRequested = false
            state.lastDetectionFailure = "preview-capture"
        case nil: return
        }
        reconcileCamera()
    }

    /// The detector reports its terminal decision before processing that frame.
    /// Do not advance scheduler completion: a late failed frame must never save.
    public mutating func cameraDetectionFailed(token: UUID, reason: CameraDetectionFailure, at now: TimeInterval) {
        guard token == state.cameraToken, now.isFinite else { return }
        switch (state.cameraPurpose, reason) {
        case (.measurement, .noFace):
            _ = elapse(to: now)
            state.lastDetectionFailure = "measurement-no-face"
            cancelMeasurementInternal()
        case (.training, .noFace):
            _ = elapse(to: now)
            state.lastDetectionFailure = "training-no-face"
            interruptTraining(reason)
        default: return
        }
        reconcileCamera()
    }

    public mutating func takeEffects() -> [EngineEffect] { defer { effects.removeAll() }; return effects }

    public mutating func updateSettings(_ settings: AppSettings, at now: TimeInterval) {
        advance(to: now)
        let old = self.settings; self.settings = settings.validated()
        if old.trainingInterval != self.settings.trainingInterval || (!old.trainingEnabled && self.settings.trainingEnabled) {
            state.trainingRemaining = self.settings.trainingInterval
        }
        if old.exerciseInterval != self.settings.exerciseInterval { state.exerciseRemaining = self.settings.exerciseInterval }
        if old.breakInterval != self.settings.breakInterval { state.breakRemaining += self.settings.breakInterval - old.breakInterval }
        if old.measurementInterval != self.settings.measurementInterval { state.measurementRemaining = self.settings.measurementInterval }
        if old.measurementEnabled && !self.settings.measurementEnabled { cancelMeasurementInternal() }
        if !old.measurementEnabled && self.settings.measurementEnabled { state.measurementRemaining = policy.firstMeasurementDelay }
        if !self.settings.trainingEnabled { stopTraining(); if state.reminder?.isTraining == true { state.reminder = nil; simpleStartedAt = nil } }
        if !self.settings.exerciseEnabled, case .exercise = state.reminder { state.reminder = nil }
        if !self.settings.breakEnabled { endRest(.disabled) }
        reconcileCamera()
    }
    public mutating func setPaused(_ paused: Bool, reason: PauseReason = .user, at now: TimeInterval) {
        advance(to: now)
        let wasPaused = state.isPaused
        if paused { state.pauseReasons.insert(reason) } else { state.pauseReasons.remove(reason) }
        if state.isPaused {
            // pauseProgram hides an active simple reminder through
            // hideBlinkReminder, which restarts its training timer.
            if simpleStartedAt != nil { state.trainingRemaining = settings.trainingInterval }
            endRest(.paused); state.reminder = nil; simpleStartedAt = nil; stopTraining(); cancelMeasurementInternal()
        }
        else if wasPaused {
            quietUntil = now + policy.startupQuietPeriod
            state.breakRemaining = settings.breakInterval; state.exerciseRemaining = settings.exerciseInterval
        }
        reconcileCamera()
    }
    public mutating func setCameraPaused(_ paused: Bool, reason: CameraPauseReason = .user, at now: TimeInterval) {
        advance(to: now)
        if paused { state.cameraPauseReasons.insert(reason) } else { state.cameraPauseReasons.remove(reason) }
        reconcileCamera()
    }
    public mutating func setPreview(_ enabled: Bool, at now: TimeInterval) {
        advance(to: now); state.previewRequested = enabled
        if enabled {
            // Original enableLivePreview dispatches through quitBreak,
            // exerciseFinished, or hideBlinkReminder before opening preview.
            // Clearing the panel alone leaves an expired feature queued.
            switch state.reminder {
            case .rest: finishRest(kind: .cameraPreview)
            case .exercise: finishExercise()
            case .training, .trainingFeedback, .trainingInterrupted: state.trainingRemaining = settings.trainingInterval
            case nil: break
            }
            state.reminder = nil; simpleStartedAt = nil; stopTraining(); cancelMeasurementInternal()
            state.lastDetectionFailure = nil
        }
        reconcileCamera()
    }
    public mutating func cancelMeasurement(at now: TimeInterval) {
        advance(to: now); state.measurementRequested = false; cancelMeasurementInternal(); reconcileCamera()
    }
    /// Call before changing devices or restarting an interrupted capture session.
    /// Frames from the old hardware lease cannot acquire the replacement token.
    public mutating func invalidateCamera(at now: TimeInterval) {
        advance(to: now); cancelMeasurementInternal(); stopTraining()
        state.cameraPurpose = nil; state.cameraToken = nil; reconcileCamera()
    }
    /// The original starts training/measurement observation after camera initialization.
    /// The OS adapter calls this on its first frame, before delivering that frame.
    public mutating func cameraDidStart(token: UUID, at now: TimeInterval) {
        guard token == state.cameraToken, !state.cameraHasStarted else { return }
        _ = elapse(to: now)
        state.cameraHasStarted = true
        if state.trainingSessionActive {
            trainingStartedAt = now
            if settings.mgdEnabled { showTraining(.interactive) }
        }
        if var session = state.measurement {
            session.startedAt = now; session.elapsedDuration = 0; state.measurement = session
        }
    }

    public mutating func advance(to now: TimeInterval, idleDuration: TimeInterval? = nil, date: Date = Date()) {
        guard let elapsed = elapse(to: now) else { return }
        guard !state.isPaused else { return }
        if let idleDuration { latestIdleDuration = idleDuration.isFinite ? max(0, idleDuration) : 0 }
        let idle = latestIdleDuration
        // Button/settings events advance time without fabricating a fresh idle sample.
        if idleDuration != nil, now >= nextNaturalCheck {
            nextNaturalCheck = now + max(0.001, policy.naturalBreakCheckInterval)
            // Original checkPresence is strictly greater, and runs once per minute.
            if idle > settings.naturalBreakDuration {
                if settings.naturalBreaksEnabled {
                    state.breakRemaining = settings.breakInterval
                    if policy.naturalBreakResetsExercise { state.exerciseRemaining = settings.exerciseInterval }
                }
                if case .rest = state.reminder { finishRest(idleDuration: idle) }
                if case .exercise = state.reminder { finishExercise() }
            }
        }
        if case .exercise(let kind, let remaining) = state.reminder {
            if remaining <= elapsed { finishExercise() }
            else { state.reminder = .exercise(kind, secondsRemaining: remaining - elapsed) }
        }
        if let started = simpleStartedAt, now - started >= policy.simpleReminderDuration {
            state.reminder = nil; simpleStartedAt = nil; state.trainingRemaining = settings.trainingInterval
        }
        if policy.measurementTiming == .originalElapsedTime, var session = state.measurement {
            session.elapsedDuration = max(0, now - session.startedAt); state.measurement = session
        }
        guard now >= nextFeatureCheck, now >= quietUntil, !state.previewRequested else { reconcileCamera(); return }
        nextFeatureCheck = now + max(0.001, policy.featurePollingInterval)
        // accessFeature does not preempt an active feature. This is a single arbiter.
        guard state.reminder == nil, state.measurement == nil, !state.trainingSessionActive else { reconcileCamera(); return }
        if (state.measurementRequested || (settings.measurementEnabled && state.measurementRemaining <= 0)), cameraAvailable {
            createMeasurement(at: now, date: date)
        } else if settings.breakEnabled, state.breakRemaining <= 0 {
            state.trainingRemaining = policy.trainingDelayAfterBreakOrExercise
            state.reminder = .rest
            effects.append(.restTransition(.init(kind: .started, uptime: previousTime)))
        } else if settings.exerciseEnabled, state.exerciseRemaining <= 0,
                  state.breakRemaining >= policy.exerciseBreakSeparation, !policy.exerciseSequence.isEmpty {
            let kind = policy.exerciseSequence[exerciseIndex % policy.exerciseSequence.count]
            state.trainingRemaining = policy.trainingDelayAfterBreakOrExercise
            state.reminder = .exercise(kind, secondsRemaining: policy.exerciseStepDuration)
        } else if settings.trainingEnabled, state.trainingRemaining <= 0 {
            if settings.trainingMode == .simple || !cameraAvailable {
                simpleStartedAt = now; showTraining(.simple)
            } else {
                state.trainingSessionActive = true; trainingStartedAt = now; state.lastDetectionFailure = nil
            }
        }
        reconcileCamera()
    }

    /// A busy controller queues this request; the next accessFeature poll starts it.
    @discardableResult public mutating func startMeasurement(at now: TimeInterval, date: Date = Date()) -> UUID? {
        advance(to: now, date: date)
        guard cameraAvailable, !state.previewRequested else { return nil }
        state.measurementRequested = true
        if state.reminder == nil, !state.trainingSessionActive, now >= quietUntil { createMeasurement(at: now, date: date) }
        reconcileCamera(); return state.measurement?.id
    }
    private mutating func createMeasurement(at now: TimeInterval, date: Date) {
        if state.measurement == nil {
            var session = MeasurementSession(date: date, targetDuration: settings.measurementDuration)
            session.timing = policy.measurementTiming
            session.startedAt = now; state.measurement = session; state.lastDetectionFailure = nil
        }
        state.measurementRequested = false; reconcileCamera()
    }

    /// Each frame carries tokens captured when its camera callback was installed.
    /// A frame may legitimately precede a queued UI timer tick; per-stream ordering
    /// and tokens reject stale input without comparing it against the timer clock.
    public mutating func sample(cameraToken: UUID, token: UUID?, at now: TimeInterval, faceValid: Bool, blinkDurations: [TimeInterval]) {
        guard cameraAvailable, cameraToken == state.cameraToken, now.isFinite else { return }
        if state.cameraPurpose == .measurement, token != state.measurement?.id { return }
        cameraDidStart(token: cameraToken, at: now)
        let blinks = blinkDurations.filter { $0.isFinite && $0 > 0 }
        if state.cameraPurpose == .measurement {
            guard let token, var session = state.measurement, token == session.id,
                  now >= session.startedAt, session.previousSample.map({ now > $0 }) ?? true else { return }
            if now > previousTime { _ = elapse(to: now) }
            let previousCount = session.blinkDurations.count
            session.sample(at: now, valid: faceValid, blinks: blinks)
            if policy.measurementTiming == .originalElapsedTime,
               previousCount == session.blinkDurations.count { session.blinkDurations.append(contentsOf: blinks) }
            session.elapsedDuration = max(0, now - session.startedAt)
            state.measurement = session
            if policy.measurementTiming == .validSamples, session.validDuration >= session.targetDuration { completeMeasurement(session) }
        } else if state.cameraPurpose == .training {
            guard token == nil, now >= (trainingStartedAt ?? now), lastTrainingSample.map({ now > $0 }) ?? true else { return }
            if now > previousTime { _ = elapse(to: now) }
            lastTrainingSample = now
            // The worker retains its count and checks it before the next read.
            // Completion arrives via cameraTrainingProgress after capture release.
        }
    }
    private mutating func completeMeasurement(_ session: MeasurementSession) {
        let duration = policy.measurementTiming == .originalElapsedTime ? session.elapsedDuration : session.validDuration
        let rateDuration = policy.measurementTiming == .originalElapsedTime ? session.targetDuration : nil
        let record = MeasurementRecord(id: session.id, date: session.date, validDuration: duration, blinkDurations: session.blinkDurations, frequencyDuration: rateDuration)
        effects.append(.measurementCompleted(record)); state.measurement = nil
        state.measurementRemaining = settings.measurementInterval; reconcileCamera()
    }
    public mutating func dismissReminder(at now: TimeInterval) {
        advance(to: now)
        switch state.reminder {
        case .training, .trainingFeedback, .trainingInterrupted: stopTraining(); simpleStartedAt = nil; state.trainingRemaining = settings.trainingInterval
        case .exercise: finishExercise()
        case .rest: endRest(.skipped); state.breakRemaining = settings.breakInterval
        case nil: break
        }
        state.reminder = nil; reconcileCamera()
    }
    /// Identity-gated acknowledgement: a cancelled/old animation must never
    /// dismiss a later prompt, rest, exercise, or a new training completion.
    @discardableResult public mutating func finishTrainingFeedback(id: UUID, at now: TimeInterval) -> Bool {
        guard state.reminder?.trainingFeedbackID == id else { return false }
        _ = elapse(to: now)
        state.reminder = nil
        state.trainingRemaining = settings.trainingInterval
        reconcileCamera()
        return true
    }
    /// Retry the visible unfinished prompt through the existing camera arbiter.
    @discardableResult public mutating func retryTraining(at now: TimeInterval) -> Bool {
        guard case .trainingInterrupted = state.reminder, settings.trainingEnabled,
              !state.isPaused, cameraAvailable, !state.previewRequested, elapse(to: now) != nil else { return false }
        state.lastDetectionFailure = nil
        state.trainingSessionActive = true
        trainingStartedAt = now; lastTrainingSample = nil
        state.reminder = .training(.interactive, mgd: settings.mgdEnabled)
        reconcileCamera()
        return true
    }
    public mutating func snoozeBreak(at now: TimeInterval) {
        advance(to: now)
        guard case .rest = state.reminder else { return }
        endRest(.snoozed); state.breakRemaining = policy.snoozeDuration
    }
    private mutating func showTraining(_ mode: TrainingMode) {
        guard state.reminder == nil else { return }
        state.reminder = .training(mode, mgd: settings.mgdEnabled)
        if settings.reminderSoundEnabled { effects.append(.playReminderSound) }
    }
    private mutating func finishExercise() {
        exerciseIndex += 1; state.reminder = nil; state.exerciseRemaining = settings.exerciseInterval
    }
    private mutating func finishRest(kind: RestTransition.Kind = .idleCompletion, idleDuration: TimeInterval? = nil) {
        endRest(kind, idleDuration: idleDuration)
        state.breakRemaining = settings.breakInterval; state.exerciseRemaining = settings.exerciseInterval
    }
    private mutating func endRest(_ kind: RestTransition.Kind, idleDuration: TimeInterval? = nil) {
        guard case .rest = state.reminder else { return }
        effects.append(.restTransition(.init(kind: kind, uptime: previousTime, idleDuration: idleDuration)))
        state.reminder = nil
    }
    private mutating func stopTraining() {
        let wasActive = state.trainingSessionActive
        state.trainingSessionActive = false; trainingStartedAt = nil; lastTrainingSample = nil
        if wasActive { state.trainingRemaining = settings.trainingInterval }
    }
    private mutating func interruptTraining(_ reason: CameraDetectionFailure) {
        // Error 4 (no face) calls hideBlinkReminder in the shipped controller.
        if state.reminder?.isTraining == true { state.reminder = nil }
        stopTraining()
    }
    private var cameraAvailable: Bool { settings.cameraEnabled && !state.cameraPaused }
    private mutating func cancelMeasurementInternal() {
        guard let id = state.measurement?.id else { return }
        effects.append(.measurementCancelled(id))
        state.measurement = nil; state.measurementRemaining = policy.measurementFailureDelay
    }
    private mutating func reconcileCamera() {
        let previous = state.cameraPurpose
        if !cameraAvailable {
            state.cameraPurpose = nil; state.cameraToken = nil; state.cameraHasStarted = false; cancelMeasurementInternal(); stopTraining()
            if case .training(.interactive, _) = state.reminder { state.reminder = nil }
            return
        }
        let requested: Set<CameraPurpose> = Set([
            state.previewRequested ? .preview : nil,
            state.measurement != nil ? .measurement : nil,
            state.trainingSessionActive ? .training : nil
        ].compactMap { $0 })
        state.cameraPurpose = policy.cameraPriority.first { requested.contains($0) }
        if state.measurement != nil, state.cameraPurpose != .measurement { cancelMeasurementInternal() }
        if previous != state.cameraPurpose { state.cameraToken = state.cameraPurpose == nil ? nil : UUID(); state.cameraHasStarted = false }
    }
    private mutating func elapse(to now: TimeInterval) -> TimeInterval? {
        guard now.isFinite, now >= previousTime else { return nil }
        let elapsed = now - previousTime; previousTime = now
        // The original training/measurement QTimers keep their deadlines during
        // global pause. Only dispatch is suspended, including the resume quiet period.
        if settings.trainingEnabled, !state.trainingSessionActive, simpleStartedAt == nil,
           state.reminder?.isTraining != true { state.trainingRemaining -= elapsed }
        if settings.measurementEnabled, state.measurement == nil { state.measurementRemaining -= elapsed }
        guard !state.isPaused else { return elapsed }
        if settings.exerciseEnabled { state.exerciseRemaining -= elapsed }
        if settings.breakEnabled { state.breakRemaining -= elapsed }
        return elapsed
    }
}

public struct AutomaticPauseMatches: Equatable, Sendable {
    public var all: Set<PauseReason>
    public var camera: Set<CameraPauseReason>
    /// Providers are synchronous and called only for configured rule sources.
    public static func evaluate(settings: AppSettings, processes: () -> [String], windowTitles: () -> (all: [String], frontmost: [String])) -> AutomaticPauseMatches {
        func configured(_ keywords: [String]) -> Bool {
            keywords.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let processValues = configured(settings.pauseProcessKeywords) ? processes() : []
        let needsWindows = configured(settings.pauseWindowKeywords) || configured(settings.pauseCameraKeywords)
        let windows = needsWindows ? windowTitles() : (all: [], frontmost: [])
        return evaluate(settings: settings, processes: processValues, windowTitles: windows.all, frontmostWindowTitles: windows.frontmost)
    }
    public static func evaluate(settings: AppSettings, processes: [String], windowTitles: [String], frontmostWindowTitles: [String]) -> AutomaticPauseMatches {
        func matches(_ keywords: [String], in values: [String]) -> [String] {
            keywords.filter { keyword in
                let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                return !term.isEmpty && values.contains { $0.localizedCaseInsensitiveContains(term) }
            }
        }
        let processNames = Set(processes.map { $0.lowercased() })
        let matchedProcesses = settings.pauseProcessKeywords.filter {
            let name = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !name.isEmpty && processNames.contains(name)
        }
        return .init(all: Set(matchedProcesses.map(PauseReason.process) + matches(settings.pauseWindowKeywords, in: windowTitles).map(PauseReason.window)), camera: Set(matches(settings.pauseCameraKeywords, in: settings.pauseCameraFrontmostOnly ? frontmostWindowTitles : windowTitles).map(CameraPauseReason.window)))
    }
}
