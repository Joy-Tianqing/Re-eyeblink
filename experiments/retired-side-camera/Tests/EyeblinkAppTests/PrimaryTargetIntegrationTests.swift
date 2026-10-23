import XCTest
import Vision
import EyeblinkCore
@testable import EyeblinkApp

final class PrimaryTargetIntegrationTests: XCTestCase {
    /// Public fixture only. No camera access and no image file output.
    private func scene(bystander: Bool, user: Bool = true) throws -> [UInt8] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bgr = Array(try Data(contentsOf: root.appendingPathComponent(".deps/eye-tracking/face.bgr")).dropFirst(8))
        var source = [UInt8](repeating: 255,count: 640*480*4)
        for i in 0..<(640*480) { for c in 0..<3 { source[i*4+c] = bgr[i*3+c] } }
        let bitmap = CGBitmapInfo.byteOrder32Little.union(.init(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(source) as CFData))
        let image = try XCTUnwrap(CGImage(width: 640,height: 480,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 640*4,
            space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: bitmap,provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
        let request = VNDetectFaceRectanglesRequest(); request.revision = VNDetectFaceRectanglesRequestRevision3
        try VNImageRequestHandler(cgImage: image).perform([request])
        let box = try XCTUnwrap(request.results?.max { $0.boundingBox.width < $1.boundingBox.width }).boundingBox
        let x = max(0,Int((box.minX-box.width*0.1)*640)), y = max(0,Int((1-box.maxY-box.height*0.1)*480))
        let w = min(640-x,Int(box.width*1.2*640)), h = min(480-y,Int(box.height*1.2*480))
        var result = [UInt8](repeating: 32,count: 640*480*4)
        func place(_ dx: Int, _ dy: Int, _ dw: Int) {
            let dh = h*dw/w
            for row in 0..<dh { for col in 0..<dw {
                let origin = ((y+row*h/dh)*640+x+col*w/dw)*4
                let destination = ((dy+row)*640+dx+col)*4
                for c in 0..<4 { result[destination+c] = source[origin+c] }
            } }
        }
        if user { place(90,90,220) }
        if bystander { place(470,120,100) }
        return result
    }
    private func sample(_ pixels: [UInt8], adapter: SideCameraFrameAnalysis, time: Double) throws -> SideCameraSample {
        try pixels.withUnsafeBufferPointer { p in try adapter.extract(.init(pixels: p.baseAddress!,width: 640,height: 480,stride: 640*4),time: time) }
    }
    func testActualVisionKeepsEstablishedPrimaryGeometryWhenPublicBystanderAppears() throws {
        let solo = try scene(bystander: false), group = try scene(bystander: true)
        let adapter = SideCameraFrameAnalysis()
        var initial: SideCameraSample!
        for i in 0..<6 { initial = try sample(solo,adapter: adapter,time: 1+Double(i)*0.1) }
        XCTAssertEqual(initial.target?.status, .tracking); XCTAssertEqual(initial.target?.visibleFaceCount, 1)
        let result = try sample(group,adapter: adapter,time: 1.6)
        XCTAssertEqual(result.target?.visibleFaceCount, 2)
        XCTAssertEqual(result.target?.status, .tracking)
        XCTAssertEqual(result.faceCount, 1, "One selected target while two faces are visible")
        XCTAssertLessThan(hypot(result.faceCenter.x-initial.faceCenter.x,result.faceCenter.y-initial.faceCenter.y),0.05)
        XCTAssertNotNil(result.left); XCTAssertNotNil(result.right)
        let lost = try sample(try scene(bystander: true,user: false),adapter: adapter,time: 1.7)
        XCTAssertEqual(lost.target?.visibleFaceCount, 1); XCTAssertEqual(lost.target?.status, .lost)
        XCTAssertEqual(lost.faceCount, 0); XCTAssertNil(lost.left)
    }
    func testVisionPrimeCannotOverwriteEstablishedTargetWithUnrelatedBystander() throws {
        let solo = try scene(bystander: false), other = try scene(bystander: true,user: false)
        let adapter = SideCameraFrameAnalysis()
        for i in 0..<6 { _ = try sample(solo,adapter: adapter,time: 1+Double(i)*0.1) }
        adapter.endRun(); adapter.reset(key: "",noFaceTimeout: nil)
        try other.withUnsafeBufferPointer { p in
            _ = try adapter.prime(.init(pixels: p.baseAddress!,width: 640,height: 480,stride: 640*4), clock: { .init(ticks: 2_000_000,frequency: 1_000_000) })
        }
        let result = try sample(other,adapter: adapter,time: 2.1)
        XCTAssertEqual(result.target?.status, .lost)
        XCTAssertEqual(result.faceCount, 0)
    }
}
