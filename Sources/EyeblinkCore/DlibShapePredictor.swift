import Foundation
import CryptoKit

/// Inclusive integer rectangle used by dlib, in top-left-origin image pixels.
/// The original controller passes right = x + width, bottom = y + height.
public struct DlibFaceRectangle: Equatable, Sendable {
    public var left: Int
    public var top: Int
    public var right: Int
    public var bottom: Int
    public init(left: Int, top: Int, right: Int, bottom: Int) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }
}

public enum DlibPredictorError: Error, Equatable {
    case invalidModel(String)
    case invalidImage
    case invalidRectangle
}

/// Portable dlib shape_predictor-v1 reader and CPU predictor. No Intel library is loaded.
/// Mathematics follows dlib's shape_predictor.h and find_similarity_transform:
/// https://github.com/davisking/dlib/tree/v19.24.6/dlib
/// See docs/recovered-rules.md for the original artifact identity and parity limits.
public struct DlibShapePredictor: Sendable {
    public struct Metadata: Equatable, Sendable {
        public let sha256: String
        public let landmarkCount: Int
        public let stageCount: Int
        public let treeCount: Int
        public let byteCount: Int
    }
    private struct Split: Sendable { let first: Int; let second: Int; let threshold: Float }
    private struct Tree: Sendable { let splits: [Split]; let leaves: [Float]; let leafCount: Int }
    private struct Stage: Sendable { let trees: [Tree]; let anchors: [Int]; let deltas: [SIMD2<Float>] }
    public let metadata: Metadata
    private let initialShape: [Float]
    private let stages: [Stage]

