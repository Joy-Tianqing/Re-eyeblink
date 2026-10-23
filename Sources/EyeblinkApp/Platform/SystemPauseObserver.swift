import AppKit
import EyeblinkCore

/// Lock/screensaver notifications use the distributed center; display/system
/// sleep and user switching use the workspace center. Reasons remain independent.
@MainActor
final class SystemPauseObserver {
    static let screenLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    static let screensaverStarted = Notification.Name("com.apple.screensaver.didstart")
    static let screensaverStopped = Notification.Name("com.apple.screensaver.didstop")
    static let lockReason = PauseReason.custom("screen-locked")
    static let sessionReason = PauseReason.custom("session-inactive")
    static let displayReason = PauseReason.custom("display-asleep")
    static let screensaverReason = PauseReason.custom("screensaver-active")

    private let workspace: NotificationCenter
    private let distributed: NotificationCenter
    private let initiallyLocked: () -> Bool
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var handler: ((PauseReason, Bool) -> Void)?
    private var generation = UUID()

    init(workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributed: NotificationCenter = DistributedNotificationCenter.default(),
         initiallyLocked: @escaping () -> Bool = {
             (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
         }) {
        self.workspace = workspace
        self.distributed = distributed
        self.initiallyLocked = initiallyLocked
    }

    func start(handler: @escaping (PauseReason, Bool) -> Void) {
        stop()
        self.handler = handler
        observe(workspace, NSWorkspace.willSleepNotification, reason: .systemSleep, paused: true)
        observe(workspace, NSWorkspace.didWakeNotification, reason: .systemSleep, paused: false)
        observe(workspace, NSWorkspace.screensDidSleepNotification, reason: Self.displayReason, paused: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, reason: Self.displayReason, paused: false)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, reason: Self.sessionReason, paused: true)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, reason: Self.sessionReason, paused: false)
        observe(distributed, Self.screenLocked, reason: Self.lockReason, paused: true)
        observe(distributed, Self.screenUnlocked, reason: Self.lockReason, paused: false)
        observe(distributed, Self.screensaverStarted, reason: Self.screensaverReason, paused: true)
        observe(distributed, Self.screensaverStopped, reason: Self.screensaverReason, paused: false)
        // Subscribe before reading the snapshot, and before AppModel can open a
        // camera. A login/relaunch while locked must not wait for the next lock.
        if initiallyLocked() { handler(Self.lockReason, true) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, reason: PauseReason, paused: Bool) {
        let generation = generation
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Synchronous main-queue delivery preserves lock/unlock order;
            // unstructured Tasks could resume after shutdown or a newer event.
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.handler?(reason, paused)
            }
        }
        observers.append((center, token))
    }

    func stop() {
        generation = UUID()
        handler = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
}
