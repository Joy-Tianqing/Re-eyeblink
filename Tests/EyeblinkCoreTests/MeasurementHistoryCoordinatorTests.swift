import XCTest
@testable import EyeblinkCore

private actor HistoryGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters; waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

/// Pauses actual store boundaries without sleeps or changing the production
/// scheduler. A captured snapshot can deliberately arrive after a newer clear.
private actor ControlledHistory: MeasurementHistory {
    let base: HistoryStore
    let snapshotEntered = HistoryGate(), snapshotRelease = HistoryGate()
    let appendEntered = HistoryGate(), appendRelease = HistoryGate()
    let clearEntered = HistoryGate(), clearRelease = HistoryGate()
    private let heldRead: Int?
    private let holdsAppend: Bool
    private let holdsClear: Bool
    private let failsClear: Bool
    private var reads = 0
    init(base: HistoryStore, heldRead: Int? = nil, holdsAppend: Bool = false, holdsClear: Bool = false, failsClear: Bool = false) {
        self.base = base; self.heldRead = heldRead; self.holdsAppend = holdsAppend
        self.holdsClear = holdsClear; self.failsClear = failsClear
    }
    func snapshotState() async -> HistorySnapshot {
        reads += 1
        let hold = reads == heldRead
        let captured = await base.snapshotState()
        if hold { await snapshotEntered.open(); await snapshotRelease.wait() }
        return captured
    }
    func append(_ record: MeasurementRecord, expectedGeneration: UInt64) async throws -> Bool {
        if holdsAppend { await appendEntered.open(); await appendRelease.wait() }
        return try await base.append(record, expectedGeneration: expectedGeneration)
    }
    func clear(confirmed: Bool) async throws -> HistorySnapshot {
        if holdsClear { await clearEntered.open(); await clearRelease.wait() }
        if failsClear { throw CocoaError(.fileWriteNoPermission) }
        return try await base.clear(confirmed: confirmed)
    }
}

@MainActor
final class MeasurementHistoryCoordinatorTests: XCTestCase {
    private func record() -> MeasurementRecord {
        MeasurementRecord(date: Date(timeIntervalSince1970: 1_792_390_000), validDuration: 180, blinkDurations: [0.2], frequencyDuration: 180)
    }

    func testLateInitialReadCannotRestoreClearedRecords() async throws {
        let base = try HistoryStore()
        let old = record()
        _ = try await base.append(old, expectedGeneration: 0)
        let store = ControlledHistory(base: base, heldRead: 1)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        let loading = coordinator.load()
        await store.snapshotEntered.wait()
        await coordinator.clear()!.value
        XCTAssertEqual(coordinator.snapshot.generation, 1)
        await store.snapshotRelease.open()
        await loading.value
        XCTAssertTrue(coordinator.snapshot.records.isEmpty)
        XCTAssertEqual(coordinator.snapshot.revision, 2)
    }

    func testClearBlocksNewBindingsAndRejectsOldResultThenAcceptsNewMeasurement() async throws {
        let base = try HistoryStore()
        let store = ControlledHistory(base: base, holdsClear: true)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        await coordinator.load().value
        let old = record(), new = record()
        XCTAssertTrue(coordinator.bind(old.id))
        let clearing = coordinator.clear()!
        await store.clearEntered.wait()
        XCTAssertTrue(coordinator.isClearing)
        XCTAssertFalse(coordinator.bind(new.id))
        XCTAssertNil(coordinator.save(old))
        await store.clearRelease.open()
        await clearing.value
        XCTAssertFalse(coordinator.isClearing)
        XCTAssertTrue(coordinator.bind(new.id))
        await coordinator.save(new)!.value
        XCTAssertEqual(coordinator.snapshot.records.map(\.id), [new.id])
        XCTAssertEqual(coordinator.snapshot.generation, 1)
    }

    func testAppendSnapshotArrivingAfterClearCannotPublishOrNotifyDeletedMeasurement() async throws {
        let base = try HistoryStore()
        let store = ControlledHistory(base: base, heldRead: 2)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        var notifications: [UUID] = []
        coordinator.onSaved = { notifications.append($0.id) }
        await coordinator.load().value
        let measurement = record()
        coordinator.bind(measurement.id)
        let saving = coordinator.save(measurement)!
        await store.snapshotEntered.wait()
        await coordinator.clear()!.value
        await store.snapshotRelease.open()
        await saving.value
        XCTAssertTrue(coordinator.snapshot.records.isEmpty)
        XCTAssertTrue(notifications.isEmpty)
        XCTAssertEqual(coordinator.snapshot.generation, 1)
    }

    func testCloseWaitsForAcceptedWriteAndRefusesFurtherSubmissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("history.json")
        let base = try HistoryStore(fileURL: file)
        let store = ControlledHistory(base: base, holdsAppend: true)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        let measurement = record()
        coordinator.bind(measurement.id)
        _ = coordinator.save(measurement)
        await store.appendEntered.wait()
        let closing = coordinator.close()
        XCTAssertTrue(coordinator.isClosing)
        XCTAssertFalse(coordinator.bind(UUID()))
        XCTAssertNil(coordinator.clear())
        await store.appendRelease.open()
        await closing.value
        await coordinator.close().value
        let persisted = try JSONDecoder().decode([MeasurementRecord].self, from: Data(contentsOf: file))
        XCTAssertEqual(persisted.map(\.id), [measurement.id])
    }

    func testCloseAlsoWaitsForInFlightClear() async throws {
        let base = try HistoryStore()
        _ = try await base.append(record(), expectedGeneration: 0)
        let store = ControlledHistory(base: base, holdsClear: true)
        let coordinator = MeasurementHistoryCoordinator(store: store)
        await coordinator.load().value
        _ = coordinator.clear()
        await store.clearEntered.wait()
        let closing = coordinator.close()
        await store.clearRelease.open()
        await closing.value
        XCTAssertFalse(coordinator.isClearing)
        XCTAssertTrue(coordinator.snapshot.records.isEmpty)
        XCTAssertEqual(coordinator.snapshot.generation, 1)
    }

    func testFailedClearPreservesRecordsAndAllowsNewRecording() async throws {
        let base = try HistoryStore()
        let existing = record()
        _ = try await base.append(existing, expectedGeneration: 0)
        let coordinator = MeasurementHistoryCoordinator(store: ControlledHistory(base: base, failsClear: true))
        var errors = 0
        coordinator.onError = { _ in errors += 1 }
        await coordinator.load().value
        await coordinator.clear()!.value
        XCTAssertEqual(errors, 1)
        XCTAssertFalse(coordinator.isClearing)
        XCTAssertEqual(coordinator.snapshot.records.map(\.id), [existing.id])
        let next = record()
        XCTAssertTrue(coordinator.bind(next.id))
        await coordinator.save(next)!.value
        XCTAssertEqual(coordinator.snapshot.records.map(\.id), [existing.id, next.id])
    }
}
