import XCTest
import CryptoKit
import CFaceDetector
import EyeblinkCore
@testable import EyeblinkApp

final class CameraEyeTrackingTests: XCTestCase {
    private struct Reference: Decodable {
        let originalSHA256: String
        let inputSHA256: String
        let modelSHA256: String
        let sequences: [Sequence]
        struct Sequence: Decodable { let name: String; let frames: [Frame] }
        struct Frame: Decodable {
            let frame: Int
            let faceInput: Bool
            let selected: Bool
            let leftEye: [Double]?
            let rightEye: [Double]?
        }
    }

    func testOriginalImageCNNPredictorReuseAndDelayedRecovery() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let input = root.appendingPathComponent(".deps/eye-tracking/face.bgr")
        let model = root.appendingPathComponent(".deps/models/data.dat")
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard [input, model, cnn].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Requires private extracted models and frozen public image; run materialize_eye_tracking.py first")
        }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "OriginalEyeTracking", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        let data = try Data(contentsOf: input)
        XCTAssertEqual(sha(data), reference.inputSHA256)
        XCTAssertEqual(sha(try Data(contentsOf: cnn)), "835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767")
        let predictor = try DlibShapePredictor(contentsOf: model)
        XCTAssertEqual(predictor.metadata.sha256, reference.modelSHA256)
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        let width = Int(data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        let height = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int32.self) })
        XCTAssertEqual(width, 640); XCTAssertEqual(height, 480)
        var face = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            for c in 0..<3 { face[i*4+c] = data[8+i*3+c] }
        }
        let black = [UInt8](repeating: 0, count: face.count)
        var tracker = CameraEyeTracking()
        XCTAssertEqual(reference.sequences.map(\.frames.count), [5, 9])
        for sequence in reference.sequences {
            // Exercise the same production reset used on camera start. The
            // second run starts after the first has a tracked face and cursor 5.
            tracker.reset()
            for frame in sequence.frames {
                let pixels = frame.faceInput ? face : black
                let actual = try pixels.withUnsafeBufferPointer {
                    try tracker.process(pixels: $0.baseAddress!, width: width, height: height, stride: width*4, predictor: predictor)
                }
                let context = "\(sequence.name) frame \(frame.frame)"
                XCTAssertEqual(actual != nil, frame.selected, context)
                if let actual {
                    XCTAssertEqual([actual.left.center_x, actual.left.center_y, actual.left.width], frame.leftEye, context)
                    XCTAssertEqual([actual.right.center_x, actual.right.center_y, actual.right.width], frame.rightEye, context)
                    XCTAssertEqual(tracker.faceCount, 1, context)
                }
            }
        }
    }

    private func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
