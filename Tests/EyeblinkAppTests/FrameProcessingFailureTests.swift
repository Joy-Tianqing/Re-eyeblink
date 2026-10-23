import XCTest
import CFaceDetector
import EyeblinkCore
@testable import EyeblinkApp

final class FrameProcessingFailureTests: XCTestCase {
    private func predictor() throws -> DlibShapePredictor {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard FileManager.default.fileExists(atPath:cnn.path) else { throw XCTSkip("Requires recovered original models") }
        var error = [CChar](repeating:0,count:512)
        XCTAssertEqual(cnn.path.withCString {eyeface_load_model($0,&error,error.count)},1,String(cString:error))
        return try DlibShapePredictor(contentsOf:root.appendingPathComponent(".deps/models/data.dat"))
    }

    func testZeroQuarterMatchesActualOriginalThrowVersusNormalNoFace() throws {
        _ = try predictor()
        struct Reference: Decodable {
            struct Frame: Decodable { var width:Int; var height:Int; var escapedModelToScratchCatch:Bool }
            var originalSHA256:String; var cases:[Frame]
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource:"OriginalZeroQuarter",withExtension:"json",subdirectory:"Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self,from:Data(contentsOf:url))
        XCTAssertEqual(reference.originalSHA256,"bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.cases.count,12)
        for frame in reference.cases {
            let pixels = [UInt8](repeating:0,count:frame.width*frame.height*4)
            var faces = [EyeFaceDetection](repeating:EyeFaceDetection(),count:256)
            let count = pixels.withUnsafeBufferPointer {
                eyeface_detect_bgra($0.baseAddress,Int32(frame.width),Int32(frame.height),Int32(frame.width*4),&faces,256)
            }
            XCTAssertEqual(count,frame.escapedModelToScratchCatch ? -1:0,"\(frame.width)x\(frame.height)")
        }
    }

    func testProcessingFailureCannotTurnAFullThreeMinuteRunIntoZeroMeasurement() throws {
        let predictor = try predictor(), run = CameraFrameRun()
        var settings = AppSettings()
        settings.trainingEnabled=false;settings.measurementEnabled=false;settings.exerciseEnabled=false;settings.breakEnabled=false
        var engine = EyeblinkEngine(settings:settings)
        let id = try XCTUnwrap(engine.startMeasurement(at:15)), token = try XCTUnwrap(engine.state.cameraToken)
        XCTAssertEqual(engine.state.measurement?.targetDuration,180,"Do not shorten production measurement timing")
        run.reset(generation:token,isPreview:false,noFaceTimeout:8,measurementDuration:180)
        let pixels = [UInt8](repeating:0,count:640*4)
        var acquired=0, clockCalls=0, failures=0, invalidErrorSamples=0, completed=0
        // Full 180s at32 synthetic callbacks/sec, with the actual 0.5s main
        // ticker. An error sample must not keep this lease alive until success.
        for index in 0...5762 {
            let base=Int64(15_000_000+index*31_250)
            var subclock:Int64=0
            let value = pixels.withUnsafeBufferPointer { buffer in
                run.process(predictor:predictor,receivedAt:Double(base)/1_000_000,clock:{
                    clockCalls += 1;defer {subclock += 1}
                    return .init(ticks:base+subclock,frequency:1_000_000)
                },acquirePixels:{
                    acquired += 1
                    return .init(pixels:buffer.baseAddress!,width:640,height:1,stride:2560)
                })
            }
            if let value {
                if value.isPriming { engine.cameraDidStart(token:token,at:value.uptime) }
                else if value.terminalFailure {
                    failures += 1
                    XCTAssertNotNil(value.error)
                    engine.setCameraPaused(true,reason:.unavailable,at:value.uptime)
                } else if value.measurementFinished {
                    completed += 1
                    engine.cameraMeasurementFinished(token:token,at:value.uptime)
                } else if let reason=value.detectionFailure {
                    engine.cameraDetectionFailed(token:token,reason:reason,at:value.uptime)
                } else {
                    if value.error != nil { invalidErrorSamples += 1 }
                    engine.sample(cameraToken:token,token:id,at:value.uptime,faceValid:value.error == nil && value.eyeDetectionValid,blinkDurations:value.blinkDurations)
                }
            }
            if index%16 == 0 { engine.advance(to:Double(base+10)/1_000_000) }
        }
        XCTAssertEqual(failures,1)
        XCTAssertEqual(invalidErrorSamples,0)
        XCTAssertEqual(completed,0)
        XCTAssertEqual(acquired,9,"Seven discarded reads, one prime, and one failing frame")
        XCTAssertEqual(clockCalls,4,"No queued callback may consume clocks after failure")
        XCTAssertTrue(engine.state.cameraPauseReasons.contains(.unavailable))
        XCTAssertNil(engine.state.measurement)
        XCTAssertEqual(engine.takeEffects(),[.measurementCancelled(id)])
        engine.cameraMeasurementFinished(token:token,at:196)
        XCTAssertTrue(engine.takeEffects().isEmpty,"Late completion cannot resurrect a failed lease")
    }

    func testPositiveQuarterRetainsOrdinaryNoFaceThenTimeoutSemantics() throws {
        let predictor = try predictor(), run = CameraFrameRun()
        run.reset(generation:UUID(),isPreview:false,noFaceTimeout:8,measurementDuration:180)
        let pixels = [UInt8](repeating:0,count:640*3*4)
        func sample(_ base:Int64) -> CameraObservation? {
            var subclock:Int64=0
            return pixels.withUnsafeBufferPointer { buffer in
                run.process(predictor:predictor,receivedAt:Double(base)/1_000_000,clock:{
                    defer {subclock += 1};return .init(ticks:base+subclock,frequency:1_000_000)
                },acquirePixels:{.init(pixels:buffer.baseAddress!,width:640,height:3,stride:2560)})
            }
        }
        XCTAssertTrue(try XCTUnwrap(sample(0)).isPriming)
        for time:Int64 in [31_250,62_500] {
            let normal = try XCTUnwrap(sample(time))
            XCTAssertFalse(normal.terminalFailure);XCTAssertNil(normal.error);XCTAssertNil(normal.detectionFailure)
            XCTAssertEqual(normal.faceCount,0);XCTAssertFalse(normal.eyeDetectionValid)
        }
        let noFace = try XCTUnwrap(sample(9_000_000))
        XCTAssertEqual(noFace.detectionFailure,.noFace)
        XCTAssertFalse(noFace.terminalFailure,"No-face still retries normally, unlike a processing exception")
        XCTAssertNil(noFace.error)
        XCTAssertNil(sample(10_000_000))
    }

    func testFailedAcquisitionStopsBeforePrimingAndFreshLeaseCanReconnect() throws {
        let predictor = try predictor(), run = CameraFrameRun()
        run.reset(generation:UUID(),isPreview:false,noFaceTimeout:8,measurementDuration:180)
        var acquisitions=0
        let failure=run.process(predictor:predictor,receivedAt:15,clock:{
            XCTFail("Acquisition failure cannot consume an analysis/ready clock")
            return .init(ticks:0,frequency:32)
        },acquirePixels:{
            acquisitions += 1
            throw CameraFrameAnalysis.AnalysisError.normalization
        })
        let failed=try XCTUnwrap(failure)
        XCTAssertTrue(failed.terminalFailure);XCTAssertNotNil(failed.error)
        XCTAssertFalse(failed.isPriming);XCTAssertNil(failed.detectionFailure)
        XCTAssertNil(run.process(predictor:predictor,receivedAt:200,clock:{
            XCTFail("Failed run must ignore queued clocks")
            return .init(ticks:6400,frequency:32)
        },acquirePixels:{
            XCTFail("Failed run must ignore queued pixels")
            throw CameraFrameAnalysis.AnalysisError.normalization
        }))
        XCTAssertEqual(acquisitions,1)
        let token=UUID()
        run.reset(generation:token,isPreview:false,noFaceTimeout:8,measurementDuration:180)
        let pixels=[UInt8](repeating:0,count:640*3*4)
        let ready=pixels.withUnsafeBufferPointer { buffer in
            run.process(predictor:predictor,receivedAt:201,clock:{.init(ticks:6432,frequency:32)},
                acquirePixels:{.init(pixels:buffer.baseAddress!,width:640,height:3,stride:2560)})
        }
        XCTAssertTrue(try XCTUnwrap(ready).isPriming)
        XCTAssertEqual(ready?.generation,token)
        XCTAssertNil(ready?.error)
    }
}