    public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }
    public init(data: Data) throws {
        var reader = Reader(bytes: Array(data))
        guard try reader.integer() == 1 else { throw DlibPredictorError.invalidModel("Expected shape_predictor version 1") }
        let initial = try reader.matrix(maximumElements: 1024)
        guard initial.columns == 1, initial.values.count >= 4, initial.values.count.isMultiple(of: 2) else {
            throw DlibPredictorError.invalidModel("Invalid initial shape")
        }
        let landmarkCount = initial.values.count / 2
        let stageCount = try reader.count(maximum: 128)
        guard stageCount > 0 else { throw DlibPredictorError.invalidModel("No regression stages") }
        var forests: [[Tree]] = []; forests.reserveCapacity(stageCount)
        var totalTrees = 0
        for _ in 0..<stageCount {
            let count = try reader.count(maximum: 10_000)
            guard count > 0 else { throw DlibPredictorError.invalidModel("Empty regression stage") }
            totalTrees += count
            var trees: [Tree] = []; trees.reserveCapacity(count)
            for _ in 0..<count {
                let splitCount = try reader.count(maximum: 65_535)
                var splits: [Split] = []; splits.reserveCapacity(splitCount)
                for _ in 0..<splitCount {
                    let first = try reader.count(maximum: 1_000_000)
                    let second = try reader.count(maximum: 1_000_000)
                    splits.append(Split(first: first, second: second, threshold: try reader.floating()))
                }
                let leafCount = try reader.count(maximum: 65_536)
                guard leafCount == splitCount + 1, leafCount.nonzeroBitCount == 1 else {
                    throw DlibPredictorError.invalidModel("Regression tree must be complete")
                }
                var leaves: [Float] = []; leaves.reserveCapacity(leafCount * initial.values.count)
                for _ in 0..<leafCount {
                    let matrix = try reader.matrix(maximumElements: 1024)
                    guard matrix.rows == initial.rows, matrix.columns == initial.columns else {
                        throw DlibPredictorError.invalidModel("Leaf shape differs from initial shape")
                    }
                    leaves.append(contentsOf: matrix.values)
                }
                trees.append(Tree(splits: splits, leaves: leaves, leafCount: leafCount))
            }
            forests.append(trees)
        }
        guard try reader.count(maximum: 128) == stageCount else { throw DlibPredictorError.invalidModel("Anchor stage count mismatch") }
        var anchors: [[Int]] = []; anchors.reserveCapacity(stageCount)
        for _ in 0..<stageCount {
            let count = try reader.count(maximum: 1_000_000)
            guard count > 0 else { throw DlibPredictorError.invalidModel("Empty anchor stage") }
            var values: [Int] = []; values.reserveCapacity(count)
            for _ in 0..<count { values.append(try reader.count(maximum: landmarkCount - 1)) }
            anchors.append(values)
        }
        guard try reader.count(maximum: 128) == stageCount else { throw DlibPredictorError.invalidModel("Delta stage count mismatch") }
        var decodedStages: [Stage] = []; decodedStages.reserveCapacity(stageCount)
        for index in 0..<stageCount {
            let count = try reader.count(maximum: 1_000_000)
            guard count == anchors[index].count else { throw DlibPredictorError.invalidModel("Anchor/delta size mismatch") }
            var deltas: [SIMD2<Float>] = []; deltas.reserveCapacity(count)
            for _ in 0..<count { deltas.append(SIMD2(try reader.floating(), try reader.floating())) }
            for tree in forests[index] {
                guard tree.splits.allSatisfy({ $0.first < count && $0.second < count }) else {
                    throw DlibPredictorError.invalidModel("Split references missing feature pixel")
                }
            }
            decodedStages.append(Stage(trees: forests[index], anchors: anchors[index], deltas: deltas))
        }
        guard reader.offset == data.count else { throw DlibPredictorError.invalidModel("Trailing bytes after shape predictor") }
        initialShape = initial.values
        stages = decodedStages
        metadata = Metadata(sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                            landmarkCount: landmarkCount, stageCount: stageCount, treeCount: totalTrees, byteCount: data.count)
    }

    /// Gray pixels are UInt8 intensity (no blur here); dlib performs nearest-pixel
    /// sampling and substitutes zero for coordinates outside the image.
    public func predict(grayscale: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil,
                        rectangle: DlibFaceRectangle) throws -> [CGPoint] {
        try grayscale.withUnsafeBufferPointer {
            try predict(pixels: $0, width: width, height: height, bytesPerRow: bytesPerRow ?? width, rectangle: rectangle)
        }
    }

    public func predict(pixels: UnsafeBufferPointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                        rectangle: DlibFaceRectangle) throws -> [CGPoint] {
        guard width > 0, height > 0, bytesPerRow >= width,
              height <= Int.max / bytesPerRow, pixels.count >= height * bytesPerRow else { throw DlibPredictorError.invalidImage }
        guard rectangle.right >= rectangle.left, rectangle.bottom >= rectangle.top,
              [rectangle.left, rectangle.top, rectangle.right, rectangle.bottom].allSatisfy({ abs(Double($0)) < 1e9 }) else {
            throw DlibPredictorError.invalidRectangle
        }
        var shape = initialShape
        let scaleX = Double(rectangle.right - rectangle.left), scaleY = Double(rectangle.bottom - rectangle.top)
        for stage in stages {
            let transform = similarityLinear(from: initialShape, to: shape)
            var features: [Float] = []; features.reserveCapacity(stage.anchors.count)
            for index in stage.anchors.indices {
                let delta = stage.deltas[index], anchor = 2 * stage.anchors[index]
                // dlib casts the 2x2 similarity matrix to Float before transforming deltas.
                let x = (transform.x * delta.x - transform.y * delta.y) + shape[anchor]
                let y = (transform.y * delta.x + transform.x * delta.y) + shape[anchor + 1]
                let imageX = Double(x) * scaleX + Double(rectangle.left)
                let imageY = Double(y) * scaleY + Double(rectangle.top)
                let px = Int(floor(imageX + 0.5)), py = Int(floor(imageY + 0.5))
                features.append(px >= 0 && px < width && py >= 0 && py < height ? Float(pixels[py * bytesPerRow + px]) : 0)
            }
            for tree in stage.trees {
                var node = 0
                while node < tree.splits.count {
                    let split = tree.splits[node]
                    node = 2 * node + (features[split.first] - features[split.second] > split.threshold ? 1 : 2)
                }
                let leaf = node - tree.splits.count
                let base = leaf * shape.count
                for index in shape.indices { shape[index] += tree.leaves[base + index] }
            }
        }
        return stride(from: 0, to: shape.count, by: 2).map {
            CGPoint(x: floor(Double(shape[$0]) * scaleX + Double(rectangle.left) + 0.5),
                    y: floor(Double(shape[$0 + 1]) * scaleY + Double(rectangle.top) + 0.5))
        }
    }

    /// Closed-form 2D rotation/scale least squares, equivalent mathematically to
    /// dlib's proper-rotation Umeyama solution. Floating-point/SVD boundary parity
    /// must be checked with a fixed-image reference; it is not bitwise guaranteed.
    private func similarityLinear(from: [Float], to: [Float]) -> SIMD2<Float> {
        let count = from.count / 2
        var fromMean = SIMD2<Double>.zero, toMean = SIMD2<Double>.zero
        for index in 0..<count {
            fromMean += SIMD2(Double(from[2 * index]), Double(from[2 * index + 1]))
            toMean += SIMD2(Double(to[2 * index]), Double(to[2 * index + 1]))
        }
        fromMean /= Double(count); toMean /= Double(count)
        var variance = 0.0, dot = 0.0, cross = 0.0
        for index in 0..<count {
            let p = SIMD2(Double(from[2 * index]), Double(from[2 * index + 1])) - fromMean
            let q = SIMD2(Double(to[2 * index]), Double(to[2 * index + 1])) - toMean
            variance += p.x * p.x + p.y * p.y
            dot += q.x * p.x + q.y * p.y
            cross += q.y * p.x - q.x * p.y
        }
        guard variance != 0 else { return SIMD2(1, 0) }
        return SIMD2(Float(dot / variance), Float(cross / variance))
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0
        mutating func integer() throws -> Int64 {
            guard offset < bytes.count else { throw DlibPredictorError.invalidModel("Truncated integer") }
            let control = bytes[offset]; offset += 1
            let count = Int(control & 15)
            guard control & 0x70 == 0, count > 0, count <= 8, offset <= bytes.count - count else {
                throw DlibPredictorError.invalidModel("Invalid integer encoding")
            }
            var value: UInt64 = 0
            for index in 0..<count { value |= UInt64(bytes[offset + index]) << (8 * index) }
            offset += count
            guard value <= UInt64(Int64.max) else { throw DlibPredictorError.invalidModel("Integer overflow") }
            let magnitude = Int64(value)
            return control & 128 == 0 ? magnitude : -magnitude
        }
        mutating func count(maximum: Int) throws -> Int {
            let value = try integer()
            guard value >= 0, value <= maximum else { throw DlibPredictorError.invalidModel("Collection count out of bounds") }
            return Int(value)
        }
        mutating func floating() throws -> Float {
            let mantissa = try integer(), exponent = try integer()
            guard abs(exponent) < 1024 else { throw DlibPredictorError.invalidModel("Invalid floating exponent") }
            let value = Float(Double(mantissa) * pow(2, Double(exponent)))
            guard value.isFinite else { throw DlibPredictorError.invalidModel("Non-finite model coefficient") }
            return value
        }
        mutating func matrix(maximumElements: Int) throws -> (rows: Int, columns: Int, values: [Float]) {
            let storedRows = try integer(), storedColumns = try integer()
            guard storedRows <= 0, storedColumns <= 0,
                  storedRows >= -Int64(maximumElements), storedColumns >= -Int64(maximumElements) else {
                throw DlibPredictorError.invalidModel("Unsupported matrix dimensions")
            }
            let rows = Int(-storedRows), columns = Int(-storedColumns)
            guard rows * columns <= maximumElements else { throw DlibPredictorError.invalidModel("Matrix too large") }
            var values: [Float] = []; values.reserveCapacity(rows * columns)
            for _ in 0..<(rows * columns) { values.append(try floating()) }
            return (rows, columns, values)
        }
    }
}
