import XCTest
import CFaceDetector
import EyeblinkCore
@testable import EyeblinkApp

final class NoFaceTerminationTests: XCTestCase {
    private func fixtures() throws -> (DlibShapePredictor, [UInt8], URL) {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cnn = root.appendingPathComponent(".deps/models/eyeblink-face-v3.bin"), image = root.appendingPathComponent(".deps/eye-tracking/face.bgr")
        guard [cnn,image].allSatisfy({FileManager.default.fileExists(atPath:$0.path)}) else {throw XCTSkip("Requires recovered model andpublic crop")}
        var error = [CChar](repeating:0,count:512)
        XCTAssertEqual(cnn.path.withCString {eyeface_load_model($0,&error,error.count)},1,String(cString:error))
        let data = try Data(contentsOf:image);var face = [UInt8](repeating:255,count:640*480*4)
        for i in 0..<(640*480) {for c in 0..<3 {face[i*4+c]=data[8+i*3+c]}}
        return (try DlibShapePredictor(contentsOf:root.appendingPathComponent(".deps/models/data.dat")),face,root)
    }
    private func sample(_ analysis:CameraFrameAnalysis,_ pixels:[UInt8],_ predictor:DlibShapePredictor,_ frame:Int64,_ checked:Int64,frequency:Double=1_000_000) throws -> CameraFrameAnalysis.Result {
        try pixels.withUnsafeBufferPointer {
            try analysis.process(pixels:$0.baseAddress!,width:640,height:480,stride:640*4,predictor:predictor,
                clock:{.init(ticks:frame,frequency:frequency)},faceClock:{.init(ticks:checked,frequency:frequency)})
        }
    }
    private func assertNoFace(_ body:() throws -> CameraFrameAnalysis.Result,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertThrowsError(try body(),file:file,line:line) {error in
            guard case CameraFrameAnalysis.AnalysisError.noFace = error else {return XCTFail("Expected noFace,got \(error)",file:file,line:line)}
        }
    }
    func testOriginalNoFaceThresholdStopsAndLatchesUntilNewLease() throws {
        let (predictor,face,_) = try fixtures(),analysis = CameraFrameAnalysis()
        let black = [UInt8](repeating:0,count:face.count)
        analysis.reset(noFaceTimeout:1)
        _ = try sample(analysis,black,predictor,1_000_000,1_100_000)
        _ = try sample(analysis,black,predictor,2_000_000,2_100_500)
        assertNoFace {try sample(analysis,black,predictor,2_000_100,2_101_000)}
        assertNoFace {
            try black.withUnsafeBufferPointer {
                try analysis.process(pixels:$0.baseAddress!,width:640,height:480,stride:640*4,predictor:predictor,
                    clock:{XCTFail("Latched lease must not analyze another frame");return .init(ticks:3_000_000,frequency:1_000_000)},
                    faceClock:{XCTFail("Latched lease must not restarttimer");return .init(ticks:3_100_000,frequency:1_000_000)})
            }
        }
        XCTAssertThrowsError(try black.withUnsafeBufferPointer {
            try analysis.prime(pixels:$0.baseAddress!,width:640,height:480,stride:640*4,
                clock:{XCTFail("Expiredlease cannot prime again");return .init(ticks:0,frequency:1_000_000)})
        }) {error in
            guard case CameraFrameAnalysis.AnalysisError.noFace = error else {return XCTFail("Expected latchednoFace")}
        }
        analysis.reset(noFaceTimeout:1)
        _ = try sample(analysis,black,predictor,1_000_000,1_100_000)
    }
    func testRecoveryRestartsAbsenceAndDisabledPreviewNeverExpires() throws {
        let (predictor,face,_) = try fixtures(),analysis = CameraFrameAnalysis()
        let black = [UInt8](repeating:0,count:face.count)
        analysis.reset(noFaceTimeout:8)
        _ = try sample(analysis,black,predictor,1_000_000,1_100_000)
        _ = try sample(analysis,black,predictor,8_050_000,8_100_500)
        XCTAssertNotNil(try sample(analysis,face,predictor,8_150_000,8_200_000).eyes)
        XCTAssertNotNil(try sample(analysis,black,predictor,8_250_000,8_300_000).eyes,"Original reuseseyes untilfourth frame")
        XCTAssertNil(try sample(analysis,black,predictor,8_350_000,8_400_000).eyes)
        _ = try sample(analysis,black,predictor,16_350_000,16_400_500)
        assertNoFace {try sample(analysis,black,predictor,16_360_000,16_401_000)}
        analysis.reset(noFaceTimeout:nil)
        _ = try sample(analysis,black,predictor,1_000_000,1_100_000)
        _ = try sample(analysis,black,predictor,1_001_000_000,1_001_900_000)
    }
    func testTimeoutPreservesNextLeaseMotionLikeUnprocessedControl() throws {
        let (predictor,face,root) = try fixtures(),subject = CameraFrameAnalysis(),control = CameraFrameAnalysis()
        let black = [UInt8](repeating:0,count:face.count)
        let input = try Data(contentsOf:root.appendingPathComponent(".deps/tracked-motion/upperEyeShift6.frames"))
        var positive:[[UInt8]]=[]
        for index in 0..<7 {
            var pixels = [UInt8](repeating:255,count:face.count)
            for i in 0..<(640*480) {for c in 0..<3 {pixels[i*4+c]=input[16+index*640*480*3+i*3+c]}}
            positive.append(pixels)
        }
        for analysis in [subject,control] {
            analysis.reset(noFaceTimeout:1)
            for index in 0..<9 {
                let pixels = index<7 ? positive[index] : black
                _ = try sample(analysis,pixels,predictor,Int64(index+1),Int64(index+1),frequency:32)
            }
        }
        assertNoFace {try sample(subject,black,predictor,42,42,frequency:32)}
        subject.reset(noFaceTimeout:1);control.reset(noFaceTimeout:1)
        for index in 0..<7 {
            let a = try sample(subject,positive[index],predictor,Int64(index+1),Int64(index+1),frequency:32)
            let b = try sample(control,positive[index],predictor,Int64(index+1),Int64(index+1),frequency:32)
            XCTAssertEqual(a.blinks,b.blinks,"Expiredframe must not change retained merger before reset")
            XCTAssertEqual(a.features.left.mean_y,b.features.left.mean_y)
            XCTAssertEqual(a.features.right.mean_y,b.features.right.mean_y)
        }
    }
}
