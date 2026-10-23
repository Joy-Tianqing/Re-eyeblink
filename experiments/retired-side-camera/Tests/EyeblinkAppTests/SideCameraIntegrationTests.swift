import XCTest
import Vision
import EyeblinkCore
@testable import EyeblinkApp

final class SideCameraIntegrationTests: XCTestCase {
    private func predictor() throws -> DlibShapePredictor {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try DlibShapePredictor(contentsOf: root.appendingPathComponent(".deps/models/data.dat"))
    }
    private func stamp(_ seconds: Double) -> FrameTimestamp { .init(ticks: Int64((seconds*1_000_000).rounded()), frequency: 1_000_000) }
    private func withInput<T>(_ body: (CameraFrameInput) throws -> T) rethrows -> T {
        try [UInt8](repeating: 0, count: 640*480*4).withUnsafeBufferPointer { p in
            try body(.init(pixels: p.baseAddress!, width: 640, height: 480, stride: 640*4))
        }
    }
    func testRealVisionAdapterBlackFrameIsNoFaceRatherThanValidZeroBlink() throws {
        let adapter = SideCameraFrameAnalysis()
        let sample = try withInput { try adapter.extract($0, time: 1) }
        XCTAssertEqual(sample.faceCount, 0)
        XCTAssertNil(sample.left); XCTAssertNil(sample.right); XCTAssertNil(sample.yaw)
        var d = SideCameraBlinkDetector()
        XCTAssertFalse(d.process(sample).valid)
    }
    func testRealVisionAdapterPublicMultiFaceInputCannotImmediatelyBecomeTrustedBlinkTarget() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bgr = try Data(contentsOf: root.appendingPathComponent(".deps/eye-tracking/face.bgr")).dropFirst(8)
        var bgra = [UInt8](repeating: 255, count: 640*480*4)
        let bytes = Array(bgr)
        for i in 0..<(640*480) { for channel in 0..<3 { bgra[i*4+channel] = bytes[i*3+channel] } }
        let adapter = SideCameraFrameAnalysis()
        let sample = try bgra.withUnsafeBufferPointer { p in
            try adapter.extract(.init(pixels: p.baseAddress!, width: 640, height: 480, stride: 640*4), time: 1)
        }
        XCTAssertEqual(sample.target?.visibleFaceCount, 4)
        XCTAssertNotEqual(sample.target?.status, .tracking)
        var d = SideCameraBlinkDetector()
        let result = d.process(sample)
        XCTAssertFalse(result.valid); XCTAssertTrue(result.blinks.isEmpty)
    }
    func testSideModeDeadlineBeforePixelAcquisitionCarriesZeroCoverageAndLatches() throws {
        let run = CameraFrameRun(), predictor = try predictor(), generation = UUID()
        run.reset(generation: generation, isPreview: false, noFaceTimeout: 8, measurementDuration: 180, mode: .sideCamera, calibrationKey: "camera-A")
        withInput { input in
            let prime = run.process(predictor: predictor, receivedAt: 0, clock: { self.stamp(0) }, acquirePixels: { input })
            XCTAssertEqual(prime?.isPriming, true)
            var acquired = false
            let done = run.process(predictor: predictor, receivedAt: 180.001, clock: { self.stamp(180.001) }, acquirePixels: { acquired = true; return input })
            XCTAssertFalse(acquired); XCTAssertEqual(done?.measurementFinished, true)
            XCTAssertEqual(done?.generation, generation)
            XCTAssertEqual(done?.detection?.algorithm, "side-contour-v4")
            XCTAssertEqual(done?.detection?.isAcceptable, false)
            let late = run.process(predictor: predictor, receivedAt: 181, clock: { XCTFail("Must not read a queued clock"); return self.stamp(181) }, acquirePixels: { acquired = true; return input })
            XCTAssertNil(late); XCTAssertFalse(acquired)
        }
    }
    func testRealVisionSinglePublicFaceProducesResolvedEyeGeometryAndPose() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bgr = Array(try Data(contentsOf: root.appendingPathComponent(".deps/eye-tracking/face.bgr")).dropFirst(8))
        var bgra = [UInt8](repeating: 255, count: 640*480*4)
        for i in 0..<(640*480) { for c in 0..<3 { bgra[i*4+c] = bgr[i*3+c] } }
        let bitmap = CGBitmapInfo.byteOrder32Little.union(.init(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bgra) as CFData))
        let image = try XCTUnwrap(CGImage(width: 640,height: 480,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 640*4,
            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: bitmap,provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        let request = VNDetectFaceRectanglesRequest(); request.revision = VNDetectFaceRectanglesRequestRevision3
        try VNImageRequestHandler(cgImage: image).perform([request])
        let face = try XCTUnwrap(request.results?.max { $0.boundingBox.width < $1.boundingBox.width })
        let box = face.boundingBox
        let x = max(0, Int((box.minX-box.width*0.1)*640)), y = max(0, Int((1-box.maxY-box.height*0.1)*480))
        let w = min(640-x, Int(box.width*1.2*640)), h = min(480-y, Int(box.height*1.2*480))
        var crop = [UInt8](); crop.reserveCapacity(w*h*4)
        for row in y..<(y+h) { crop.append(contentsOf: bgra[(row*640+x)*4..<(row*640+x+w)*4]) }
        let sample = try crop.withUnsafeBufferPointer { p in
            try SideCameraFrameAnalysis().extract(.init(pixels: p.baseAddress!,width: w,height: h,stride: w*4), time: 1)
        }
        XCTAssertEqual(sample.faceCount, 1)
        XCTAssertGreaterThan(try XCTUnwrap(sample.left).width, 10)
        XCTAssertGreaterThan(try XCTUnwrap(sample.right).width, 10)
        XCTAssertNotNil(sample.yaw); XCTAssertNotNil(sample.pitch); XCTAssertNotNil(sample.roll)
    }
    func testSideModeNoFaceFailureRemainsOrderedAndFreshLeaseCanPrime() throws {
        let run = CameraFrameRun(), predictor = try predictor()
        run.reset(generation: UUID(), isPreview: false, noFaceTimeout: 8, measurementDuration: 180, mode: .sideCamera, calibrationKey: "camera-A")
        withInput { input in
            _ = run.process(predictor: predictor, receivedAt: 0, clock: { self.stamp(0) }, acquirePixels: { input })
            let first = run.process(predictor: predictor, receivedAt: 1, clock: { self.stamp(1) }, acquirePixels: { input })
            XCTAssertEqual(first?.sideCamera?.status, .noFace)
            let failure = run.process(predictor: predictor, receivedAt: 9.002, clock: { self.stamp(9.002) }, acquirePixels: { input })
            XCTAssertEqual(failure?.detectionFailure, .noFace)
            XCTAssertNil(run.process(predictor: predictor, receivedAt: 200, clock: { self.stamp(200) }, acquirePixels: { input }))
            run.reset(generation: UUID(), isPreview: true, noFaceTimeout: nil, measurementDuration: nil, mode: .sideCamera, calibrationKey: "camera-B")
            XCTAssertEqual(run.process(predictor: predictor, receivedAt: 201, clock: { self.stamp(201) }, acquirePixels: { input })?.isPriming, true)
        }
    }
    func testSideAcquisitionFailureIsTerminalBeforeCalibration() throws {
        let run = CameraFrameRun(), predictor = try predictor()
        run.reset(generation: UUID(), isPreview: true, noFaceTimeout: nil, measurementDuration: nil, mode: .sideCamera)
        let result = run.process(predictor: predictor, receivedAt: 0, clock: { XCTFail("No clock before pixels"); return self.stamp(0) }, acquirePixels: { throw CameraFrameAnalysis.AnalysisError.normalization })
        XCTAssertEqual(result?.terminalFailure, true)
        XCTAssertNil(result?.sideCamera)
    }
}
