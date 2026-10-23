import XCTest
@testable import EyeblinkCore

final class EyeGeometryTests: XCTestCase {
    private struct Reference: Decodable {
        let cases: [Fixture]
        struct Fixture: Decodable {
            let fixture: Int
            let points: [[Double]]
            let leftEye: [Double]
            let rightEye: [Double]
        }
    }
    func testMatchesEightShippedDetectEyesFunctionResults() throws {
        let url = Bundle.module.url(forResource: "OriginalEyeGeometry", withExtension: "json", subdirectory: "Fixtures")!
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.cases.count, 8)
        for fixture in reference.cases {
            let geometry = try XCTUnwrap(EyeGeometry(points: fixture.points.map { CGPoint(x: $0[0], y: $0[1]) }))
            XCTAssertEqual([geometry.left.center.x, geometry.left.center.y, geometry.left.width], fixture.leftEye, "fixture \(fixture.fixture)")
            XCTAssertEqual([geometry.right.center.x, geometry.right.center.y, geometry.right.width], fixture.rightEye, "fixture \(fixture.fixture)")
        }
    }
    func testNormalizerKeepsOriginalSubtractionAndDegenerateSemantics() throws {
        // dx=5, dy=3 -> sqrt(25 - 9)=4; Euclidean distance would differ.
        let valid = try XCTUnwrap(EyeGeometry(points: [.init(x: 0, y: 0), .init(x: 2, y: 0), .init(x: 5, y: 3), .init(x: 7, y: 3), .zero]))
        XCTAssertEqual(valid.normalizer, 4)
        let coincident = try XCTUnwrap(EyeGeometry(points: Array(repeating: .zero, count: 5)))
        XCTAssertEqual(coincident.normalizer, 1)
        let tilted = try XCTUnwrap(EyeGeometry(points: [.zero, .zero, .init(x: 1, y: 3), .init(x: 1, y: 3), .zero]))
        XCTAssertTrue(tilted.normalizer.isNaN)
        // SSE computes each Float square before subtraction; an FMA changes this boundary.
        let precision = try XCTUnwrap(EyeGeometry(points: [.init(x: 10000, y: 0), .init(x: 10001, y: 0), .init(x: 0, y: 10000), .init(x: 0, y: 10000), .zero]))
        XCTAssertEqual(precision.normalizer, 100)
        XCTAssertNil(EyeGeometry(points: [.zero]))
    }
}
