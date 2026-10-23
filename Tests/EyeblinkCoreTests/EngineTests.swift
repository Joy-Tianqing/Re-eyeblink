import XCTest
@testable import EyeblinkCore

final class EngineTests: XCTestCase {
    // Boundary tests use exact single steps; production policy is independently asserted.
    func testingPolicy() -> EnginePolicy {
        var policy = EnginePolicy()
        policy.startupQuietPeriod = 0
        policy.featurePollingInterval = 0.001
        return policy
    }
    func isolatedSettings() -> AppSettings {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.exerciseEnabled = false
        settings.breakEnabled = false; settings.measurementEnabled = false
        return settings
    }
    func testDefaultsAndRoundTrip() throws {
        let settings = AppSettings()
        XCTAssertEqual(settings.language, .simplifiedChinese)
        XCTAssertEqual(settings.trainingInterval, 30)
        XCTAssertEqual(settings.measurementDuration, 180)
        XCTAssertFalse(settings.researchSharingEnabled)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
    }
    func testSimpleReminderDoesNotOpenCameraAndDoesNotStack() {
        var settings = isolatedSettings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        settings.reminderSoundEnabled = true
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.advance(to: 30)
        XCTAssertEqual(engine.state.reminder, .training(.simple, mgd: false))
        XCTAssertNil(engine.state.cameraPurpose)
        XCTAssertEqual(engine.takeEffects(), [.playReminderSound])
        engine.advance(to: 500)
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
    func testPauseKeepsTimerDeadlineAndUserPauseSurvivesAutomation() {
        var settings = isolatedSettings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.setPaused(true, at: 10)
        engine.setPaused(true, reason: .process("zoom"), at: 20)
        engine.setPaused(false, reason: .process("zoom"), at: 40)
        XCTAssertTrue(engine.state.isPaused)
        engine.setPaused(false, at: 1000)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 1000)
        XCTAssertNotNil(engine.state.reminder)
    }
    func testOldCameraAndMeasurementCallbacksCannotWriteAfterPause() {
        var engine = EyeblinkEngine(settings: isolatedSettings(), policy: testingPolicy())
        let first = engine.startMeasurement(at: 0)!
        let camera = engine.state.cameraToken!
        engine.setCameraPaused(true, at: 1)
        engine.setCameraPaused(false, at: 2)
        let second = engine.startMeasurement(at: 2)!
        XCTAssertNotEqual(first, second)
        engine.sample(cameraToken: camera, token: first, at: 3, faceValid: true, blinkDurations: [0.1])
        XCTAssertEqual(engine.state.measurement?.validDuration, 0)
        XCTAssertTrue(engine.state.measurement?.blinkDurations.isEmpty == true)
    }
    func testPreviewIsExclusiveAndDoesNotGenerateStatistics() {
        var engine = EyeblinkEngine(settings: isolatedSettings(), policy: testingPolicy())
        let measurement = engine.startMeasurement(at: 0)!
        engine.setPreview(true, at: 1)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.takeEffects(), [.measurementCancelled(measurement)])
        engine.sample(cameraToken: engine.state.cameraToken!, token: nil, at: 1.1, faceValid: true, blinkDurations: [0.1])
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
    func testNewPreviewClearsPriorTrainingFailure() {
        var settings = isolatedSettings()
        settings.trainingEnabled = true
        settings.trainingInterval = 2
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.advance(to: 2)
        engine.cameraDetectionFailed(token: engine.state.cameraToken!, reason: .noFace, at: 13)
        XCTAssertEqual(engine.state.lastDetectionFailure, "training-no-face")
        engine.setPreview(true, at: 13)
        XCTAssertEqual(engine.state.cameraPurpose, .preview)
        XCTAssertNil(engine.state.lastDetectionFailure)
    }
    func testMeasurementCountsOnlyContinuousValidSamplesAndFinishesOnce() {
        var settings = isolatedSettings(); settings.measurementDuration = 1
        var policy = testingPolicy(); policy.measurementTiming = .validSamples
        var engine = EyeblinkEngine(settings: settings, policy: policy)
        let id = engine.startMeasurement(at: 0)!, camera = engine.state.cameraToken!
        engine.sample(cameraToken: camera, token: id, at: 0, faceValid: true, blinkDurations: [])
        engine.sample(cameraToken: camera, token: id, at: 0.25, faceValid: true, blinkDurations: [0.1])
        engine.sample(cameraToken: camera, token: id, at: 0.5, faceValid: false, blinkDurations: [])
        engine.sample(cameraToken: camera, token: id, at: 5, faceValid: true, blinkDurations: [])
        XCTAssertEqual(engine.state.measurement?.validDuration, 0.25)
        for time in [5.25, 5.5, 5.75] { engine.sample(cameraToken: camera, token: id, at: time, faceValid: true, blinkDurations: []) }
        let effects = engine.takeEffects()
        XCTAssertEqual(effects.count, 1)
        guard case .measurementCompleted(let record) = effects.first else { return XCTFail("Missing record") }
        XCTAssertEqual(record.bpm, 60)
        XCTAssertEqual(record.averageBlinkDurationMilliseconds, 100)
        XCTAssertNil(engine.state.measurement)
        engine.sample(cameraToken: camera, token: id, at: 6, faceValid: true, blinkDurations: [0.1])
        XCTAssertTrue(engine.takeEffects().isEmpty)
    }
    func testSnoozeBreakUsesExactlyFiveMinutesAndSkipDoesNotRecordRest() {
        var settings = isolatedSettings(); settings.breakEnabled = true; settings.breakInterval = 10
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.advance(to: 10)
        engine.snoozeBreak(at: 10)
        engine.advance(to: 309)
        XCTAssertNil(engine.state.reminder)
        engine.advance(to: 310)
        XCTAssertEqual(engine.state.reminder, .rest)
        engine.dismissReminder(at: 310)
        XCTAssertEqual(engine.state.breakRemaining, 10)
    }
    func testRestFinishesAtSampledIdleCheckInsteadOfIndependentCountdown() {
        var settings = isolatedSettings(); settings.breakEnabled = true; settings.breakInterval = 10
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.advance(to: 10)
        engine.advance(to: 190, idleDuration: 180)
        XCTAssertEqual(engine.state.reminder, .rest)
        engine.advance(to: 249, idleDuration: 239)
        XCTAssertEqual(engine.state.reminder, .rest)
        engine.advance(to: 250, idleDuration: 240)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.breakRemaining, 10)
    }
    func testExerciseRotatesOneActionPerCycleAndSkipInvalidatesElapsedTime() {
        var settings = isolatedSettings(); settings.exerciseEnabled = true; settings.exerciseInterval = 100
        var engine = EyeblinkEngine(settings: settings, policy: testingPolicy())
        engine.advance(to: 100)
        XCTAssertEqual(engine.state.reminder, .exercise(.lookFar, secondsRemaining: 10))
        engine.advance(to: 110)
        XCTAssertNil(engine.state.reminder)
        XCTAssertEqual(engine.state.exerciseRemaining, 100)
        engine.advance(to: 210)
        XCTAssertEqual(engine.state.reminder, .exercise(.squeezeBlink, secondsRemaining: 10))
        engine.dismissReminder(at: 211)
        engine.advance(to: 220)
        XCTAssertNil(engine.state.reminder)
    }
    func testAutomaticPauseRulesUseIndependentReasonsAndIgnoreEmptyKeywords() {
        var settings = AppSettings()
        settings.pauseProcessKeywords = ["Zoom", " "]
        settings.pauseWindowKeywords = ["Movie"]
        settings.pauseCameraKeywords = ["Meeting"]
        let result = AutomaticPauseMatches.evaluate(settings: settings, processes: ["zoom"], windowTitles: ["Movie Player", "Meeting"], frontmostWindowTitles: ["Notes"])
        XCTAssertEqual(result.all, [.process("Zoom"), .window("Movie")])
        XCTAssertTrue(result.camera.isEmpty)
    }
    func testAutomaticPauseSkipsUnconfiguredProvidersAndKeepsRuleSemantics() {
        var settings = AppSettings()
        var processReads = 0, windowReads = 0
        func sample() -> AutomaticPauseMatches {
            AutomaticPauseMatches.evaluate(settings: settings, processes: {
                processReads += 1; return ["Zoom"]
            }, windowTitles: {
                windowReads += 1; return (all: ["Movie", "Meeting"], frontmost: ["Notes"])
            })
        }
        XCTAssertEqual(sample(), .init(all: [], camera: []))
        settings.pauseProcessKeywords = [" ", "\n"]
        settings.pauseWindowKeywords = ["\t"]; settings.pauseCameraKeywords = [""]
        XCTAssertEqual(sample(), .init(all: [], camera: []))
        XCTAssertEqual(processReads, 0); XCTAssertEqual(windowReads, 0)
        settings.pauseProcessKeywords = ["zoom"]
        XCTAssertEqual(sample().all, [.process("zoom")])
        XCTAssertEqual(processReads, 1); XCTAssertEqual(windowReads, 0)
        settings.pauseProcessKeywords = []
        settings.pauseWindowKeywords = ["movie"]; settings.pauseCameraKeywords = ["meeting"]
        XCTAssertEqual(sample(), .init(all: [.window("movie")], camera: []))
        XCTAssertEqual(processReads, 1); XCTAssertEqual(windowReads, 1)
        settings.pauseCameraFrontmostOnly = false
        XCTAssertEqual(sample().camera, [.window("meeting")])
        XCTAssertEqual(processReads, 1); XCTAssertEqual(windowReads, 2)
        settings.pauseCameraKeywords = []; settings.pauseWindowKeywords = []
        XCTAssertEqual(sample(), .init(all: [], camera: []))
        XCTAssertEqual(processReads, 1); XCTAssertEqual(windowReads, 2)
    }
    func testMonotonicClockIgnoresBackwardsAndInvalidInput() {
        var settings = isolatedSettings(); settings.trainingEnabled = true; settings.trainingMode = .simple
        var engine = EyeblinkEngine(settings: settings, now: 10, policy: testingPolicy())
        engine.advance(to: 9); engine.advance(to: .nan); engine.advance(to: 20)
        XCTAssertEqual(engine.state.trainingRemaining, 20)
    }
}

