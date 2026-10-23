import XCTest
import CryptoKit
import CFaceDetector
import CEyeFlow
import EyeblinkCore
@testable import EyeblinkApp

final class CameraFrameAnalysisTests: XCTestCase {
    private struct Reference: Decodable {
        var originalSHA256: String
        var modelSHA256: String
        var sequences: [Sequence]
        struct Sequence: Decodable { var name: String; var inputSHA256: String; var frames: [Frame] }
        struct Frame: Decodable {
            var frame: Int
            var time: Double
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

    func testOriginalTrackedImagesThroughFeaturesAndEvents() throws {
        try compareOriginalFrames(rawScale: 1)
    }

    func testOriginalDoubledInputNormalizesBeforeTrackingAndPositiveEvent() throws {
        try compareOriginalFrames(rawScale: 2, names: ["upperEyeShift6"])
    }

    func testPreReadBlackFramePreservesOriginalPositiveAnalyzedSequence() throws {
        try compareOriginalFrames(rawScale: 2, names: ["upperEyeShift6"], primeFirst: true)
    }

    func testPreReadSeedsFirstAnalyzedIntervalAnd31FrameRateWindow() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = root.appendingPathComponent(".deps/models/data.dat")
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard [model, cnn].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("Requires extracted models") }
        let predictor = try DlibShapePredictor(contentsOf: model)
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        let analysis = CameraFrameAnalysis()
        let black = [UInt8](repeating: 0, count: 800*600*4)
        var clockCalls = 0
        let baseline = try black.withUnsafeBufferPointer {
            try analysis.prime(pixels: $0.baseAddress!, width: 800, height: 600, stride: 800*4,
                clock: { clockCalls += 1; return FrameTimestamp(ticks: 0, frequency: 32) })
        }
        XCTAssertTrue(analysis.hasTimeBaseline)
        XCTAssertEqual(analysis.faceCount, 0)
        var monitor = FrameRateMonitor()
        XCTAssertNil(monitor.observe(at: baseline.uptime))
        for index in 1...31 {
            let result = try black.withUnsafeBufferPointer {
                try analysis.process(pixels: $0.baseAddress!, width: 800, height: 600, stride: 800*4, predictor: predictor,
                    clock: { clockCalls += 1; return FrameTimestamp(ticks: Int64(index), frequency: 32) })
            }
            XCTAssertEqual(result.frameInterval, 0.03125, "analyzed frame \(index)")
            let rate = monitor.observe(at: result.uptime, frameInterval: result.frameInterval)
            if index < 31 { XCTAssertNil(rate) } else { XCTAssertEqual(rate, 32) }
            XCTAssertTrue(result.blinks.isEmpty)
        }
        XCTAssertEqual(clockCalls, 32, "One pre-read plus31 analyzed frames")
    }

