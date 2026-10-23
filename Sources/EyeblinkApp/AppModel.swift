import AppKit
import SwiftUI
import Combine
import AVFoundation
import ServiceManagement
import EyeblinkCore
import OSLog

private let restLog = Logger(subsystem: "org.reeyeblink.app", category: "RestLifecycle")
private let systemPauseLog = Logger(subsystem: "org.reeyeblink.app", category: "SystemPause")

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published private(set) var measurements: [MeasurementRecord] = []
    @Published private(set) var statusText = "正在准备"
    @Published private(set) var cameraStatus = "相机尚未启用"
    @Published private(set) var cameraAuthorized = false
    @Published private(set) var isPaused = false
    @Published private(set) var isCameraPaused = false
    @Published private(set) var isMeasuring = false
    @Published private(set) var measurementProgress = 0.0
    @Published private(set) var latestBlinkRate: Double?
    @Published private(set) var cameraDevices: [CameraDevice] = []
    @Published var selectedCameraID = ""
    @Published private(set) var cameraPreviewEnabled = false
    @Published private(set) var framesPerSecond = 0.0
    @Published private(set) var blinkCount = 0
    @Published private(set) var nextExerciseRemaining: TimeInterval = 20 * 60
    @Published private(set) var nextBreakRemaining: TimeInterval = 50 * 60
    @Published private(set) var isTakingBreak = false
    @Published var lastError: String?
    @Published private(set) var hasCameraFailure = false
    @Published private(set) var isClearingMeasurements = false
    @Published private(set) var isShuttingDown = false
    @Published private(set) var loginApprovalRequired = false
    @Published private(set) var windowTitlePermissionGranted = false
    let cameraPipeline = CameraPipeline()
    let notifications: MeasurementNotifications
    var onOpenMainWindow: (() -> Void)?
    private(set) var engine: EyeblinkEngine
    private let settingsURL: URL
    private let persistence: MeasurementHistoryCoordinator
    private var activeCameraToken: UUID?
    private var activeDeviceID: String?
    private var ticker: AnyCancellable?
    private var systemPauseObserver: SystemPauseObserver?
    private var automaticAll: Set<PauseReason> = []
    private var automaticCamera: Set<CameraPauseReason> = []
    private var overlay: ReminderWindowController?
    private var ticks = 0
    private var previewReminder: Reminder?
    private var previewExpires: TimeInterval = 0
    private var pendingMeasurement = false
    private var cameraFailureMessage: String?
    private var idleTracker = SampledIdleTracker(now: ProcessInfo.processInfo.systemUptime, cursor: NSEvent.mouseLocation, keyCount: CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown))

    init(dataDirectory: URL? = nil, historyStore: (any MeasurementHistory)? = nil, observesSystemEvents: Bool = true, notificationClient: (any MeasurementNotificationClient)? = nil, systemPauseObserver: SystemPauseObserver? = nil) {
        let dataRoot = dataDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReEyeblink", isDirectory: true)
        settingsURL = dataRoot.appendingPathComponent("settings.json")
        var loaded = AppSettings()
        if let data = try? Data(contentsOf: settingsURL), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) { loaded = decoded.validatedForInterface() }
        if observesSystemEvents { loaded.launchAtLogin = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval }
        settings = loaded
        notifications = MeasurementNotifications(client: notificationClient ?? (observesSystemEvents ? SystemMeasurementNotificationClient() : nil), enabled: loaded.measurementNotifications)
        engine = EyeblinkEngine(settings: loaded, now: ProcessInfo.processInfo.systemUptime)
        let history: any MeasurementHistory
        var historyReadError: Error?
        if let historyStore { history = historyStore }
        else {
            do { history = try HistoryStore(fileURL: dataRoot.appendingPathComponent("measurements.json")) }
            catch { history = try! HistoryStore(); historyReadError = error }
        }
        persistence = MeasurementHistoryCoordinator(store: history)
        if let historyReadError { lastError = "无法读取测量记录，已保留原文件：\(historyReadError.localizedDescription)" }
        cameraDevices = observesSystemEvents ? CameraPipeline.devices() : []
        let preferred = UserDefaults.standard.string(forKey: "selectedCameraID")
        selectedCameraID = cameraDevices.first(where: { $0.id == preferred })?.id ?? cameraDevices.first?.id ?? ""
        if observesSystemEvents { updatePermissionState(); refreshSystemCapabilities() }
        else { engine.setCameraPaused(true, reason: .permissionDenied, at: now) }
        persistence.onChange = { [weak self] in self?.historyDidChange() }
        persistence.onSaved = { [weak self] record in
            guard let self, !self.persistence.isClosing else { return }
            if self.settings.measurementNotifications { self.notifications.notify(record, english: self.isEnglish) }
        }
        persistence.onError = { [weak self] error in
            guard let self else { return }
            self.lastError = self.text("记录操作失败：", "History operation failed: ") + error.localizedDescription
        }
        persistence.load()
        self.systemPauseObserver = systemPauseObserver ?? (observesSystemEvents ? SystemPauseObserver() : nil)
        self.systemPauseObserver?.start { [weak self] reason, paused in
            self?.setSystemPaused(paused, reason: reason)
        }
        if observesSystemEvents {
            ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        }
        synchronize()
    }

    var isEnglish: Bool { settings.language == .english }
    var isManuallyPaused: Bool { engine.state.pauseReasons.contains(.user) }
    var isCameraManuallyPaused: Bool { engine.state.cameraPauseReasons.contains(.user) }
    func text(_ zh: String, _ en: String) -> String { isEnglish ? en : zh }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func saveSettings() {
        settings = settings.validatedForInterface()
        notifications.setEnabled(settings.measurementNotifications)
        engine.updateSettings(settings, at: now)
        do {
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        } catch { lastError = text("设置保存失败：", "Unable to save settings: ") + error.localizedDescription }
        synchronize()
    }

    func setMeasurementNotifications(_ enabled: Bool) {
        // Revoke pending deliveries in the binding setter, before SwiftUI's
        // later settings persistence callback can run.
        notifications.setEnabled(enabled)
        settings.measurementNotifications = enabled
    }

    func togglePause() {
        engine.setPaused(!engine.state.pauseReasons.contains(.user), reason: .user, at: now)
        previewReminder = nil
        synchronize()
    }
    func toggleCameraPause() {
        engine.setCameraPaused(!engine.state.cameraPauseReasons.contains(.user), reason: .user, at: now)
        synchronize()
    }
    func requestCamera() {
        hasCameraFailure = false; cameraFailureMessage = nil
        engine.setCameraPaused(false, reason: .unavailable, at: now)
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: updatePermissionState(); synchronize()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.updatePermissionState()
                    if self.pendingMeasurement && self.cameraAuthorized { self.pendingMeasurement = false; self.startMeasurement() }
                    self.synchronize()
                }
            }
        default: updatePermissionState(); openCameraPrivacySettings()
        }
    }
    private func updatePermissionState() {
        cameraAuthorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if engine.state.cameraPauseReasons.contains(.permissionDenied) != !cameraAuthorized {
            engine.setCameraPaused(!cameraAuthorized, reason: .permissionDenied, at: now)
        }
        if !cameraAuthorized { cameraStatus = text("尚未授权相机。定时提醒仍然可用。", "Camera access is off. Timed reminders still work.") }
    }
    func startMeasurement() {
        guard !isShuttingDown, !isClearingMeasurements else { return }
        guard cameraAuthorized else { pendingMeasurement = true; requestCamera(); return }
        engine.setPreview(false, at: now)
        if let id = engine.startMeasurement(at: now) { persistence.bind(id) }
        else if !engine.state.measurementRequested { lastError = text("请先恢复相机和 Eyeblink，再开始测量。", "Resume the camera and Eyeblink before measuring.") }
        synchronize()
    }
    func togglePreview() {
        guard cameraAuthorized else { requestCamera(); return }
        engine.setPreview(!engine.state.previewRequested, at: now)
        synchronize()
    }
    func chooseCamera(_ id: String) {
        guard cameraDevices.contains(where: { $0.id == id }) else { return }
        selectedCameraID = id
        UserDefaults.standard.set(id, forKey: "selectedCameraID")
        hasCameraFailure = false; cameraFailureMessage = nil
        engine.setCameraPaused(false, reason: .unavailable, at: now)
        engine.invalidateCamera(at: now)
        activeDeviceID = nil
        synchronize()
    }
    func openCameraPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshSystemCapabilities()
            saveSettings()
        } catch {
            refreshSystemCapabilities()
            lastError = text("无法更改登录启动：", "Unable to change login item: ") + error.localizedDescription
        }
    }
    private func refreshSystemCapabilities() {
        let status = SMAppService.mainApp.status
        settings.launchAtLogin = status == .enabled || status == .requiresApproval
        loginApprovalRequired = status == .requiresApproval
        windowTitlePermissionGranted = CGPreflightScreenCaptureAccess()
    }
    func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func requestWindowTitleAccess() {
        guard !isShuttingDown else { return }
        if !CGRequestScreenCaptureAccess() { openWindowTitlePrivacySettings() }
        refreshSystemCapabilities()
    }
    func openWindowTitlePrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
    func clearMeasurements() {
        guard persistence.clear() != nil else { return }
        notifications.invalidate()
        engine.setCameraPaused(true, reason: .custom("clearing-history"), at: now)
        engine.cancelMeasurement(at: now)
        synchronize()
    }
    private func historyDidChange() {
        let wasClearing = isClearingMeasurements
        measurements = persistence.snapshot.records.sorted { $0.date < $1.date }
        latestBlinkRate = measurements.last?.bpm
        isClearingMeasurements = persistence.isClearing
        if wasClearing, !isClearingMeasurements, !persistence.isClosing {
            engine.setCameraPaused(false, reason: .custom("clearing-history"), at: now)
            synchronize()
        }
    }
    func openMainWindow() {
        onOpenMainWindow?()
        NSApp.unhide(nil)
        let window = NSApp.windows.first(where: { ($0.identifier?.rawValue.hasPrefix("main") ?? false) && !($0 is NSPanel) })
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func showReminderPreview() { preview(.training(settings.trainingMode, mgd: settings.mgdEnabled), duration: 15) }
    func playTrainingFeedbackPreview() {
        guard !isShuttingDown, !isPaused, case .training = previewReminder else { return }
        preview(.trainingFeedback(UUID()), duration: .infinity)
    }
    func previewExercise(_ kind: ExerciseKind = .lookFar) { preview(.exercise(kind, secondsRemaining: 10), duration: 10) }
    func previewBreak() { preview(.rest, duration: 30) }
    func revealBreakReminder() {
        guard !isShuttingDown, case .rest = engine.state.reminder else { return }
        overlay?.reveal()
    }
    private func preview(_ reminder: Reminder, duration: TimeInterval) {
        previewReminder = reminder; previewExpires = now + duration
        synchronize()
    }
    func dismissReminder() {
        if previewReminder != nil { previewReminder = nil }
        else { engine.dismissReminder(at: now) }
        synchronize()
    }
    func finishTrainingFeedback(_ id: UUID) {
        guard !isShuttingDown else { return }
        if previewReminder?.trainingFeedbackID == id { previewReminder = nil }
        else if !engine.finishTrainingFeedback(id: id, at: now) { return }
        synchronize()
    }
    func retryTraining() {
        guard !isShuttingDown, engine.retryTraining(at: now) else { return }
        synchronize()
    }
    func snoozeBreak() {
        if previewReminder != nil { previewReminder = nil }
        else { engine.snoozeBreak(at: now) }
        synchronize()
    }
    private func setSystemPaused(_ paused: Bool, reason: PauseReason) {
        guard !isShuttingDown, engine.state.pauseReasons.contains(reason) != paused else { return }
        engine.setPaused(paused, reason: reason, at: now)
        if paused { previewReminder = nil }
        synchronize()
        systemPauseLog.notice("system pause reason=\(String(describing: reason), privacy: .public) active=\(paused, privacy: .public) effective=\(self.isPaused, privacy: .public)")
    }
    private func tick() {
        ticks += 1
        engine.advance(to: now, idleDuration: idleDuration(), date: Date())
        if ticks % 4 == 0 {
            updatePermissionState()
            refreshSystemCapabilities()
            updateAutomaticPause()
            cameraDevices = CameraPipeline.devices()
        }
        if previewReminder != nil && now >= previewExpires { previewReminder = nil }
        synchronize()
    }
    private func idleDuration() -> TimeInterval {
        idleTracker.observe(at: now, cursor: NSEvent.mouseLocation, keyCount: CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown))
    }
    private func updateAutomaticPause() {
        let matches = AutomaticPauseMatches.evaluate(settings: settings, processes: {
            NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        }, windowTitles: {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let titles = windows.compactMap { $0[kCGWindowName as String] as? String }
            let frontTitles = windows.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == foregroundPID }.compactMap { $0[kCGWindowName as String] as? String }
            return (all: titles, frontmost: frontTitles)
        })
        for reason in automaticAll.subtracting(matches.all) { engine.setPaused(false, reason: reason, at: now) }
        for reason in matches.all.subtracting(automaticAll) { engine.setPaused(true, reason: reason, at: now) }
        for reason in automaticCamera.subtracting(matches.camera) { engine.setCameraPaused(false, reason: reason, at: now) }
        for reason in matches.camera.subtracting(automaticCamera) { engine.setCameraPaused(true, reason: reason, at: now) }
        automaticAll = matches.all; automaticCamera = matches.camera
    }
    private func synchronize() {
        guard !isShuttingDown else { return }
        // A separate preview must not leave a hidden success animation queued
        // behind it. It also must not be closed by that animation's callback.
        if previewReminder != nil, let id = engine.state.reminder?.trainingFeedbackID {
            engine.finishTrainingFeedback(id: id, at: now)
        }
        let state = engine.state
        isPaused = state.isPaused
        isCameraPaused = state.cameraPaused || !settings.cameraEnabled
        cameraPreviewEnabled = state.cameraPurpose == .preview
        isMeasuring = state.measurement != nil || state.measurementRequested
        measurementProgress = state.measurement?.progress ?? 0
        nextExerciseRemaining = max(0, state.exerciseRemaining)
        nextBreakRemaining = max(0, state.breakRemaining)
        if case .rest = state.reminder { isTakingBreak = true } else { isTakingBreak = false }
        if let measurement = state.measurement { persistence.bind(measurement.id) }
        statusText = state.isPaused ? text("已暂停", "Paused") : state.measurement != nil ? text("测量进行中", "Measuring") : state.measurementRequested ? text("测量已排队，等待当前任务结束。", "Measurement queued until the current task ends.") : text("正在守护你的用眼节奏", "Keeping a gentle rhythm for your eyes")
        syncCamera()
        if cameraFailureMessage == nil, !isCameraPaused, state.cameraPurpose == nil, let failure = state.lastDetectionFailure {
            if failure == "measurement-no-face" { cameraStatus = text("测量已停止：未持续检测到人脸。请检查光线与摄像头后重试。", "Measurement stopped: no continuous face detection. Check your lighting and camera, then try again.") }
            else if failure == "training-no-face" { cameraStatus = text("本次训练已停止：未检测到人脸。", "This training session stopped because no face was detected.") }
        }
        if overlay == nil { overlay = ReminderWindowController(model: self) }
        overlay?.show(reminder: state.isPaused ? nil : previewReminder ?? state.reminder, isPreview: previewReminder != nil)
        for effect in engine.takeEffects() {
            switch effect {
            case .playReminderSound:
                NSSound(named: .init("Glass"))?.play()
            case .measurementCancelled(let id): persistence.cancel(id)
            case .measurementCompleted(let record): persistence.save(record)
            case .restTransition(let event):
                // Fixed event names and durations only; no camera, window titles,
                // process keywords, or image data enter this local system log.
                restLog.notice("rest event=\(event.kind.rawValue, privacy: .public) uptime=\(event.uptime, privacy: .public) idle=\(event.idleDuration ?? -1, privacy: .public)")
            }
        }
    }
    private func syncCamera() {
        guard let token = engine.state.cameraToken, engine.state.cameraPurpose != nil, cameraAuthorized else {
            if activeCameraToken != nil { activeCameraToken = nil; activeDeviceID = nil; cameraPipeline.stop() }
            framesPerSecond = 0
            if let cameraFailureMessage { cameraStatus = cameraFailureMessage }
            else if !cameraAuthorized { cameraStatus = text("尚未授权相机。定时提醒仍然可用。", "Camera access is off. Timed reminders still work.") }
            else if isCameraPaused { cameraStatus = text("相机功能已暂停", "Camera features are paused") }
            else { cameraStatus = text("相机待机，等待下一次训练或测量。", "Camera is idle until the next training or measurement.") }
            return
        }
        guard activeCameraToken != token || activeDeviceID != selectedCameraID else { return }
        activeCameraToken = token; activeDeviceID = selectedCameraID
        framesPerSecond = 0
        cameraStatus = text("正在启动摄像头…", "Starting camera…")
        let measurementToken = engine.state.measurement?.id
        let duration = engine.policy.measurementTiming == .originalElapsedTime ? engine.state.measurement?.targetDuration : nil
        cameraPipeline.start(deviceID: selectedCameraID, generation: token, isPreview: engine.state.cameraPurpose == .preview, noFaceTimeout: engine.cameraNoFaceTimeout, measurementDuration: duration) { [weak self] observation in
            CameraObservationDelivery.send(observation) { [weak self] value in
                self?.receive(value, measurementToken: measurementToken)
            }
        }
    }
    private func receive(_ observation: CameraObservation, measurementToken: UUID?) {
        guard observation.generation == activeCameraToken else { return }
        if let failure = observation.detectionFailure {
            engine.cameraDetectionFailed(token: observation.generation, reason: failure, at: observation.uptime)
            synchronize()
            return
        }
        if observation.measurementFinished {
            engine.cameraMeasurementFinished(token: observation.generation, at: observation.uptime)
            synchronize()
            return
        }
        if let blinkDetected = observation.trainingReaction {
            engine.cameraTrainingProgress(token: observation.generation, blinkDetected: blinkDetected, at: observation.uptime)
            synchronize()
            return
        }
        if observation.terminalFailure {
            hasCameraFailure = true
            cameraFailureMessage = observation.error
            if observation.captureFailure {
                engine.cameraCaptureFailed(token: observation.generation, at: observation.uptime)
            } else {
                engine.setCameraPaused(true, reason: .unavailable, at: now)
            }
            synchronize()
            return
        }
        framesPerSecond = observation.framesPerSecond
        if observation.isPriming {
            hasCameraFailure = false; cameraFailureMessage = nil
            engine.cameraDidStart(token: observation.generation, at: observation.uptime)
            synchronize()
            return
        }
        if let error = observation.error { cameraStatus = error }
        else if observation.faceCount == 0 { cameraStatus = text("未检测到人脸，请面向摄像头并改善光线。", "No face detected. Face the camera and check your lighting.") }
        else if observation.faceCount > 1 { cameraStatus = text("检测到多张人脸，请保持画面中只有一人。", "Multiple faces detected. Keep one person in view.") }
        else { cameraStatus = text("正在识别眨眼", "Detecting blinks") }
        let valid = observation.error == nil && observation.faceCount == 1 && observation.eyeDetectionValid
        let blinks = observation.blinkDurations.filter { $0.isFinite && $0 > 0 }
        blinkCount += blinks.count
        engine.sample(cameraToken: observation.generation, token: measurementToken, at: observation.uptime, faceValid: valid, blinkDurations: blinks)
        synchronize()
    }
    func terminate() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        systemPauseObserver?.stop()
        notifications.stop()
        ticker?.cancel()
        activeCameraToken = nil
        cameraPipeline.stop()
        overlay?.close()
    }
    func beginShutdown() -> Task<Void, Never> {
        terminate()
        let history = persistence.close()
        let camera = cameraPipeline
        return Task.detached {
            await history.value
            await camera.stopAndWait()
        }
    }
    func shutdown() async { await beginShutdown().value }
}
