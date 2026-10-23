import XCTest
import CFaceDetector
import CEyeFlow
import EyeblinkCore
@testable import EyeblinkApp

final class FaceClockPhaseTests: XCTestCase {
    private func fixtures() throws -> (DlibShapePredictor, [UInt8]) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin")
        let input = root.appendingPathComponent(".deps/eye-tracking/face.bgr")
        guard [cnn, input].allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { throw XCTSkip("Requires extracted model and fixed public crop") }
        var error = [CChar](repeating: 0, count: 512)
        XCTAssertEqual(cnn.path.withCString { eyeface_load_model($0, &error, error.count) }, 1, String(cString: error))
        let raw = try Data(contentsOf: input)
        var pixels = [UInt8](repeating: 255, count: 640*480*4)
        for i in 0..<(640*480) { for c in 0..<3 { pixels[i*4+c] = raw[8+i*3+c] } }
        return (try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat")), pixels)
    }
    func testFaceClockRunsAfterTrackingWithoutChangingFrameIntervals() throws {
        let (predictor, face) = try fixtures(), analysis = CameraFrameAnalysis()
        let black = [UInt8](repeating: 0, count: face.count)
        var frameCalls = 0, faceCalls = 0
        for index in 0..<7 {
            let pixels = [4,5].contains(index) ? black : face
            let result = try pixels.withUnsafeBufferPointer {
                try analysis.process(pixels: $0.baseAddress!, width: 640, height: 480, stride: 640*4, predictor: predictor,
                    clock: { frameCalls += 1; return .init(ticks: Int64(10_000+index*100), frequency: 1000) },
                    faceClock: {
                        faceCalls += 1
                        XCTAssertEqual(analysis.faceCount, 0, "Face decision must finish before this clock")
                        return .init(ticks: Int64(10_050+index*100), frequency: 1000)
                    })
            }
            XCTAssertEqual(result.uptime, 10 + Double(index)/10)
            XCTAssertEqual(result.frameInterval, index == 0 ? nil : 0.1, "Face clock must not enterframe dt/FPS")
            if [4,5].contains(index) {
                XCTAssertNil(result.eyes)
            } else { XCTAssertNotNil(result.eyes) }
        }
        XCTAssertEqual(frameCalls, 7)
        XCTAssertEqual(faceCalls, 2, "No no-face clock while face is present/recovered")
    }
    func testInvalidOrEarlierFaceClockIsRejected() throws {
        let (predictor, face) = try fixtures()
        let black = [UInt8](repeating: 0, count: face.count)
        for bad in [FrameTimestamp(ticks: 9000, frequency: 1000), .init(ticks: 10000, frequency: .nan), .init(ticks: 20000, frequency: 2000)] {
            let analysis = CameraFrameAnalysis()
            XCTAssertThrowsError(try black.withUnsafeBufferPointer {
                try analysis.process(pixels: $0.baseAddress!, width: 640, height: 480, stride: 640*4, predictor: predictor,
                    clock: { .init(ticks: 10000, frequency: 1000) }, faceClock: { bad })
            })
        }
    }
}
