import Foundation
import CoreGraphics

/// The shipped Model::detectEyes geometry at its fixed 2.0 eye scale.
/// Keep the caller's scalar SSE/Float normalizer, including its subtraction.
public struct EyeGeometry: Sendable {
    public struct Eye: Equatable, Sendable {
        public let center: CGPoint
        public let width: Double

        public init(center: CGPoint, width: Double) {
            self.center = center; self.width = width
        }
    }
    public let left: Eye
    public let right: Eye
    public let normalizer: Float

    public init?(points: [CGPoint]) {
        guard points.count == 5 else { return nil }
        func eye(_ a: CGPoint, _ b: CGPoint) -> Eye {
            let dx = a.x - b.x, dy = a.y - b.y
            // Original: sqrt(integer dx² + dy²), round, then scale by 2.
            let width = 2 * sqrt(dx * dx + dy * dy).rounded()
            let x = Float(a.x + b.x) * 0.5, y = Float(a.y + b.y) * 0.5
            return Eye(center: CGPoint(x: Double(x), y: Double(y)), width: width)
        }
        self.init(left: eye(points[0], points[1]), right: eye(points[2], points[3]))
    }

    /// CNN coarse eyes and dlib-refined eyes share the original denominator.
    public init(left: Eye, right: Eye) {
        self.left = left; self.right = right
        let dx = Float(left.center.x) - Float(right.center.x)
        let dy = Float(left.center.y) - Float(right.center.y)
        let squaredX = dx * dx, squaredY = dy * dy
        let distance = (squaredX - squaredY).squareRoot()
        // '< 1' deliberately preserves NaN, as the original flow denominator does.
        normalizer = distance < 1 ? 1 : distance
    }
}
