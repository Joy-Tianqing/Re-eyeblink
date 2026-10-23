import XCTest
import CryptoKit
import CFaceDetector
import CEyeFlow
import EyeblinkCore
@testable import EyeblinkApp

final class WarmupPixelTests: XCTestCase {
    private struct Reference: Decodable {
        var originalSHA256: String
        var modelSHA256: String
        var cases: [Sequence]
        struct Sequence: Decodable { var name: String; var sessions: [Session] }
        struct Session: Decodable { var inputSHA256: String; var file: String; var frames: [Frame] }
        struct Frame: Decodable {
            var frame: Int
            var selected: Bool
            var leftEye: [Double]?
            var rightEye: [Double]?
            var flowSkippedForMissingPreviousFace: Bool
            var leftStats: [Double]
            var rightStats: [Double]
            var emissions: [Double]
            var count: Double
            var totalDuration: Double
        }
    }
    private func sha(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }

    private func fixtures() throws -> (URL, DlibShapePredictor, Reference) {
        let root = URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = root.appendingPathComponent(".deps/models/data.dat")
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        let folder = root.appendingPathComponent(".deps/warmup-pixels")
        guard [model,cnn,folder].allSatisfy({FileManager.default.fileExists(atPath:$0.path)}) else { throw XCTSkip("Requires recovered models and frozen public-pixel inputs") }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource:"OriginalWarmupPixels",withExtension:"json",subdirectory:"Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self,from:Data(contentsOf:fixture))
        XCTAssertEqual(reference.originalSHA256,"bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.cases.count,5)
        XCTAssertEqual(reference.cases.flatMap(\.sessions).flatMap(\.frames).count,52)
        let predictor = try DlibShapePredictor(contentsOf:model)
        XCTAssertEqual(predictor.metadata.sha256,reference.modelSHA256)
        XCTAssertEqual(sha(try Data(contentsOf:cnn)),"835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767")
        var error = [CChar](repeating:0,count:512)
        XCTAssertEqual(cnn.path.withCString {eyeface_load_model($0,&error,error.count)},1,String(cString:error))
        return (folder,predictor,reference)
    }

    func testOriginalPixelsThroughPendingCandidateLossRecoveryAndActualReopenReference() throws {
        let (folder,predictor,reference) = try fixtures()
        var legacyMismatchFrames: [String] = []
        for sequence in reference.cases {
            let analysis = CameraFrameAnalysis()
            var legacy = OpticalFlowStream()
            var count: Double = 0, total: Double = 0
            for (sessionIndex,session) in sequence.sessions.enumerated() {
                let input = try Data(contentsOf:folder.appendingPathComponent(session.file))
                XCTAssertEqual(sha(input),session.inputSHA256)
                let header = input.withUnsafeBytes { bytes in (0..<4).map { Int(bytes.loadUnaligned(fromByteOffset:$0*4,as:Int32.self)) } }
                XCTAssertEqual(header,[640,480,1920,session.frames.count])
                XCTAssertEqual(input.count,16+640*480*3*session.frames.count)
                if sessionIndex > 0 { analysis.reset(); legacy.reset() }
                for frame in session.frames {
                    var pixels = [UInt8](repeating:255,count:640*480*4)
                    for i in 0..<(640*480) { for c in 0..<3 { pixels[i*4+c]=input[16+frame.frame*640*480*3+i*3+c] } }
                    // The original reopen reference includes an actual pre-read.
                    // Seed the same pixel/time baseline, never a detected sample.
                    if sessionIndex > 0, frame.frame == 0 {
                        _ = try pixels.withUnsafeBufferPointer {
                            try analysis.prime(pixels:$0.baseAddress!,width:640,height:480,stride:2560,clock:{.init(ticks:0,frequency:32)})
                        }
                    }
                    let actual = try pixels.withUnsafeBufferPointer {
                        try analysis.process(pixels:$0.baseAddress!,width:640,height:480,stride:2560,predictor:predictor,
                            clock:{.init(ticks:Int64(frame.frame+(sessionIndex > 0 ? 1:0)),frequency:32)})
                    }
                    let context = "\(sequence.name) session\(sessionIndex) frame\(frame.frame)"
                    XCTAssertEqual(actual.eyes != nil,frame.selected,context)
                    if let eyes=actual.eyes {
                        XCTAssertEqual([eyes.left.center_x,eyes.left.center_y,eyes.left.width],frame.leftEye,context)
                        XCTAssertEqual([eyes.right.center_x,eyes.right.center_y,eyes.right.width],frame.rightEye,context)
                    }
                    XCTAssertEqual(actual.flowStatus,frame.flowSkippedForMissingPreviousFace ? EF_WARMUP.rawValue:EF_OK.rawValue,context)
                    XCTAssertEqual(actual.isValid,frame.selected,context)
                    XCTAssertEqual([actual.features.left.mean_y,actual.features.left.stddev_y],frame.leftStats,context)
                    XCTAssertEqual([actual.features.right.mean_y,actual.features.right.stddev_y],frame.rightStats,context)
                    XCTAssertEqual(actual.blinks,frame.emissions,context)
                    count += Double(actual.blinks.count);total += actual.blinks.reduce(0,+)
                    XCTAssertEqual(count,frame.count,context);XCTAssertEqual(total,frame.totalDuration,context)
                    // Counterfactual control uses the old unconditional scanner
                    // on actual derived features. This is not the original oracle.
                    let old = legacy.process(at:actual.uptime,leftMean:actual.features.left.mean_y,leftDeviation:actual.features.left.stddev_y,
                        rightMean:actual.features.right.mean_y,rightDeviation:actual.features.right.stddev_y,frameInterval:actual.frameInterval)
                    if old != actual.blinks { legacyMismatchFrames.append(context) }
                }
            }
        }
        XCTAssertTrue(legacyMismatchFrames.contains("singleRecovery session0 frame5"))
        XCTAssertTrue(legacyMismatchFrames.contains("singleRecovery session0 frame6"))
        XCTAssertTrue(legacyMismatchFrames.contains("reopenBeforeDeferredMerge session1 frame5"),"Early merge must affect the next camera lease, not merely UI timing")
    }
    func testOrderedFrameRunPreservesOriginalPixelEventsAndReopenState() throws {
        let (folder,predictor,reference) = try fixtures()
        for sequence in reference.cases {
            let run = CameraFrameRun()
            var count:Double=0,total:Double=0
            for session in sequence.sessions {
                let token=UUID()
                run.reset(generation:token,isPreview:true,noFaceTimeout:nil,measurementDuration:nil)
                let input=try Data(contentsOf:folder.appendingPathComponent(session.file))
                XCTAssertEqual(sha(input),session.inputSHA256)
                for frame in session.frames {
                    var pixels=[UInt8](repeating:255,count:640*480*4)
                    for i in 0..<(640*480) { for c in 0..<3 { pixels[i*4+c]=input[16+frame.frame*640*480*3+i*3+c] } }
                    if frame.frame == 0 {
                        let ready=pixels.withUnsafeBufferPointer { buffer in
                            run.process(predictor:predictor,receivedAt:0,clock:{.init(ticks:0,frequency:32)},
                                acquirePixels:{.init(pixels:buffer.baseAddress!,width:640,height:480,stride:2560)})
                        }
                        XCTAssertTrue(try XCTUnwrap(ready).isPriming)
                    }
                    let value=pixels.withUnsafeBufferPointer { buffer in
                        run.process(predictor:predictor,receivedAt:Double(frame.frame+1)/32,
                            clock:{.init(ticks:Int64(frame.frame+1),frequency:32)},
                            acquirePixels:{.init(pixels:buffer.baseAddress!,width:640,height:480,stride:2560)})
                    }
                    let observation=try XCTUnwrap(value)
                    let context="\(sequence.name) frame\(frame.frame)"
                    XCTAssertEqual(observation.generation,token,context)
                    XCTAssertFalse(observation.isPriming,context)
                    XCTAssertFalse(observation.terminalFailure,context)
                    XCTAssertFalse(observation.measurementFinished,context)
                    XCTAssertNil(observation.error,context)
                    XCTAssertNil(observation.detectionFailure,context)
                    XCTAssertEqual(observation.faceCount,frame.selected ? 1:0,context)
                    XCTAssertEqual(observation.eyeDetectionValid,frame.selected,context)
                    XCTAssertEqual(observation.blinkDurations,frame.emissions,context)
                    XCTAssertEqual(observation.framesPerSecond,32,accuracy:1e-12,context)
                    count += Double(observation.blinkDurations.count);total += observation.blinkDurations.reduce(0,+)
                    XCTAssertEqual(count,frame.count,context);XCTAssertEqual(total,frame.totalDuration,context)
                }
            }
        }
    }

}
