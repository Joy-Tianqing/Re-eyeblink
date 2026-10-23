import AppKit
import XCTest
@testable import EyeblinkApp

@MainActor
private final class DockTestWindow: NSWindow {
    var shown = true
    var minimized = false
    override var isVisible: Bool { shown }
    override var isMiniaturized: Bool { minimized }
}

@MainActor
final class DockVisibilityTests: XCTestCase {
    private let center = NotificationCenter()
    private var windows: [NSWindow] = []
    private var hidden = false
    private var policies: [NSApplication.ActivationPolicy] = []

    private func window(_ id: String) -> DockTestWindow {
        _ = NSApplication.shared
        let window = DockTestWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.identifier = .init(id)
        windows.append(window)
        return window
    }
    private func controller() -> DockVisibilityController {
        DockVisibilityController(center: center, windows: { self.windows }, isHidden: { self.hidden }, applyPolicy: { self.policies.append($0) })
    }

    func testClosingLastWindowRemovesDockBeforeVisibilityChanges() {
        let main = window("main")
        let controller = controller(); controller.start()
        XCTAssertEqual(policies, [.regular])
        center.post(name: NSWindow.willCloseNotification, object: main)
        XCTAssertTrue(main.isVisible, "willClose is delivered before visibility changes")
        XCTAssertEqual(policies, [.regular, .accessory])
    }

    func testHistoryKeepsDockUntilItAlsoCloses() {
        let main = window("main"), history = window("history")
        let controller = controller(); controller.start()
        center.post(name: NSWindow.willCloseNotification, object: main)
        main.shown = false
        XCTAssertEqual(policies, [.regular])
        center.post(name: NSWindow.willCloseNotification, object: history)
        XCTAssertEqual(policies.last, .accessory)
    }

    func testMinimizingAndRestoringWindowUpdatesDock() {
        let main = window("main")
        let controller = controller(); controller.start()
        main.minimized = true
        center.post(name: NSWindow.didMiniaturizeNotification, object: main)
        XCTAssertEqual(policies.last, .accessory)
        controller.prepareToOpenWindow()
        XCTAssertEqual(policies.last, .regular)
        main.minimized = false
        center.post(name: NSWindow.didDeminiaturizeNotification, object: main)
        XCTAssertEqual(policies, [.regular, .accessory, .regular])
    }

    func testHiddenApplicationOnlyKeepsMenuBarUntilReopened() {
        _ = window("main")
        let controller = controller(); controller.start()
        hidden = true
        center.post(name: NSApplication.didHideNotification, object: nil)
        XCTAssertEqual(policies.last, .accessory)
        controller.prepareToOpenWindow()
        hidden = false
        center.post(name: NSApplication.didUnhideNotification, object: nil)
        XCTAssertEqual(policies, [.regular, .accessory, .regular])
    }

    func testBackgroundReminderAndUnrelatedWindowsDoNotRestoreDock() {
        let main = window("main"); main.shown = false
        _ = window("auxiliary")
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        panel.identifier = .init("main-reminder")
        windows.append(panel)
        let controller = controller(); controller.start()
        center.post(name: NSWindow.didBecomeKeyNotification, object: panel)
        XCTAssertEqual(policies, [.accessory])
        main.shown = true
        center.post(name: NSWindow.didBecomeKeyNotification, object: main)
        XCTAssertEqual(policies, [.accessory, .regular])
    }

    func testSwitchingFocusDoesNotHideDockAndRepeatedEventsDoNotReapplyPolicy() {
        let main = window("main")
        let controller = controller(); controller.start()
        center.post(name: NSWindow.didResignKeyNotification, object: main)
        center.post(name: NSWindow.didBecomeKeyNotification, object: main)
        XCTAssertEqual(policies, [.regular])
    }

    func testReactivatingAnExistingWindowRestoresDockWithoutNewKeyWindowEvent() {
        let main = window("main"); main.shown = false
        let controller = controller(); controller.start()
        XCTAssertEqual(policies, [.accessory])
        main.shown = true
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertEqual(policies, [.accessory, .regular])
    }

    func testStopAndRestartRemoveOldObservers() {
        let main = window("main")
        let controller = controller(); controller.start(); controller.start()
        policies.removeAll()
        center.post(name: NSWindow.willCloseNotification, object: main)
        XCTAssertEqual(policies, [.accessory])
        controller.stop()
        center.post(name: NSWindow.didBecomeKeyNotification, object: main)
        XCTAssertEqual(policies, [.accessory])
    }
}
