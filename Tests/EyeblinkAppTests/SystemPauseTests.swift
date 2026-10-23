import AppKit
import XCTest
import EyeblinkCore
@testable import EyeblinkApp

@MainActor
final class SystemPauseTests: XCTestCase {
    private let workspace = NotificationCenter()
    private let distributed = NotificationCenter()

    private func observer(locked: Bool = false) -> SystemPauseObserver {
        SystemPauseObserver(workspace: workspace, distributed: distributed, initiallyLocked: { locked })
    }

    private func model(locked: Bool = false) throws -> AppModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppModel(dataDirectory: directory, observesSystemEvents: false, systemPauseObserver: observer(locked: locked))
    }

    func testScreensaverAndDisplaySleepUseTheirOwnNotificationCenters() async throws {
        let pairs: [(NotificationCenter, NotificationCenter, Notification.Name, Notification.Name)] = [
            (distributed, workspace, .init("com.apple.screensaver.didstart"), .init("com.apple.screensaver.didstop")),
            (workspace, distributed, NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification)
        ]
        for (center, wrongCenter, pause, resume) in pairs {
            let model = try model()
            wrongCenter.post(name: pause, object: nil)
            XCTAssertFalse(model.isPaused)
            center.post(name: pause, object: nil)
            XCTAssertTrue(model.isPaused)
            XCTAssertTrue(model.isCameraPaused)
            center.post(name: resume, object: nil)
            XCTAssertFalse(model.isPaused)
            await model.shutdown()
            center.post(name: pause, object: nil)
            XCTAssertFalse(model.isPaused)
        }
    }

    func testScreensaverDisplayLockAndManualPauseCannotResumeEachOther() async throws {
        for wakeDisplayFirst in [true, false] {
            let model = try model()
            model.togglePause()
            distributed.post(name: .init("com.apple.screensaver.didstart"), object: nil)
            workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
            distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
            model.togglePause()
            distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
            XCTAssertTrue(model.isPaused)
            if wakeDisplayFirst {
                workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            } else {
                distributed.post(name: .init("com.apple.screensaver.didstop"), object: nil)
            }
            XCTAssertTrue(model.isPaused)
            workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
            distributed.post(name: .init("com.apple.screensaver.didstop"), object: nil)
            XCTAssertFalse(model.isPaused)
            await model.shutdown()
        }
    }

    func testScreensaverAndDisplaySleepReleasePreviewAndRejectOldCameraLease() throws {
        for screenSaver in [true, false] {
            var settings = AppSettings()
            settings.trainingEnabled = false; settings.measurementEnabled = false
            settings.exerciseEnabled = false; settings.breakEnabled = false
            var engine = EyeblinkEngine(settings: settings)
            var time = 1.0
            let observer = observer()
            observer.start { reason, paused in engine.setPaused(paused, reason: reason, at: time) }
            engine.setPreview(true, at: 0)
            let oldCamera = try XCTUnwrap(engine.state.cameraToken)
            let center = screenSaver ? distributed : workspace
            center.post(name: screenSaver ? .init("com.apple.screensaver.didstart") : NSWorkspace.screensDidSleepNotification, object: nil)
            XCTAssertNil(engine.state.cameraToken)
            time = 100
            center.post(name: screenSaver ? .init("com.apple.screensaver.didstop") : NSWorkspace.screensDidWakeNotification, object: nil)
            XCTAssertEqual(engine.state.cameraPurpose, .preview)
            XCTAssertNotEqual(engine.state.cameraToken, oldCamera)
            engine.cameraDidStart(token: oldCamera, at: time)
            XCTAssertFalse(engine.state.cameraHasStarted)
            XCTAssertTrue(engine.takeEffects().isEmpty)
        }
    }

    func testDistributedLockPausesAppAndUnlockResumes() async throws {
        let model = try model()
        XCTAssertFalse(model.isPaused)
        // Lock events on the workspace center must not accidentally stand in
        // for the actual distributed notification registration.
        workspace.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertFalse(model.isPaused)
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertTrue(model.isPaused)
        XCTAssertTrue(model.isCameraPaused)
        XCTAssertEqual(model.engine.state.pauseReasons, [SystemPauseObserver.lockReason])
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertFalse(model.isPaused)
        XCTAssertTrue(model.engine.state.pauseReasons.isEmpty)
        await model.shutdown()
    }

    func testUnlockPreservesManualPauseAndCameraPause() async throws {
        let model = try model()
        model.togglePause()
        model.toggleCameraPause()
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertTrue(model.isManuallyPaused)
        XCTAssertTrue(model.isPaused)
        XCTAssertTrue(model.isCameraManuallyPaused)
        model.togglePause()
        XCTAssertFalse(model.isPaused)
        XCTAssertTrue(model.isCameraManuallyPaused)
        await model.shutdown()
    }

    func testSleepSessionAndLockResumeIndependentlyInEitherOrder() async throws {
        for unlockFirst in [true, false] {
            let model = try model()
            distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            if unlockFirst {
                distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
            } else {
                workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            }
            XCTAssertTrue(model.isPaused)
            workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            XCTAssertTrue(model.isPaused)
            if unlockFirst {
                workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            } else {
                distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
            }
            XCTAssertFalse(model.isPaused)
            await model.shutdown()
        }
    }

    func testAlreadyLockedLaunchIsPausedBeforeFirstCameraRequest() async throws {
        let model = try model(locked: true)
        XCTAssertTrue(model.isPaused)
        XCTAssertNil(model.engine.state.cameraToken)
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertFalse(model.isPaused)
        await model.shutdown()
    }

    func testRepeatedEventsAndShutdownDoNotLeaveObserversActive() async throws {
        let model = try model()
        for _ in 0..<3 { distributed.post(name: SystemPauseObserver.screenLocked, object: nil) }
        XCTAssertEqual(model.engine.state.pauseReasons, [SystemPauseObserver.lockReason])
        for _ in 0..<3 { distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil) }
        XCTAssertFalse(model.isPaused)
        await model.shutdown()
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertTrue(model.engine.state.pauseReasons.isEmpty)
    }

    func testObserverRestartAndDeinitRemoveRegistrations() {
        var observer: SystemPauseObserver? = observer()
        var oldCalls = 0, currentCalls = 0
        observer?.start { _, _ in oldCalls += 1 }
        observer?.start { _, _ in currentCalls += 1 }
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(currentCalls, 1)
        observer = nil
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertEqual(currentCalls, 1)
    }

    func testLockReleasesPreviewAndUnlockUsesFreshCameraLease() {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.measurementEnabled = false
        settings.exerciseEnabled = false; settings.breakEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        var time = 1.0
        let observer = observer()
        observer.start { reason, paused in engine.setPaused(paused, reason: reason, at: time) }
        engine.setPreview(true, at: 0)
        let oldCamera = engine.state.cameraToken
        XCTAssertNotNil(oldCamera)
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertNil(engine.state.cameraPurpose)
        XCTAssertTrue(engine.state.previewRequested)
        time = 100
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNotNil(engine.state.cameraToken)
        XCTAssertNotEqual(engine.state.cameraToken, oldCamera)
    }

    func testLockCancelsMeasurementAndRejectsLateCompletionWithoutSaving() throws {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.measurementEnabled = false
        settings.exerciseEnabled = false; settings.breakEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        let measurement = try XCTUnwrap(engine.startMeasurement(at: 20))
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: camera, at: 21)
        var time = 30.0
        let observer = observer()
        observer.start { reason, paused in engine.setPaused(paused, reason: reason, at: time) }
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertNil(engine.state.measurement)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(measurement)])
        engine.sample(cameraToken: camera, token: measurement, at: 31, faceValid: true, blinkDurations: [0.1])
        engine.cameraMeasurementFinished(token: camera, at: 201)
        time = 202
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertNil(engine.state.measurement)
        XCTAssertTrue(engine.takeEffects().isEmpty)
        XCTAssertFalse(engine.state.isPaused)
    }

    func testLockStopsTrainingButTimerExpiresBeforeResume() throws {
        var settings = AppSettings()
        settings.measurementEnabled = false; settings.exerciseEnabled = false; settings.breakEnabled = false
        var engine = EyeblinkEngine(settings: settings)
        engine.advance(to: 31)
        let camera = try XCTUnwrap(engine.state.cameraToken)
        engine.cameraDidStart(token: camera, at: 31.1)
        var time = 31.2
        let observer = observer()
        observer.start { reason, paused in engine.setPaused(paused, reason: reason, at: time) }
        distributed.post(name: SystemPauseObserver.screenLocked, object: nil)
        XCTAssertFalse(engine.state.trainingSessionActive)
        XCTAssertNil(engine.state.cameraToken)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 1000)
        XCTAssertLessThanOrEqual(engine.state.trainingRemaining, 0)
        time = 1001
        distributed.post(name: SystemPauseObserver.screenUnlocked, object: nil)
        XCTAssertFalse(engine.state.isPaused)
        XCTAssertNil(engine.state.cameraToken)
        engine.advance(to: 1015.999)
        XCTAssertNil(engine.state.cameraToken)
        engine.advance(to: 1016)
        XCTAssertTrue(engine.state.trainingSessionActive)
    }
}
