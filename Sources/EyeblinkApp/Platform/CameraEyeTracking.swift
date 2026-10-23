import Foundation
import EyeblinkCore
import CFaceDetector
import CEyeFlow

/// Ordered production tracking stage; no session, camera, UI, or permission APIs.
struct CameraEyeTracking {
    typealias Eyes = (left: EFEye, right: EFEye, normalizer: Double)
    private var frameIndex = 0
    private var currentEyes: Eyes?
    private(set) var faceCount = 0
    private var grayPixels: [UInt8] = []
    private var previousFace: EyeFaceRect?

    mutating func reset() {
        frameIndex = 0; currentEyes = nil; faceCount = 0; previousFace = nil
    }

    mutating func invalidateEyes() { currentEyes = nil }

    mutating func process(pixels: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int,
                          predictor: DlibShapePredictor) throws -> Eyes? {
        if frameIndex % 4 == 0 || currentEyes == nil {
            var faces = Array(repeating: EyeFaceDetection(), count: 256)
            let count = eyeface_detect_bgra(pixels, Int32(width), Int32(height), Int32(stride), &faces, Int32(faces.count))
            guard count >= 0 else { throw TrackingError.faceModel("人脸检测未能完成。") }
            var selection = EyeFaceSelection()
            let found: Int32
            if var previousFace {
                found = eyeface_select(&faces, count, Int32(width), Int32(height), &previousFace, &selection)
            } else { found = eyeface_select(&faces, count, Int32(width), Int32(height), nil, &selection) }
            faceCount = found == 1 ? 1 : Int(count)
            currentEyes = nil
            if found == 1 {
                previousFace = selection.rect
                let geometry: EyeGeometry
                if frameIndex % 4 == 0 {
                    if grayPixels.count != width * height { grayPixels = Array(repeating: 0, count: width * height) }
                    let status = grayPixels.withUnsafeMutableBufferPointer {
                        ef_prepare_gray(pixels, Int32(width), Int32(height), stride, 0, $0.baseAddress, width)
                    }
                    guard status == EF_OK.rawValue else { throw TrackingError.grayscale }
                    let box = selection.rect
                    let x = Int(box.x), y = Int(box.y)
                    let points = try predictor.predict(grayscale: grayPixels, width: width, height: height,
                        rectangle: .init(left: x, top: y, right: x + Int(box.width), bottom: y + Int(box.height)))
                    guard let refined = EyeGeometry(points: points) else { throw TrackingError.invalidModel }
                    geometry = refined
                } else {
                    // Shipped Model 0x100140a50..0x100140aa0 reacquires with
                    // CNN coarse eyes, then reuses them until the fourth frame.
                    geometry = EyeGeometry(
                        left: .init(center: CGPoint(x: Double(selection.leftEyeX), y: Double(selection.leftEyeY)), width: Double(selection.eyeWidth)),
                        right: .init(center: CGPoint(x: Double(selection.rightEyeX), y: Double(selection.rightEyeY)), width: Double(selection.eyeWidth)))
                }
                let left = EFEye(center_x: geometry.left.center.x, center_y: geometry.left.center.y, width: geometry.left.width)
                let right = EFEye(center_x: geometry.right.center.x, center_y: geometry.right.center.y, width: geometry.right.width)
                currentEyes = (left, right, Double(geometry.normalizer))
            } else { previousFace = nil }
        }
        frameIndex += 1
        return currentEyes
    }

    enum TrackingError: LocalizedError {
        case faceModel(String), grayscale, invalidModel
        var errorDescription: String? {
            switch self {
            case .faceModel(let message): return message
            case .grayscale: return "图像格式转换失败。"
            case .invalidModel: return "检测模型与已确认的原版基线不一致。"
            }
        }
    }
}
