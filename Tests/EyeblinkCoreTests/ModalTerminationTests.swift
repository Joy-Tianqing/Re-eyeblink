import XCTest
import CoreFoundation
@testable import EyeblinkCore

@MainActor
private final class ModalCompletion {
    var finished = false
    var waiting = true
}

@MainActor
final class ModalTerminationTests: XCTestCase {
    private func runModal(_ mode: RunLoop.Mode) {
        CFRunLoopRunInMode(CFRunLoopMode(rawValue: mode.rawValue as CFString), 3, false)
    }
    func testPendingWriteCanDrainWhileAppKitRunsItsTerminationModalLoop() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("history.json")
        let store = try HistoryStore(fileURL: file)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        let record = MeasurementRecord(date: Date(), validDuration: 180, blinkDurations: [0.2])
        XCTAssertTrue(coordinator.bind(record.id))
        XCTAssertNotNil(coordinator.save(record))
        let closed = coordinator.close()
        let flag = ModalCompletion()
        let mode = RunLoop.Mode(rawValue: "NSModalPanelRunLoopMode")
        Task.detached {
            await closed.value
            RunLoop.main.perform(inModes: [mode]) {
                MainActor.assumeIsolated {
                    flag.finished = true
                    if flag.waiting { CFRunLoopStop(CFRunLoopGetMain()) }
                }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        // A real nested modal run loop, with no dispatch-main/task pumping.
        let keepAlive = Timer(timeInterval: 3, repeats: false) { _ in }
        RunLoop.main.add(keepAlive, forMode: mode)
        runModal(mode)
        flag.waiting = false
        keepAlive.invalidate()
        XCTAssertTrue(flag.finished, "History close must complete inside the termination modal loop")
        await closed.value
        let disk = try JSONDecoder().decode([MeasurementRecord].self, from: Data(contentsOf: file))
        XCTAssertEqual(disk.map(\.id), [record.id])
    }
}
