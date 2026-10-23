import AppKit

/// Only ordinary app windows keep a Dock presence. Background reminder panels
/// must not turn a menu-bar session back into a foreground application.
@MainActor
final class DockVisibilityController {
    private let center: NotificationCenter
    private let windows: @MainActor () -> [NSWindow]
    private let isHidden: @MainActor () -> Bool
    private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private var observers: [NSObjectProtocol] = []
    private var lastPolicy: NSApplication.ActivationPolicy?

    init(center: NotificationCenter = .default,
         windows: @escaping @MainActor () -> [NSWindow] = { NSApp.windows },
         isHidden: @escaping @MainActor () -> Bool = { NSApp.isHidden },
         applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }) {
        self.center = center
        self.windows = windows
        self.isHidden = isHidden
        self.applyPolicy = applyPolicy
    }

    func start() {
        stop()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification, NSWindow.willCloseNotification,
                     NSApplication.didHideNotification, NSApplication.didUnhideNotification,
                     NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    // willClose arrives before isVisible changes. Exclude the
                    // closing window while still accounting for a history window.
                    self?.refresh(excluding: notification.name == NSWindow.willCloseNotification ? notification.object as? NSWindow : nil)
                }
            })
        }
        refresh()
    }

    func refresh(excluding closingWindow: NSWindow? = nil) {
        let hasVisibleWindow = !isHidden() && windows().contains { window in
            guard window !== closingWindow, !(window is NSPanel), window.isVisible, !window.isMiniaturized,
                  let identifier = window.identifier?.rawValue else { return false }
            return identifier.hasPrefix("main") || identifier.hasPrefix("history")
        }
        setPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    /// Promote before opening/activating a window, including a previously hidden
    /// or minimized one. Its subsequent window notifications reconcile the state.
    func prepareToOpenWindow() { setPolicy(.regular) }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard policy != lastPolicy else { return }
        lastPolicy = policy
        applyPolicy(policy)
    }

    func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
        lastPolicy = nil
    }

    deinit { observers.forEach(center.removeObserver) }
}
