import XCTest
import Foundation
import CEyeFlow
import EyeblinkCore

final class NativeFrameClockTests: XCTestCase {
    func testNativeClockSharesSchedulerUptimeDomain() {
        let before = ProcessInfo.processInfo.systemUptime
        let raw = ef_clock_stamp()
        let after = ProcessInfo.processInfo.systemUptime
        let stamp = FrameTimestamp(ticks: raw.ticks, frequency: raw.frequency)
        XCTAssertTrue(stamp.isValid)
        // This is an OS clock-domain containment check. Exact integer-delta
        // parity is independently checked against shipped values, without tolerance.
        let rounding = max(1 / stamp.frequency, stamp.uptime.ulp * 4)
        XCTAssertGreaterThanOrEqual(stamp.uptime, before - rounding)
        XCTAssertLessThanOrEqual(stamp.uptime, after + rounding)
    }
}
