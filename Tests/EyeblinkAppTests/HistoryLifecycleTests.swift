import XCTest
import Combine
import EyeblinkCore
@testable import EyeblinkApp

private actor LifecycleGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { opened = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}

private actor DelayedClearHistory: MeasurementHistory {
    let base: HistoryStore
    let entered = LifecycleGate(), release = LifecycleGate()
    init(base: HistoryStore) { self.base = base }
    func snapshotState() async -> HistorySnapshot { await base.snapshotState() }
    func append(_ record: MeasurementRecord, expectedGeneration: UInt64) async throws -> Bool {
        try await base.append(record, expectedGeneration: expectedGeneration)
    }
    func clear(confirmed: Bool) async throws -> HistorySnapshot {
        await entered.open(); await release.wait()
        return try await base.clear(confirmed: confirmed)
    }
}

@MainActor
final class HistoryLifecycleTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func record() -> MeasurementRecord { .init(date: Date(), validDuration: 180, blinkDurations: [0.2]) }

    func testClearCompletesThroughAppModelAndRestoresCameraPauseReasonOnlyAfterCommit() async throws {
        let root = try directory()
        let base = try HistoryStore(fileURL: root.appendingPathComponent("history.json"))
        let existing = record(); _ = try await base.append(existing, expectedGeneration: 0)
        let history = DelayedClearHistory(base: base)
        // No windows, timer, permissions, system observers, or camera enumeration.
        let model = AppModel(dataDirectory: root, historyStore: history, observesSystemEvents: false)
        let loaded = expectation(description: "stored record published")
        let loadObserver = model.$measurements.first(where: { $0.count == 1 }).sink { _ in loaded.fulfill() }
        await fulfillment(of: [loaded], timeout: 2)
        let finished = expectation(description: "clear transaction finished")
        let clearObserver = model.$isClearingMeasurements.dropFirst().first(where: { !$0 }).sink { _ in finished.fulfill() }
        model.clearMeasurements()
        await history.entered.wait()
        XCTAssertTrue(model.isClearingMeasurements)
        XCTAssertTrue(model.engine.state.cameraPauseReasons.contains(.custom("clearing-history")))
        XCTAssertEqual(model.measurements.map(\.id), [existing.id])
        await history.release.open()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(model.measurements.isEmpty)
        XCTAssertFalse(model.engine.state.cameraPauseReasons.contains(.custom("clearing-history")))
        XCTAssertNil(model.latestBlinkRate)
        await model.shutdown()
        withExtendedLifetime([loadObserver, clearObserver]) {}
    }

    func testShutdownDrainsClearAndLateCompletionCannotResumeCamera() async throws {
        let root = try directory()
        let file = root.appendingPathComponent("history.json")
        let base = try HistoryStore(fileURL: file)
        _ = try await base.append(record(), expectedGeneration: 0)
        let history = DelayedClearHistory(base: base)
        let model = AppModel(dataDirectory: root, historyStore: history, observesSystemEvents: false)
        model.clearMeasurements()
        await history.entered.wait()
        let stopping = expectation(description: "shutdown froze commands")
        let observer = model.$isShuttingDown.first(where: { $0 }).sink { _ in stopping.fulfill() }
        let shutdown = Task { await model.shutdown() }
        await fulfillment(of: [stopping], timeout: 2)
        XCTAssertTrue(model.isShuttingDown)
        await history.release.open()
        await shutdown.value
        XCTAssertTrue(model.measurements.isEmpty)
        XCTAssertFalse(model.isClearingMeasurements)
        XCTAssertTrue(model.engine.state.cameraPauseReasons.contains(.custom("clearing-history")))
        let persisted = try JSONDecoder().decode([MeasurementRecord].self, from: Data(contentsOf: file))
        XCTAssertTrue(persisted.isEmpty)
        withExtendedLifetime(observer) {}
    }
}
