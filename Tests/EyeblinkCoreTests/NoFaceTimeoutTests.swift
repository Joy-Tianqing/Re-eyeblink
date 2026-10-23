import XCTest
@testable import EyeblinkCore

final class NoFaceTimeoutTests: XCTestCase {
    private struct Reference: Decodable {
        var originalSHA256: String
        var qtCoreSHA256: String
        var thresholdCases: [Case]
        struct Case: Decodable { var nanoseconds: Int64; var elapsedMilliseconds: Int; var parameterMilliseconds: Int; var wouldStop: Bool }
    }
    func testActualOriginalIntegerMillisecondNoFaceBoundaries() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"OriginalNoFaceTimeout",withExtension:"json",subdirectory:"Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self,from:Data(contentsOf:url))
        XCTAssertEqual(reference.originalSHA256,"bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.qtCoreSHA256,"3941dcd1efb8c227e2fbc408c1f079215efde1f881a4968764bcec80bd2467db")
        XCTAssertEqual(reference.thresholdCases.count,24)
        let timer = FaceAbsenceTimer(startedAt:.init(ticks:0,frequency:1_000_000_000))
        for sample in reference.thresholdCases {
            let timeout = Double(sample.parameterMilliseconds-2000)/1000
            XCTAssertEqual(timer.hasExpired(at:.init(ticks:sample.nanoseconds,frequency:1_000_000_000),after:timeout),sample.wouldStop,
                "originalms=\(sample.elapsedMilliseconds),parameter=\(sample.parameterMilliseconds)")
        }
    }
    func testOnlyDetectorFailureCancelsContinuousNoFaceSamples() {
        var settings = AppSettings();settings.trainingEnabled=false;settings.breakEnabled=false;settings.exerciseEnabled=false
        var engine = EyeblinkEngine(settings:settings)
        let id = engine.startMeasurement(at:15)!,token = engine.state.cameraToken!
        engine.sample(cameraToken:token,token:id,at:16,faceValid:false,blinkDurations:[])
        engine.sample(cameraToken:token,token:id,at:25,faceValid:false,blinkDurations:[])
        XCTAssertNotNil(engine.state.measurement,"Scheduler must not duplicate detector's absence timer")
        engine.cameraDetectionFailed(token:token,reason:.noFace,at:25.001)
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.takeEffects(),[.measurementCancelled(id)])
    }
}