    func testNormalizationFailureDoesNotConsumeMotionClock() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let modelURL = root.appendingPathComponent(".deps/models/data.dat")
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw XCTSkip("Requires extracted predictor model") }
        let predictor = try DlibShapePredictor(contentsOf: modelURL)
        let analysis = CameraFrameAnalysis()
        let pixels = [UInt8](repeating: 0, count: 1280*4)
        var clockCalls = 0
        // Valid raw stride/dimensions reach the actual C normalizer, where
        // Float height/2 truncates to zero. No analyzed frame may be timestamped.
        XCTAssertThrowsError(try pixels.withUnsafeBufferPointer {
            try analysis.process(pixels: $0.baseAddress!, width: 1280, height: 1, stride: 1280*4, predictor: predictor,
                clock: { clockCalls += 1; return FrameTimestamp(ticks: 100, frequency: 1) })
        })
        XCTAssertEqual(clockCalls, 0)
    }

    func testResetAndInvalidationStartANewIntegerClockOrigin() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = root.appendingPathComponent(".deps/models/data.dat")
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard [model, cnn].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("Requires extracted models") }
        let predictor = try DlibShapePredictor(contentsOf: model)
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        let analysis = CameraFrameAnalysis()
        let black = [UInt8](repeating: 0, count: 640*480*4)
        func sample(_ tick: Int64) throws -> CameraFrameAnalysis.Result {
            try black.withUnsafeBufferPointer {
                try analysis.process(pixels: $0.baseAddress!, width: 640, height: 480, stride: 640*4, predictor: predictor,
                    clock: { FrameTimestamp(ticks: tick, frequency: 32) })
            }
        }
        XCTAssertNil(try sample(0).frameInterval)
        XCTAssertEqual(try sample(1).frameInterval, 0.03125)
        analysis.reset()
        XCTAssertNil(try sample(0).frameInterval)
        XCTAssertEqual(try sample(1).frameInterval, 0.03125)
        analysis.invalidate()
        XCTAssertNil(try sample(0).frameInterval)
        XCTAssertEqual(try sample(1).frameInterval, 0.03125)
    }

    private func compareOriginalFrames(rawScale: Int, names: Set<String>? = nil, primeFirst: Bool = false) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent(".deps/tracked-motion")
        let predictorURL = root.appendingPathComponent(".deps/models/data.dat")
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard [folder, predictorURL, cnn].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Requires private extracted models and frozen public-image inputs; run materialize_tracked_motion.py")
        }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "OriginalTrackedMotion", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        let predictor = try DlibShapePredictor(contentsOf: predictorURL)
        XCTAssertEqual(predictor.metadata.sha256, reference.modelSHA256)
        XCTAssertEqual(sha(try Data(contentsOf: cnn)), "835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767")
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        XCTAssertEqual(reference.sequences.map(\.frames.count), [9, 9, 7, 7, 9, 9])
        for sequence in reference.sequences where names == nil || names!.contains(sequence.name) {
            let input = try Data(contentsOf: folder.appendingPathComponent(sequence.name + ".frames"))
            XCTAssertEqual(sha(input), sequence.inputSHA256)
            let header: [Int] = input.withUnsafeBytes { bytes in (0..<4).map { Int(bytes.loadUnaligned(fromByteOffset: $0*4, as: Int32.self)) } }
            let width = header[0], height = header[1], stride = header[2]
            XCTAssertEqual(header, [640, 480, 1920, sequence.frames.count])
            XCTAssertEqual(input.count, 16 + stride * height * sequence.frames.count)
            // Actual production path called by captureOutput; no session,
            // permissions, UI, synthetic landmarks, or supplied flow features.
            let analysis = CameraFrameAnalysis()
            if primeFirst {
                let black = [UInt8](repeating: 0, count: width*rawScale*height*rawScale*4)
                _ = try black.withUnsafeBufferPointer {
                    try analysis.prime(pixels: $0.baseAddress!, width: width*rawScale, height: height*rawScale, stride: width*rawScale*4,
                        clock: { FrameTimestamp(ticks: 0, frequency: 32) })
                }
            }
            var count: Double = 0, duration: Double = 0
            for frame in sequence.frames {
                let rawWidth = width * rawScale, rawHeight = height * rawScale
                var bgra = [UInt8](repeating: 255, count: rawWidth * rawHeight * 4)
                let offset = 16 + frame.frame * stride * height
                for y in 0..<rawHeight {
                    for x in 0..<rawWidth {
                        for c in 0..<3 { bgra[(y*rawWidth+x)*4+c] = input[offset+(y/rawScale)*stride+(x/rawScale)*3+c] }
                    }
                }
                var clockCalls = 0, faceClockCalls = 0
                let stamp = FrameTimestamp(ticks: Int64(frame.frame + (primeFirst ? 1 : 0)), frequency: 32)
                let actual = try bgra.withUnsafeBufferPointer {
                    try analysis.process(pixels: $0.baseAddress!, width: rawWidth, height: rawHeight, stride: rawWidth*4, predictor: predictor,
                        clock: { clockCalls += 1; return stamp },
                        faceClock: { faceClockCalls += 1; return stamp })
                }
                let context = "\(sequence.name) frame \(frame.frame)"
                XCTAssertEqual(actual.uptime, frame.time + (primeFirst ? 0.03125 : 0), context)
                XCTAssertEqual(clockCalls, 1, context)
                XCTAssertEqual(faceClockCalls, frame.selected ? 0 : 1, context)
                XCTAssertEqual(actual.frameInterval, !primeFirst && frame.frame == 0 ? nil : 0.03125, context)
                XCTAssertEqual(actual.eyes != nil, frame.selected, context)
                if let eyes = actual.eyes {
                    XCTAssertEqual([eyes.left.center_x, eyes.left.center_y, eyes.left.width], frame.leftEye, context)
                    XCTAssertEqual([eyes.right.center_x, eyes.right.center_y, eyes.right.width], frame.rightEye, context)
                }
                XCTAssertEqual(actual.flowStatus, frame.flowSkippedForMissingPreviousFace ? EF_WARMUP.rawValue : EF_OK.rawValue, context)
                XCTAssertEqual([actual.features.left.mean_y, actual.features.left.stddev_y], frame.leftStats, context)
                XCTAssertEqual([actual.features.right.mean_y, actual.features.right.stddev_y], frame.rightStats, context)
                XCTAssertEqual(actual.isValid, frame.selected, context)
                XCTAssertEqual(actual.blinks, frame.emissions, context)
                count += Double(actual.blinks.count); duration += actual.blinks.reduce(0, +)
                XCTAssertEqual(count, frame.count, context)
                XCTAssertEqual(duration, frame.totalDuration, context)
            }
        }
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
