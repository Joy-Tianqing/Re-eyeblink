import Foundation

public struct MeasurementRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var validDuration: TimeInterval
    public var blinkDurations: [TimeInterval]
    public var frequencyDuration: TimeInterval?
    public var detection: MeasurementDetection?
    public var isEstimated: Bool { detection?.isMonocularEstimate == true }
    public var blinksPerMinute: Double {
        let duration = frequencyDuration ?? validDuration
        guard duration > 0 else { return 0 }
        if frequencyDuration != nil {
            // Original measurementSuccessful(float,int): divide count by three
            // minutes in Double, then cvtsd2ss before emitting/storing frequency.
            return Double(Float(Double(blinkDurations.count) / (duration / 60)))
        }
        return Double(blinkDurations.count) * 60 / duration
    }
    public var timestamp: Date { date }
    public var bpm: Double { blinksPerMinute }
    public var averageBlinkDuration: Double? { averageBlinkDurationMilliseconds }
    public var averageBlinkDurationMilliseconds: Double? {
        guard !blinkDurations.isEmpty else { return 0 }
        // Preserve divsd then mulsd before truncation. Reordering can turn the
        // original 99ms into 100ms for durations [0.09, 0.09, 0.12].
        let milliseconds = blinkDurations.reduce(0, +) / Double(blinkDurations.count) * 1000
        return milliseconds.isFinite ? milliseconds.rounded(.towardZero) : nil
    }
    public init(id: UUID = UUID(), date: Date, validDuration: TimeInterval, blinkDurations: [TimeInterval], frequencyDuration: TimeInterval? = nil, detection: MeasurementDetection? = nil) {
        self.id = id; self.date = date; self.validDuration = validDuration; self.blinkDurations = blinkDurations; self.frequencyDuration = frequencyDuration
        self.detection = detection
    }
}

public struct MeasurementSession: Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public var validDuration: TimeInterval = 0
    public var blinkDurations: [TimeInterval] = []
    public var targetDuration: TimeInterval
    public var elapsedDuration: TimeInterval = 0
    public var timing: MeasurementTiming = .validSamples
    var startedAt: TimeInterval = 0
    var previousSample: TimeInterval?
    var previousValid = false
    public var progress: Double { min(1, (timing == .originalElapsedTime ? elapsedDuration : validDuration) / targetDuration) }
    public init(date: Date, targetDuration: TimeInterval) { id = UUID(); self.date = date; self.targetDuration = max(0.001, targetDuration) }

    /// Time counts only between consecutive valid samples. Gaps never imply face presence.
    mutating func sample(at time: TimeInterval, valid: Bool, blinks: [TimeInterval], maximumGap: TimeInterval = 0.5) {
        guard time.isFinite else { return }
        if let previousSample, time <= previousSample { return }
        if let previousSample, previousValid, valid, time - previousSample <= maximumGap {
            validDuration = min(targetDuration, validDuration + time - previousSample)
            blinkDurations.append(contentsOf: blinks.filter { $0.isFinite && $0 > 0 })
        }
        previousSample = time; previousValid = valid
    }
}

public struct StatisticsSummary: Equatable, Sendable {
    public var count: Int
    public var meanBPM: Double?
    public var meanBlinkDurationMilliseconds: Double?
    public var weightedBPM: Double?
    public init(records: [MeasurementRecord]) {
        let records = records.filter { !$0.isEstimated && $0.validDuration.isFinite && $0.validDuration > 0 }
        count = records.count
        meanBPM = records.isEmpty ? nil : records.map(\.blinksPerMinute).reduce(0, +) / Double(records.count)
        let durations = records.flatMap(\.blinkDurations)
        meanBlinkDurationMilliseconds = durations.isEmpty ? nil : durations.reduce(0, +) * 1000 / Double(durations.count)
        let total = records.map(\.validDuration).reduce(0, +)
        weightedBPM = total > 0 ? Double(durations.count) * 60 / total : nil
    }
    public static func filter(_ records: [MeasurementRecord], from: Date?, through: Date?, calendar: Calendar = .current) -> [MeasurementRecord] {
        let lower = from.map { calendar.startOfDay(for: $0) }
        let upper = through.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        return records.filter { record in
            (lower == nil || record.date >= lower!) && (upper == nil || record.date < upper!)
        }.sorted { $0.date < $1.date }
    }
}

/// Serializes mutations and atomic file replacement. An older async measurement cannot
/// restore a history that the user has since cleared: it must provide the current generation.
public struct HistorySnapshot: Equatable, Sendable {
    public var records: [MeasurementRecord]
    public var generation: UInt64
    public var revision: UInt64
    public init(records: [MeasurementRecord], generation: UInt64, revision: UInt64) {
        self.records = records; self.generation = generation; self.revision = revision
    }
}

public protocol MeasurementHistory: Sendable {
    func snapshotState() async -> HistorySnapshot
    func append(_ record: MeasurementRecord, expectedGeneration: UInt64) async throws -> Bool
    @discardableResult func clear(confirmed: Bool) async throws -> HistorySnapshot
}

public actor HistoryStore: MeasurementHistory {
    private var records: [MeasurementRecord]
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private let fileURL: URL?
    public init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            records = try JSONDecoder().decode([MeasurementRecord].self, from: Data(contentsOf: fileURL))
        } else { records = [] }
    }
    public func snapshot() -> [MeasurementRecord] { records }
    public func currentGeneration() -> UInt64 { generation }
    public func snapshotState() -> HistorySnapshot { .init(records: records, generation: generation, revision: revision) }
    @discardableResult public func append(_ record: MeasurementRecord, expectedGeneration: UInt64) throws -> Bool {
        guard !Task.isCancelled, expectedGeneration == generation else { return false }
        guard record.validDuration.isFinite, record.validDuration > 0,
              record.blinkDurations.allSatisfy({ $0.isFinite && $0 > 0 }), !records.contains(where: { $0.id == record.id }) else { return false }
        var updated = records; updated.append(record)
        try persist(updated); records = updated; revision &+= 1
        return true
    }
    @discardableResult public func clear(confirmed: Bool) throws -> HistorySnapshot {
        guard confirmed else { return snapshotState() }
        try persist([]); records = []; generation &+= 1; revision &+= 1
        return snapshotState()
    }
    private func persist(_ records: [MeasurementRecord]) throws {
        guard let fileURL else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: fileURL, options: .atomic)
    }
}
