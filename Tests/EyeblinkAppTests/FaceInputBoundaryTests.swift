import XCTest
import CryptoKit
import CFaceDetector
import CEyeFlow
import EyeblinkCore
@testable import EyeblinkApp

final class FaceInputBoundaryTests: XCTestCase {
    private struct Reference: Decodable {
        var originalSHA256: String
        var cases: [Frame]
        struct Frame: Decodable {
            var id: String; var width: Int; var height: Int; var stride: Int; var file: String; var sha256: String
            var smallWidth: Int; var smallHeight: Int; var smallBGRSHA256: String
            var faceCount: Int; var faces: [Face]; var selected: Bool
            var rect: [Int]?; var leftEye: [Double]?; var rightEye: [Double]?
        }
        struct Face: Decodable { var confidence: Int; var rect: [Int]; var landmarks: [Int] }
    }
    private struct Inputs {
        var root: URL; var reference: Reference
        func bgra(_ frame: Reference.Frame) throws -> [UInt8] {
            let data = try Data(contentsOf: root.appendingPathComponent(".deps/cnn-dimensions/" + frame.file))
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), frame.sha256, frame.id)
            var pixels = [UInt8](repeating: 255, count: frame.width * frame.height * 4)
            for y in 0..<frame.height { for x in 0..<frame.width { for c in 0..<3 {
                pixels[(y*frame.width+x)*4+c] = data[12+y*frame.stride+x*3+c]
            } } }
            return pixels
        }
    }
    private func inputs() throws -> Inputs {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        guard [cnn, root.appendingPathComponent(".deps/cnn-dimensions/cases.txt")].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Requires extracted original model and frozen public/synthetic dimension fixtures")
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalCNNDimensions", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.cases.count, 29)
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        return Inputs(root: root, reference: reference)
    }

    func testActualShippedSmallDimensionCNNAndSelection() throws {
        let inputs = try inputs()
        for frame in inputs.reference.cases {
            let pixels = try inputs.bgra(frame)
            var faces = [EyeFaceDetection](repeating: EyeFaceDetection(), count: 256)
            let count = pixels.withUnsafeBufferPointer {
                eyeface_detect_bgra($0.baseAddress, Int32(frame.width), Int32(frame.height), Int32(frame.width*4), &faces, 256)
            }
            XCTAssertEqual(Int(count), frame.faceCount, frame.id)
            let small = try Data(contentsOf: inputs.root.appendingPathComponent(".deps/cnn-dimensions/"+frame.id+".small.bgr"))
            XCTAssertEqual(SHA256.hash(data: small.dropFirst(12)).map { String(format: "%02x", $0) }.joined(), frame.smallBGRSHA256)
            var rawFaces = [EyeFaceDetection](repeating: EyeFaceDetection(), count: 256)
            let rawCount = small.withUnsafeBytes {
                eyeface_detect_bgr($0.baseAddress!.advanced(by: 12).assumingMemoryBound(to: UInt8.self), Int32(frame.smallWidth), Int32(frame.smallHeight), Int32(frame.smallWidth*3), &rawFaces, 256)
            }
            XCTAssertEqual(Int(rawCount), frame.faceCount, frame.id + " original quarter BGR")
            guard count == frame.faceCount, rawCount == frame.faceCount else { continue }
            for index in 0..<Int(count) {
                for actual in [faces[index], rawFaces[index]] {
                    let expected = frame.faces[index]
                    XCTAssertEqual(Int(actual.confidence), expected.confidence, frame.id)
                    XCTAssertEqual([actual.rect.x, actual.rect.y, actual.rect.width, actual.rect.height].map(Int.init), expected.rect, frame.id)
                    let values = withUnsafeBytes(of: actual.landmarks) { raw in (0..<10).map { Int(raw.loadUnaligned(fromByteOffset: $0*4, as: Int32.self)) } }
                    XCTAssertEqual(values, expected.landmarks, frame.id)
                }
            }
            var chosen = EyeFaceSelection()
            let selected = eyeface_select(&faces, count, Int32(frame.width), Int32(frame.height), nil, &chosen)
            XCTAssertEqual(selected == 1, frame.selected, frame.id)
            if selected == 1 {
                XCTAssertEqual([chosen.rect.x, chosen.rect.y, chosen.rect.width, chosen.rect.height].map(Int.init), frame.rect, frame.id)
                XCTAssertEqual([Double(chosen.leftEyeX), Double(chosen.leftEyeY), Double(chosen.eyeWidth)], frame.leftEye, frame.id)
                XCTAssertEqual([Double(chosen.rightEyeX), Double(chosen.rightEyeY), Double(chosen.eyeWidth)], frame.rightEye, frame.id)
            }
        }
    }

    func testProductionAnalysisHandlesNarrowFaceAndTooSmallNoFaceAfterPrime() throws {
        let inputs = try inputs()
        let predictor = try DlibShapePredictor(contentsOf: inputs.root.appendingPathComponent(".deps/models/data.dat"))
        let analysis = CameraFrameAnalysis()
        for name in ["face640x255", "black640x240"] {
            let frame = try XCTUnwrap(inputs.reference.cases.first { $0.id == name })
            let pixels = try inputs.bgra(frame)
            analysis.reset()
            _ = try pixels.withUnsafeBufferPointer {
                try analysis.prime(pixels: $0.baseAddress!, width: frame.width, height: frame.height, stride: frame.width*4,
                    clock: { FrameTimestamp(ticks: 0, frequency: 32) })
            }
            do {
                let result = try pixels.withUnsafeBufferPointer {
                    try analysis.process(pixels: $0.baseAddress!, width: frame.width, height: frame.height, stride: frame.width*4, predictor: predictor,
                        clock: { FrameTimestamp(ticks: 1, frequency: 32) })
                }
                XCTAssertEqual(result.eyes != nil, frame.selected, name)
                XCTAssertEqual(analysis.faceCount, frame.selected ? 1 : frame.faceCount, name)
                XCTAssertEqual(result.flowStatus, EF_WARMUP.rawValue, name)
                XCTAssertEqual(result.frameInterval, 0.03125, name)
                XCTAssertTrue(result.blinks.isEmpty, name)
            } catch { XCTFail("\(name) must use original face/no-face outcome, not throw: \(error)") }
        }
    }
}
