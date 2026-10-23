import XCTest
@testable import EyeblinkCore

final class FrameRateMonitorTests: XCTestCase {
    func testMatchesActualShippedFPSGateRingAndDivisionOrder() throws {
        struct Reference: Decodable {
            let originalSHA256: String
            let cases: [Case]
            struct Case: Decodable { let id: String; let frameCounter: Int; let deltas: [Double]; let fps: Int? }
        }
        let url = try XCTUnwrap(Bundle.module.url(forResource: "OriginalFPSWindow", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: url))
        XCTAssertEqual(reference.originalSHA256, "bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db")
        XCTAssertEqual(reference.cases.count, 18)
        for fixture in reference.cases {
            var monitor = FrameRateMonitor()
            var time: Double = 0
            _ = monitor.observe(at: time) // The separate pre-read clock baseline.
            let prefix = max(0, fixture.frameCounter - 31)
            var result: Int?
            for index in 0..<fixture.frameCounter {
                let delta: Double
                if index < prefix { delta = 1.0 / 32 }
                else { delta = fixture.deltas[index - prefix + max(0, 31-fixture.frameCounter)] }
                time += delta
                result = monitor.observe(at: time, frameInterval: delta)
            }
            XCTAssertEqual(result, fixture.fps, fixture.id)
        }
    }
    func testAuthoritativeFrameIntervalControlsRate() {
        var monitor = FrameRateMonitor()
        XCTAssertNil(monitor.observe(at: 0))
        for frame in 1..<31 { XCTAssertNil(monitor.observe(at: Double(frame) * 0.2, frameInterval: 0.125)) }
        XCTAssertEqual(monitor.observe(at: 6.2, frameInterval: 0.125), 8)
    }
    func testChecks31DeltaWindowAndTruncatesNinePointNine() {
        var monitor = FrameRateMonitor()
        XCTAssertNil(monitor.observe(at: 0))
        for frame in 1..<31 { XCTAssertNil(monitor.observe(at: Double(frame) / 9.9)) }
        XCTAssertEqual(monitor.observe(at: 31 / 9.9), 9)
        for frame in 32..<62 { XCTAssertNil(monitor.observe(at: 31 / 9.9 + Double(frame - 31) / 30.25)) }
        XCTAssertEqual(monitor.observe(at: 31 / 9.9 + 31 / 30.25), 30)
    }
    func testResetAndInvalidTimestampsDoNotContaminateNewLease() {
        var monitor = FrameRateMonitor()
        _ = monitor.observe(at: 1)
        for _ in 0..<40 { XCTAssertNil(monitor.observe(at: .nan)); XCTAssertNil(monitor.observe(at: 0)) }
        monitor.reset()
        for frame in 0..<31 { XCTAssertNil(monitor.observe(at: Double(frame) / 8)) }
        XCTAssertEqual(monitor.observe(at: 31 / 8.0), 8)
    }
}