final class StatisticsTests: XCTestCase, @unchecked Sendable {
    func testOriginalMeasurementDurationTruncatesMillisecondsAndEmptyResultIsZero() {
        let measured = MeasurementRecord(date: Date(), validDuration: 180, blinkDurations: [0.1234, 0.2001])
        XCTAssertEqual(measured.averageBlinkDurationMilliseconds, 161)
        let noBlinks = MeasurementRecord(date: Date(), validDuration: 180, blinkDurations: [])
        XCTAssertEqual(noBlinks.averageBlinkDurationMilliseconds, 0)
    }
    func testDatesAreInclusiveThroughCalendarDayAndMeansStayDistinct() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let one = MeasurementRecord(date: date, validDuration: 60, blinkDurations: [0.1, 0.2])
        let two = MeasurementRecord(date: date.addingTimeInterval(86399), validDuration: 120, blinkDurations: [0.3])
        let three = MeasurementRecord(date: date.addingTimeInterval(86400), validDuration: 60, blinkDurations: [])
        let filtered = StatisticsSummary.filter([three, two, one], from: date, through: date, calendar: calendar)
        XCTAssertEqual(filtered.map(\.id), [one.id, two.id])
        let summary = StatisticsSummary(records: filtered)
        XCTAssertEqual(summary.meanBPM!, 1.25)
        XCTAssertEqual(summary.weightedBPM!, 1)
        XCTAssertEqual(summary.meanBlinkDurationMilliseconds!, 200, accuracy: 0.0001)
    }
    func testClearCancelGenerationAndAtomicPersistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let store = try HistoryStore(fileURL: file)
        let generation = await store.currentGeneration()
        let record = MeasurementRecord(date: Date(), validDuration: 60, blinkDurations: [0.1])
        let appended = try await store.append(record, expectedGeneration: generation)
        XCTAssertTrue(appended)
        try await store.clear(confirmed: false)
        let unchanged = await store.snapshot(); XCTAssertEqual(unchanged.count, 1)
        let reopened = try HistoryStore(fileURL: file)
        let persisted = await reopened.snapshot(); XCTAssertEqual(persisted, unchanged)
        try await store.clear(confirmed: true)
        let stale = try await store.append(record, expectedGeneration: generation)
        XCTAssertFalse(stale)
        let cleared = await store.snapshot(); XCTAssertTrue(cleared.isEmpty)
        let disk = try JSONDecoder().decode([MeasurementRecord].self, from: Data(contentsOf: file))
        XCTAssertTrue(disk.isEmpty)
    }
    func testConcurrentDuplicateAppendsAreSerialized() async throws {
        let store = try HistoryStore()
        let record = MeasurementRecord(date: Date(), validDuration: 60, blinkDurations: [])
        let count = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<30 { group.addTask { try await store.append(record, expectedGeneration: 0) } }
            var accepted = 0
            for try await result in group { if result { accepted += 1 } }
            return accepted
        }
        XCTAssertEqual(count, 1)
    }
    func testCancelledAppendDoesNotMutateHistory() async throws {
        let store = try HistoryStore()
        let record = MeasurementRecord(date: Date(), validDuration: 60, blinkDurations: [])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.append(record, expectedGeneration: 0)
        }
        let accepted = try await task.value
        XCTAssertFalse(accepted)
        let records = await store.snapshot(); XCTAssertTrue(records.isEmpty)
    }
    func testFailedPersistenceDoesNotPublishUncommittedState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blocker = directory.appendingPathComponent("regular-file")
        try Data("fixture".utf8).write(to: blocker)
        let store = try HistoryStore(fileURL: blocker.appendingPathComponent("history.json"))
        let record = MeasurementRecord(date: Date(), validDuration: 60, blinkDurations: [])
        do {
            _ = try await store.append(record, expectedGeneration: 0)
            XCTFail("Expected a file-system error")
        } catch {}
        let records = await store.snapshot(); XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "fixture")
    }
}
