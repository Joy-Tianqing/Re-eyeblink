import XCTest
@testable import EyeblinkCore

final class SideCameraMeasurementTests: XCTestCase {
    private func engine() -> EyeblinkEngine {
        var settings = AppSettings()
        settings.trainingEnabled = false; settings.exerciseEnabled = false
        settings.breakEnabled = false; settings.measurementEnabled = false
        return .init(settings: settings)
    }
    func testLowQualityCompletionCancelsInsteadOfSavingFalseZeroAndLateCompletionCannotReviveIt() throws {
        for fraction in [0, 0.84, .nan, .infinity, 1.1] {
            var e = engine()
            let id = try XCTUnwrap(e.startMeasurement(at: 15)), token = try XCTUnwrap(e.state.cameraToken)
            e.cameraDidStart(token: token, at: 15)
            // Frames arrive for the full production duration, but their eye
            // evidence is unusable. This is distinct from the no-frame watchdog.
            for i in 1...1799 { e.sample(cameraToken: token, token: id, at: 15 + Double(i)*0.1, faceValid: false, blinkDurations: []) }
            e.advance(to: 195)
            e.cameraMeasurementFinished(token: token, at: 195.001, detection: .init(algorithm: "side-contour-v1", validFrameFraction: fraction))
            XCTAssertEqual(e.takeEffects(), [.measurementCancelled(id)])
            XCTAssertEqual(e.state.lastDetectionFailure, "measurement-quality")
            e.cameraMeasurementFinished(token: token, at: 196, detection: .init(algorithm: "side-contour-v1", validFrameFraction: 1))
            XCTAssertTrue(e.takeEffects().isEmpty)
        }
    }
    func testQualifiedCompletionTagsAlgorithmAndPreservesThreeMinuteDenominator() throws {
        var e = engine()
        let id = try XCTUnwrap(e.startMeasurement(at: 15)), token = try XCTUnwrap(e.state.cameraToken)
        e.cameraDidStart(token: token, at: 15)
        e.sample(cameraToken: token, token: id, at: 194.9, faceValid: true, blinkDurations: [0.1,0.2,0.15])
        let detection = MeasurementDetection(algorithm: "side-contour-v1", validFrameFraction: 0.9)
        e.cameraMeasurementFinished(token: token, at: 195.001, detection: detection)
        guard case .measurementCompleted(let record) = e.takeEffects().first else { return XCTFail("Expected a qualified result") }
        XCTAssertEqual(record.blinksPerMinute, 1)
        XCTAssertEqual(record.frequencyDuration, 180)
        XCTAssertEqual(record.detection, detection)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementRecord.self, from: JSONEncoder().encode(record)), record)
    }
    func testOldHistoryWithoutAlgorithmMetadataDecodesUnchanged() throws {
        let old = MeasurementRecord(date: Date(timeIntervalSince1970: 123), validDuration: 180, blinkDurations: [0.2], frequencyDuration: 180)
        let raw = try JSONEncoder().encode(old)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertNil(json["detection"])
        XCTAssertEqual(try JSONDecoder().decode(MeasurementRecord.self, from: raw), old)
    }
    func testQualityFailureAndModeChangeRevokeCameraToken() throws {
        var e = engine()
        let id = try XCTUnwrap(e.startMeasurement(at: 15)), token = try XCTUnwrap(e.state.cameraToken)
        e.cameraDidStart(token: token, at: 15)
        e.cameraDetectionFailed(token: token, reason: .insufficientQuality, at: 45)
        XCTAssertEqual(e.takeEffects(), [.measurementCancelled(id)])
        XCTAssertEqual(e.state.lastDetectionFailure, "measurement-quality")
        e.setPreview(true, at: 46)
        let before = e.state.cameraToken
        e.invalidateCamera(at: 47)
        XCTAssertNotEqual(e.state.cameraToken, before)
        XCTAssertEqual(e.state.cameraPurpose, .preview)
    }
    func testSingleEyeMetadataPersistsAndIsExcludedFromBothEyeAverages() throws {
        let bilateral = MeasurementRecord(date: .distantPast, validDuration: 180, blinkDurations: [0.1,0.1,0.1])
        for mode in [EyeObservationMode.left, .right, .mixed] {
            let estimate = MeasurementRecord(date: .now, validDuration: 180, blinkDurations: [0.5],
                detection: .init(algorithm: "side-contour-v2", validFrameFraction: 0.95, observationMode: mode))
            let decoded = try JSONDecoder().decode(MeasurementRecord.self, from: JSONEncoder().encode(estimate))
            XCTAssertTrue(decoded.isEstimated); XCTAssertEqual(decoded, estimate)
            let summary = StatisticsSummary(records: [bilateral, decoded])
            XCTAssertEqual(summary.count, 1); XCTAssertEqual(summary.meanBPM, 1)
            XCTAssertEqual(summary.meanBlinkDurationMilliseconds!, 100, accuracy: 1e-9)
            XCTAssertNil(StatisticsSummary(records: [decoded]).meanBPM)
        }
    }
    func testV1MetadataWithoutEyeModeStillDecodesAsLegacyResult() throws {
        let raw = Data(#"{"algorithm":"side-contour-v1","validFrameFraction":0.9}"#.utf8)
        let result = try JSONDecoder().decode(MeasurementDetection.self, from: raw)
        XCTAssertNil(result.observationMode); XCTAssertNil(result.targeting); XCTAssertFalse(result.isMonocularEstimate)
    }
    func testCoverageTagsMixedModesAndDoesNotBridgeAnEyeSwitch() {
        var c = SideCameraCoverage(); c.start(at: 0)
        c.observe(at: 0, valid: true, observationMode: .left)
        c.observe(at: 0.1, valid: true, observationMode: .left)
        c.observe(at: 0.2, valid: true, observationMode: .right)
        c.observe(at: 0.3, valid: true, observationMode: .right)
        let result = c.report(at: 0.3)
        XCTAssertEqual(result.observationMode, .mixed); XCTAssertTrue(result.isMonocularEstimate)
        XCTAssertEqual(result.validFrameFraction, 2/3, accuracy: 1e-9)
        c.start(at: 1)
        c.observe(at: 1, valid: true, observationMode: .both)
        c.observe(at: 1.1, valid: false, observationMode: .left)
        XCTAssertEqual(c.report(at: 1.1).observationMode, .both, "Invalid frames cannot change provenance")
    }
    func testQualifiedSingleEyeMeasurementKeepsProvenanceThroughEngineCompletion() throws {
        var e = engine()
        let id = try XCTUnwrap(e.startMeasurement(at: 15)), token = try XCTUnwrap(e.state.cameraToken)
        e.cameraDidStart(token: token, at: 15)
        e.sample(cameraToken: token, token: id, at: 194.9, faceValid: true, blinkDurations: [0.1])
        e.cameraMeasurementFinished(token: token, at: 195.001,
            detection: .init(algorithm: "side-contour-v2", validFrameFraction: 0.95, observationMode: .right))
        guard case .measurementCompleted(let record) = e.takeEffects().first else { return XCTFail("Expected a qualified estimate") }
        XCTAssertTrue(record.isEstimated); XCTAssertEqual(record.frequencyDuration, 180)
        XCTAssertEqual(record.detection?.observationMode, .right)
    }

}
