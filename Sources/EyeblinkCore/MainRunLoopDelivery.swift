import Foundation
import CoreFoundation

/// AppKit's terminateLater uses a nested modal loop that does not service the
/// normal dispatch-main executor. Deliver completion in both supported modes.
public enum MainRunLoopDelivery {
    public static func perform(_ action: @escaping @MainActor @Sendable () -> Void) {
        RunLoop.main.perform(inModes: [.common, .init(rawValue: "NSModalPanelRunLoopMode")]) {
            MainActor.assumeIsolated { action() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }
}
