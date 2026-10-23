import Foundation

/// Owns the MainActor side of history transactions. Store revisions prevent an
/// older async read from republishing records after a clear or a newer append.
@MainActor
public final class MeasurementHistoryCoordinator {
    public private(set) var snapshot = HistorySnapshot(records: [], generation: 0, revision: 0)
    public private(set) var isClearing = false
    public private(set) var isClosing = false
    public var onChange: (() -> Void)?
    public var onSaved: ((MeasurementRecord) -> Void)?
    public var onError: ((Error) -> Void)?
    private let store: any MeasurementHistory
    private var bindings: [UUID: UInt64] = [:]
    private var operations: [UUID: Task<Void, Never>] = [:]
    private var closingTask: Task<Void, Never>?

    public init(store: any MeasurementHistory) { self.store = store }

    @discardableResult public func load() -> Task<Void, Never> {
        if let closingTask { return closingTask }
        return enqueue(work: { [store] in await store.snapshotState() }, apply: { [self] in publish($0) })
    }

    @discardableResult public func bind(_ id: UUID) -> Bool {
        guard !isClearing, !isClosing else { return false }
        if bindings[id] == nil { bindings[id] = snapshot.generation }
        return true
    }

    public func cancel(_ id: UUID) { bindings.removeValue(forKey: id) }

    @discardableResult public func save(_ record: MeasurementRecord) -> Task<Void, Never>? {
        guard !isClosing, let generation = bindings.removeValue(forKey: record.id) else { return nil }
        return enqueue(work: { [store] in
            do {
                guard try await store.append(record, expectedGeneration: generation) else { return Result<HistorySnapshot?, Error>.success(nil) }
                return .success(await store.snapshotState())
            } catch { return .failure(error) }
        }, apply: { [self] result in
            switch result {
            case .success(let saved?):
                publish(saved)
                if !isClearing, snapshot.generation == generation, snapshot.records.contains(where: { $0.id == record.id }) {
                    onSaved?(record)
                }
            case .success(nil): break
            case .failure(let error): onError?(error)
            }
        })
    }

    @discardableResult public func clear() -> Task<Void, Never>? {
        guard !isClearing, !isClosing else { return nil }
        isClearing = true
        bindings.removeAll()
        onChange?()
        return enqueue(work: { [store] in
            do { return Result<HistorySnapshot, Error>.success(try await store.clear(confirmed: true)) }
            catch { return .failure(error) }
        }, apply: { [self] result in
            defer { isClearing = false; onChange?() }
            switch result {
            case .success(let saved): publish(saved)
            case .failure(let error): onError?(error)
            }
        })
    }

    /// Freeze submissions synchronously before waiting. Includes an in-flight
    /// clear, not just completed measurement writes, and is safe to call twice.
    public func close() -> Task<Void, Never> {
        if let closingTask { return closingTask }
        isClosing = true
        bindings.removeAll()
        let pending = Array(operations.values)
        let task = Task.detached { for operation in pending { await operation.value } }
        closingTask = task
        onChange?()
        return task
    }

    private func publish(_ value: HistorySnapshot) {
        guard value.revision >= snapshot.revision else { return }
        snapshot = value
        onChange?()
    }

    private func enqueue<Value: Sendable>(work: @escaping @Sendable () async -> Value, apply: @escaping @MainActor (Value) -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task.detached { [self] in
            let value = await work()
            await withCheckedContinuation { continuation in
                MainRunLoopDelivery.perform {
                    apply(value)
                    self.operations.removeValue(forKey: id)
                    continuation.resume()
                }
            }
        }
        operations[id] = task
        return task
    }
}
