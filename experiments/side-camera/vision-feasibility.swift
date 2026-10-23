// Offline API/performance feasibility probe only. No camera, UI, or app data.
import Foundation
import CoreGraphics
import ImageIO
import Vision
import CryptoKit

enum ProbeError: Error { case usage, invalidInput, image }

func main() throws {
    guard (CommandLine.arguments.count == 5 || (CommandLine.arguments.count == 6 && CommandLine.arguments[5] == "--explicit-pose")),
          let width = Int(CommandLine.arguments[2]), width > 0, width <= 4096,
          let height = Int(CommandLine.arguments[3]), height > 0, height <= 4096,
          let iterations = Int(CommandLine.arguments[4]), (1...100).contains(iterations) else { throw ProbeError.usage }
    let serialized = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    guard serialized.count == 8 + width * height * 3 else { throw ProbeError.invalidInput }
    let dimensions = serialized.withUnsafeBytes { raw in
        (Int(Int32(littleEndian: raw.loadUnaligned(as: Int32.self))),
         Int(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 4, as: Int32.self))))
    }
    guard dimensions.0 == width, dimensions.1 == height else { throw ProbeError.invalidInput }
    let data = Data(serialized.dropFirst(8))
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    data.withUnsafeBytes { raw in
        let pixels = raw.bindMemory(to: UInt8.self)
        for i in 0..<(width * height) {
            rgba[i * 4] = pixels[i * 3 + 2]
            rgba[i * 4 + 1] = pixels[i * 3 + 1]
            rgba[i * 4 + 2] = pixels[i * 3]
        }
    }
    guard let provider = CGDataProvider(data: Data(rgba) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw ProbeError.image }
    let request = VNDetectFaceLandmarksRequest()
    request.revision = VNDetectFaceLandmarksRequestRevision3
    request.constellation = .constellation76Points
    let explicitPose = CommandLine.arguments.count == 6
    let rectangles = VNDetectFaceRectanglesRequest()
    rectangles.revision = VNDetectFaceRectanglesRequestRevision3
    var durations: [Double] = []
    var observations: [[String: Any]] = []
    var coldMilliseconds = 0.0
    for index in 0...iterations {
        try autoreleasepool {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            let started = ProcessInfo.processInfo.systemUptime
            if explicitPose {
                try handler.perform([rectangles])
                request.inputFaceObservations = rectangles.results ?? []
            }
            try handler.perform([request])
            let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000
            if index == 0 { coldMilliseconds = elapsed } else { durations.append(elapsed) }
            observations = (request.results ?? []).map { face in
                func eye(_ region: VNFaceLandmarkRegion2D?) -> [String: Any] {
                    let precision = region?.precisionEstimatesPerPoint?.map(Double.init) ?? []
                    return ["points": region?.pointCount ?? 0,
                            "precisionEstimateCount": precision.count,
                            "precisionEstimateMinimum": precision.min().map { $0 as Any } ?? NSNull(),
                            "precisionEstimateMaximum": precision.max().map { $0 as Any } ?? NSNull()]
                }
                func degrees(_ angle: NSNumber?) -> Any { angle.map { $0.doubleValue * 180 / .pi } ?? NSNull() }
                return ["confidence": face.confidence,
                        "landmarksConfidence": face.landmarks?.confidence as Any? ?? NSNull(),
                        "landmarkCount": face.landmarks?.allPoints?.pointCount ?? 0,
                        "yawDegrees": degrees(face.yaw), "rollDegrees": degrees(face.roll), "pitchDegrees": degrees(face.pitch),
                        "leftEye": eye(face.landmarks?.leftEye), "rightEye": eye(face.landmarks?.rightEye)]
            }
        }
    }
    durations.sort()
    let p95 = durations[min(durations.count - 1, Int(ceil(Double(durations.count) * 0.95)) - 1)]
    let report: [String: Any] = [
        "scope": "Single frozen public BGR crop; Vision API/metadata/static-image request timing only. Not side-pose accuracy, blink detection, camera FPS or energy acceptance.",
        "inputSHA256": SHA256.hash(data: serialized).map { String(format: "%02x", $0) }.joined(),
        "inputFormat": "int32le width/height header, then packed BGR pixels",
        "explicitPoseRequest": explicitPose,
        "faceRectangleRevision": explicitPose ? rectangles.revision as Any : NSNull(),
        "width": width, "height": height, "requestRevision": request.revision, "constellation": 76,
        "warmIterations": iterations, "coldRequestMilliseconds": coldMilliseconds,
        "warmMedianMilliseconds": durations[durations.count / 2], "warmP95Milliseconds": p95,
        "faces": observations, "cameraAccessed": false, "userDataAccessed": false,
        "limitations": ["An available landmark/pose is not proof of correctness or visibility",
                         "Precision estimates are placement estimates, not calibrated eye-visibility probabilities",
                         "One public crop and repeated static request timing do not establish 15–30 degree performance",
                         "macOS 14 deployment target typechecked, but not executed on a macOS 14 machine"]]
    let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(encoded)
    FileHandle.standardOutput.write(Data([10]))
}

do { try main() }
catch {
    FileHandle.standardError.write(Data("Probe failed: \(error)\nUsage: probe INPUT.bgr WIDTH HEIGHT ITERATIONS [--explicit-pose]\n".utf8))
    exit(1)
}
