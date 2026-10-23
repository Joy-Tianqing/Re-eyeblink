import XCTest
import CryptoKit
@testable import EyeblinkCore

final class DlibPredictorTests: XCTestCase {
    /// A small serialized model with independently specified split/leaf results.
    /// It checks strict > branching and inclusive dlib face coordinates.
    func testKnownTreeOutputsAndStrictBranchBoundary() throws {
        let model = try DlibShapePredictor(data: tinyModel())
        XCTAssertEqual(model.metadata.landmarkCount, 2)
        XCTAssertEqual(model.metadata.stageCount, 1)
        XCTAssertEqual(model.metadata.treeCount, 1)
        var gray = [UInt8](repeating: 0, count: 32 * 32)
        gray[10 * 32 + 10] = 200
        let face = DlibFaceRectangle(left: 10, top: 10, right: 20, bottom: 20)
        XCTAssertEqual(try model.predict(grayscale: gray, width: 32, height: 32, rectangle: face),
                       [CGPoint(x: 13, y: 13), CGPoint(x: 20, y: 10)])
        gray[10 * 32 + 20] = 200
        XCTAssertEqual(try model.predict(grayscale: gray, width: 32, height: 32, rectangle: face),
                       [CGPoint(x: 8, y: 10), CGPoint(x: 20, y: 10)])
    }

    func testOutOfImageFeaturesUseZeroAndOutputIsNotClamped() throws {
        let model = try DlibShapePredictor(data: tinyModel())
        let points = try model.predict(grayscale: [UInt8](repeating: 255, count: 100), width: 10, height: 10,
                                       rectangle: .init(left: -5, top: -5, right: 5, bottom: 5))
        XCTAssertEqual(points, [CGPoint(x: -7, y: -5), CGPoint(x: 5, y: -5)])
    }

    func testMalformedModelsAndImagesThrow() throws {
        let modelBytes = tinyModel()
        XCTAssertThrowsError(try DlibShapePredictor(data: modelBytes.dropLast()))
        XCTAssertThrowsError(try DlibShapePredictor(data: modelBytes + Data([0])))
        XCTAssertThrowsError(try DlibShapePredictor(data: Data([1, 2])))
        let model = try DlibShapePredictor(data: modelBytes)
        XCTAssertThrowsError(try model.predict(grayscale: [], width: 20, height: 20,
                                               rectangle: .init(left: 0, top: 0, right: 10, bottom: 10)))
        XCTAssertThrowsError(try model.predict(grayscale: [0], width: 1, height: 1,
                                               rectangle: .init(left: 1, top: 1, right: 0, bottom: 0)))
    }

