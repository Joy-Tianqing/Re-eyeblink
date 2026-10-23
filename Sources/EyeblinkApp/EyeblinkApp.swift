import SwiftUI
import AppKit
import EyeblinkCore
import OSLog

private let lifecycleLog = Logger(subsystem: "org.reeyeblink.app", category: "Termination")

@main
struct EyeblinkApplication: App {
    @NSApplicationDelegateAdaptor(EyeblinkAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Eyeblink", id: "main") {
            MainWindow(model: model, delegate: delegate)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(model.isManuallyPaused ? model.text("恢复 Eyeblink", "Resume Eyeblink") : model.text("暂停 Eyeblink", "Pause Eyeblink")) { model.togglePause() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
        Window(model.text("眨眼历史", "Blink history"), id: "history") {
            StatisticsView(model: model, historyOnly: true)
                .disabled(model.isShuttingDown)
                .tint(.teal)
                .environment(\.locale, Locale(identifier: model.settings.language == .english ? "en" : "zh-Hans"))
                .frame(minWidth: 720, minHeight: 500)
        }
        .defaultSize(width: 980, height: 700)
        MenuBarExtra {
            Button(model.text("打开 Eyeblink", "Open Eyeblink")) { model.openMainWindow() }.disabled(model.isShuttingDown)
            Divider()
            Button(model.isManuallyPaused ? model.text("恢复 Eyeblink", "Resume Eyeblink") : model.text("暂停全部功能", "Pause all features")) { model.togglePause() }.disabled(model.isShuttingDown)
            Button(model.isCameraManuallyPaused ? model.text("恢复相机功能", "Resume camera features") : model.text("暂停相机功能", "Pause camera features")) { model.toggleCameraPause() }
                .disabled(!model.cameraAuthorized || model.isShuttingDown)
            Button(model.text("立即测量", "Measure now")) { model.startMeasurement() }.disabled(model.isShuttingDown || model.isPaused || model.isMeasuring)
            Divider()
            Text(model.statusText)
            Button(model.text("退出 Eyeblink", "Quit Eyeblink")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: model.isPaused ? MenuBarIcon.paused : MenuBarIcon.active)
                .renderingMode(.template)
                .accessibilityLabel(model.isPaused ? model.text("Eyeblink（已暂停）", "Eyeblink (paused)") : "Eyeblink")
        }
    }
}

private struct MainWindow: View {
    @ObservedObject var model: AppModel
    let delegate: EyeblinkAppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model: model)
            .onAppear {
                delegate.model = model
                model.onOpenMainWindow = {
                    delegate.dockVisibility.prepareToOpenWindow()
                    openWindow(id: "main")
                }
            }
    }
}

@MainActor
final class EyeblinkAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    let dockVisibility = DockVisibilityController()
    private var shuttingDown = false
    func applicationDidFinishLaunching(_ notification: Notification) { dockVisibility.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dockVisibility.prepareToOpenWindow()
        if !flag { Task { @MainActor in model?.openMainWindow() } }
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { model?.terminate() } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lifecycleLog.notice("termination delegate entered")
        guard !shuttingDown else { return .terminateLater }
        shuttingDown = true
        dockVisibility.stop()
        lifecycleLog.notice("starting synchronous shutdown preparation")
        let shutdown = model?.beginShutdown()
        lifecycleLog.notice("shutdown preparation returned")
        Task.detached {
            await shutdown?.value
            lifecycleLog.notice("shutdown drained")
            MainRunLoopDelivery.perform {
                lifecycleLog.notice("replying to termination")
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}
