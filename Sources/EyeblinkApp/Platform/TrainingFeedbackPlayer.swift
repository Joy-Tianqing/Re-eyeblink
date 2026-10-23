import AppKit
import Combine
import EyeblinkCore
import OSLog

private let feedbackLog = Logger(subsystem: "org.reeyeblink.app", category: "TrainingFeedback")

enum TrainingReminderFrame: String {
    case open = "training-open"
    case wink = "training-wink"

    var image: NSImage {
        switch self {
        case .open: return Self.openImage
        case .wink: return Self.winkImage
        }
    }
    private static let openImage = load(.open)
    private static let winkImage = load(.wink)
    private static func load(_ frame: Self) -> NSImage {
        guard let url = Bundle.module.url(forResource: frame.rawValue, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            preconditionFailure("Missing training artwork: \(frame.rawValue)")
        }
        return image
    }
}

/// Two discrete approved frames; no looping GIF, camera lease, or extra timer.
/// The cancellable one-shot ends only after both visible holds have completed.
@MainActor
final class TrainingFeedbackPlayer: ObservableObject {
    typealias Sleep = @MainActor (TimeInterval) async throws -> Void
    @Published private(set) var frame: TrainingReminderFrame = .open
    private(set) var activeID: UUID?
    private var task: Task<Void, Never>?
    private let sleep: Sleep

    init(sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.sleep = sleep
    }

    func show(_ reminder: Reminder?, completion: @escaping @MainActor (UUID) -> Void) {
        guard let id = reminder?.trainingFeedbackID else { cancel(); return }
        guard activeID != id else { return }
        cancel()
        activeID = id
        frame = .wink
        feedbackLog.notice("frame=wink uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
        let sleep = self.sleep
        task = Task { [weak self] in
            do {
                try await sleep(0.7)
                guard !Task.isCancelled, self?.activeID == id else { return }
                self?.frame = .open
                feedbackLog.notice("frame=open uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
                try await sleep(0.3)
                guard !Task.isCancelled, self?.activeID == id else { return }
                self?.activeID = nil
                self?.task = nil
                feedbackLog.notice("event=completed uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
                completion(id)
            } catch {
                // Cancellation closes/replaces the presentation elsewhere.
            }
        }
    }

    func cancel() {
        task?.cancel(); task = nil
        activeID = nil
        if frame != .open { frame = .open }
    }

    deinit { task?.cancel() }
}
