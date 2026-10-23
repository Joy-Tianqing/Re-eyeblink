import XCTest
import CryptoKit
import CFaceDetector
import EyeblinkCore
@testable import EyeblinkApp

final class OriginalRecognitionFrameRunTests: XCTestCase {
    private struct Reference: Decodable {
        var originalSHA256: String
        var sequences: [Sequence]
        struct Sequence: Decodable {
            var name: String
            var inputSHA256: String
            var frames: [Frame]
        }
        struct Frame: Decodable {
            var frame: Int
            var selected: Bool
            var emissions: [Double]
        }
    }

    func testProductionTrainingAndMeasurementEmitOriginalFirstBlinkWithoutCalibration() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let predictor = try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat"))
        let model = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(model.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "OriginalTrackedMotion", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        let sequence = try XCTUnwrap(reference.sequences.first { $0.name == "upperEyeShift6" })
        let bytes = try Data(contentsOf: root.appendingPathComponent(".deps/tracked-motion/upperEyeShift6.frames"))
        XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), sequence.inputSHA256)
        for lease in 0..<2 {
            // Each reference sequence begins at original Model construction.
            // Reopen merger continuity is covered by OriginalTemporalTests.
            let run = CameraFrameRun()
            let token = UUID()
            run.reset(generation: token, isPreview: false, noFaceTimeout: lease == 0 ? 1 : 8, measurementDuration: lease == 0 ? nil : 180)
            func sample(_ pixels: [UInt8], tick: Int64) throws -> CameraObservation {
                try pixels.withUnsafeBufferPointer { buffer in
                    try XCTUnwrap(run.process(predictor: predictor, receivedAt: Double(tick) / 32,
                        clock: { .init(ticks: tick, frequency: 32) }, acquirePixels: {
                            .init(pixels: buffer.baseAddress!, width: 640, height: 480, stride: 640 * 4)
                        }))
                }
            }
            XCTAssertTrue(try sample([UInt8](repeating: 0, count: 640 * 480 * 4), tick: Int64(lease * 3200)).isPriming)
            var emissions: [Double] = []
            for frame in sequence.frames {
                var bgra = [UInt8](repeating: 255, count: 640 * 480 * 4)
                let offset = 16 + frame.frame * 640 * 480 * 3
                for pixel in 0..<(640 * 480) {
                    for channel in 0..<3 { bgra[pixel * 4 + channel] = bytes[offset + pixel * 3 + channel] }
                }
                let value = try sample(bgra, tick: Int64(lease * 3200 + frame.frame + 1))
                XCTAssertEqual(value.generation, token)
                XCTAssertNil(value.error)
                XCTAssertNil(value.detectionFailure)
                XCTAssertFalse(value.terminalFailure)
                XCTAssertEqual(value.eyeDetectionValid, frame.selected)
                XCTAssertEqual(value.blinkDurations, frame.emissions, "Lease \(lease), frame \(frame.frame)")
                emissions += value.blinkDurations
                if lease == 0, !emissions.isEmpty {
                    let finished = run.process(predictor: predictor, receivedAt: Double(frame.frame + 2) / 32,
                        clock: { .init(ticks: Int64(frame.frame + 2), frequency: 32) }, acquirePixels: {
                            XCTFail("Training success is checked before the next read")
                            throw CameraReadError.cancelled
                        })
                    XCTAssertEqual(finished?.trainingReaction, true)
                    break
                }
            }
            XCTAssertFalse(emissions.isEmpty, "The first original blink must not be consumed by three-blink calibration")
        }
    }
}