    func testOriginalModelStructureAndDeterministicPrediction() throws {
        let model = try originalModel()
        XCTAssertEqual(model.metadata.sha256, "c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888")
        XCTAssertEqual(model.metadata.landmarkCount, 5)
        XCTAssertEqual(model.metadata.stageCount, 15)
        XCTAssertEqual(model.metadata.treeCount, 7_500)
        XCTAssertEqual(model.metadata.byteCount, 9_150_489)
        let width = 320, height = 240
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let ramp = x * 3 + y * 5
                let product = (x * y) % 251
                gray[y * width + x] = UInt8((ramp + product) % 256)
            }
        }
        let face = DlibFaceRectangle(left: 40, top: 20, right: 260, bottom: 220)
        let first = try model.predict(grayscale: gray, width: width, height: height, rectangle: face)
        let second = try model.predict(grayscale: gray, width: width, height: height, rectangle: face)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        // Determinism is not a claim of original runtime or general dlib parity.
    }

    func testOriginalModelMatchesOfficialDlib19_24OnEightFixedImages() throws {
        struct Reference: Decodable { let fixture: Int; let points: [[Int]] }
        let model = try originalModel()
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let results = root.appendingPathComponent("evidence/static/recovered-rules/dlib-reference-results.json")
        let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: results))
        XCTAssertEqual(references.map(\.fixture), Array(0..<8))
        for reference in references {
            let fixture = reference.fixture
            let width = 320, height = 240
            let gray = fixedGrayImage(fixture: fixture, width: width, height: height)
            let face = fixture < 4 ? DlibFaceRectangle(left: 40, top: 20, right: 260, bottom: 220)
                                   : DlibFaceRectangle(left: -20, top: -10, right: 210, bottom: 200)
            let points = try model.predict(grayscale: gray, width: width, height: height, rectangle: face)
            let expected = reference.points.map { CGPoint(x: Double($0[0]), y: Double($0[1])) }
            XCTAssertEqual(points, expected, "Official dlib reference fixture \(fixture)")
        }
    }

    func testOriginalModelMatchesShippedPredictorOnEightFrozenImages() throws {
        struct Case: Decodable { let fixture: Int; let graySHA256: String; let rectangle: [Int]; let points: [[Int]] }
        struct Reference: Decodable { let originalSHA256: String; let modelSHA256: String; let cases: [Case] }
        let model = try originalModel()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalShapePredictor", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.modelSHA256, model.metadata.sha256)
        XCTAssertEqual(reference.cases.map(\.fixture), Array(0..<8))
        for fixture in reference.cases {
            let gray = fixedGrayImage(fixture: fixture.fixture, width: 320, height: 240)
            let sha = SHA256.hash(data: Data(gray)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(sha, fixture.graySHA256, "Frozen original input must match")
            let box = fixture.rectangle
            let actual = try model.predict(grayscale: gray, width: 320, height: 240,
                rectangle: .init(left: box[0], top: box[1], right: box[2], bottom: box[3]))
            XCTAssertEqual(actual, fixture.points.map { CGPoint(x: $0[0], y: $0[1]) }, "Shipped predictor fixture \(fixture.fixture)")
        }
    }

    private func fixedGrayImage(fixture: Int, width: Int, height: Int) -> [UInt8] {
        var gray = [UInt8](repeating: 0, count: width * height)
        var random = UInt32(fixture + 1)
        for y in 0..<height {
            for x in 0..<width {
                var value = 0
                switch fixture % 4 {
                case 0: value = (x * 3 + y * 5 + (x * y) % 251) % 256
                case 2: value = (x + y) % 256
                case 3:
                    random = random &* 1_664_525 &+ 1_013_904_223
                    value = Int(random >> 24)
                default: break
                }
                gray[y * width + x] = UInt8(value)
            }
        }
        return gray
    }

    private func originalModel() throws -> DlibShapePredictor {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = ProcessInfo.processInfo.environment["EYEBLINK_DLIB_MODEL"].map(URL.init(fileURLWithPath:)) ?? root.appendingPathComponent(".deps/models/data.dat")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("Original analysis model is local-only; set EYEBLINK_DLIB_MODEL to verify it")
        }
        return try DlibShapePredictor(contentsOf: path)
    }

    private func tinyModel() -> Data {
        var bytes: [UInt8] = []
        func integer(_ value: Int64) {
            var magnitude = UInt64(value < 0 ? -value : value)
            var payload: [UInt8] = []
            repeat { payload.append(UInt8(magnitude & 255)); magnitude >>= 8 } while magnitude > 0
            bytes.append(UInt8(payload.count) | (value < 0 ? 128 : 0)); bytes += payload
        }
        func floating(_ value: Float) {
            if value == 0 { integer(0); integer(0); return }
            var exponent: Int32 = 0
            let fraction = frexp(Double(value), &exponent)
            integer(Int64(fraction * 16_777_216)); integer(Int64(exponent) - 24)
        }
        func matrix(_ values: [Float]) { integer(-Int64(values.count)); integer(-1); values.forEach(floating) }
        integer(1) // predictor version
        matrix([0, 0, 1, 0])
        integer(1); integer(1) // one stage, one tree
        integer(1); integer(0); integer(1); floating(0) // one strict feature difference split
        integer(2); matrix([0.25, 0.25, 0, 0]); matrix([-0.25, 0, 0, 0])
        integer(1); integer(2); integer(0); integer(1) // anchor stage, two landmarks
        integer(1); integer(2); [Float](repeating: 0, count: 4).forEach(floating)
        return Data(bytes)
    }
}
