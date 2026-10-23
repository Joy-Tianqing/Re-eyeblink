import AppKit
import SwiftUI
import EyeblinkCore
import OSLog

private let reminderLog = Logger(subsystem: "org.reeyeblink.app", category: "TrainingReminder")

@MainActor
private final class ReminderState: ObservableObject {
    @Published var reminder: Reminder?
    @Published var isPreview = false
}

@MainActor
private final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ReminderWindowController {
    private let state = ReminderState()
    private let feedbackPlayer = TrainingFeedbackPlayer()
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var moveObserver: NSObjectProtocol?
    private var currentPositionKey = ""

    init(model: AppModel) { self.model = model }
    func show(reminder: Reminder?, isPreview: Bool) {
        guard let model else { return }
        let enteringPreview = isPreview && !state.isPreview
        if state.reminder != reminder {
            let phase: String
            switch reminder {
            case .training: phase = "waiting"
            case .trainingFeedback: phase = "feedback"
            case .trainingInterrupted: phase = "interrupted"
            case nil: phase = "closed"
            default: phase = "other"
            }
            reminderLog.notice("phase=\(phase, privacy: .public) preview=\(isPreview, privacy: .public) uptime=\(ProcessInfo.processInfo.systemUptime, privacy: .public)")
        }
        state.reminder = reminder
        state.isPreview = isPreview
        feedbackPlayer.show(reminder) { [weak model] id in model?.finishTrainingFeedback(id) }
        guard let reminder else { panel?.orderOut(nil); return }
        if panel == nil {
            let p = ReminderPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 280), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.hidesOnDeactivate = false
            p.title = model.text("Eyeblink 提醒", "Eyeblink Reminder")
            p.contentView = NSHostingView(rootView: ReminderOverlayView(model: model, state: state, feedbackPlayer: feedbackPlayer))
            panel = p
            moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                // Capture the current kind/frame while this move notification is
                // delivered, before a later task can switch the reminder kind.
                MainActor.assumeIsolated { self?.savePosition() }
            }
        }
        let key: String
        switch reminder { case .training, .trainingFeedback, .trainingInterrupted: key = "training"; case .exercise: key = "exercise"; case .rest: key = "rest" }
        if currentPositionKey != key || !(panel?.isVisible ?? false) {
            currentPositionKey = key
            restorePosition()
        }
        panel?.title = model.text("Eyeblink 提醒", "Eyeblink Reminder")
        if enteringPreview || !(panel?.isVisible ?? false) {
            if isPreview { panel?.makeKeyAndOrderFront(nil) }
            else { panel?.orderFrontRegardless() }
        }
    }
    private func restorePosition() {
        guard let panel else { return }
        let stored = UserDefaults.standard.dictionary(forKey: "reminderPosition.\(currentPositionKey)")
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = panel.frame
        if let x = stored?["x"] as? Double, let y = stored?["y"] as? Double { frame.origin = .init(x: x, y: y) }
        else { frame.origin = .init(x: visible.maxX - frame.width - 28, y: visible.maxY - frame.height - 28) }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(frame) }) {
            frame.origin = .init(x: min(max(frame.minX, visible.minX), visible.maxX - frame.width), y: min(max(frame.minY, visible.minY), visible.maxY - frame.height))
        }
        panel.setFrame(frame, display: true)
    }
    private func savePosition() {
        guard !currentPositionKey.isEmpty, let panel else { return }
        UserDefaults.standard.set(["x": panel.frame.minX, "y": panel.frame.minY], forKey: "reminderPosition.\(currentPositionKey)")
    }
    /// A user can recover a reminder obscured by another window. Scheduled
    /// reminders still appear without taking focus; only this explicit action does.
    func reveal() {
        guard let panel, panel.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    func close() {
        feedbackPlayer.cancel()
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.close(); panel = nil
    }
}

@MainActor
private struct ReminderOverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: ReminderState
    @ObservedObject var feedbackPlayer: TrainingFeedbackPlayer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label("Eyeblink", systemImage: "eye").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                WindowDragRegion().frame(minWidth: 16, maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                    .accessibilityHidden(true)
                if state.isPreview { Text(model.text("预览", "Preview")).font(.caption).foregroundStyle(.secondary) }
                Button { model.dismissReminder() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).help(model.text("关闭提醒", "Dismiss reminder"))
            }
            if state.reminder?.isTraining == true {
                Image(nsImage: feedbackPlayer.frame.image)
                    .resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(.primary).frame(width: 104, height: 84)
                    .accessibilityLabel(model.text(feedbackPlayer.frame == .wink ? "眨眼微笑" : "睁眼微笑", feedbackPlayer.frame == .wink ? "Winking smile" : "Open-eye smile"))
            } else {
                Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.teal).frame(height: 58)
                    .accessibilityHidden(true)
            }
            VStack(spacing: 7) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let reminder = state.reminder {
                switch reminder {
                case .rest:
                    HStack {
                        Button(model.text("跳过本次", "Skip this break")) { model.dismissReminder() }.buttonStyle(.bordered)
                        Button(model.text("5 分钟后提醒", "Remind in 5 minutes")) { model.snoozeBreak() }.buttonStyle(.borderedProminent).tint(.teal)
                    }.controlSize(.regular)
                case .exercise(_, let remaining):
                    HStack {
                        Text("\(Int(ceil(remaining))) " + model.text("秒", "sec")).monospacedDigit().foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("跳过练习", "Skip exercise")) { model.dismissReminder() }.buttonStyle(.bordered)
                    }
                case .training:
                    if state.isPreview {
                        Button(model.text("播放动画", "Play animation"), action: model.playTrainingFeedbackPreview).buttonStyle(.bordered)
                    } else {
                        Text(model.text("拖动顶部空白处可调整提醒位置", "Drag the space in the title bar to reposition it")).font(.caption).foregroundStyle(.tertiary)
                    }
                case .trainingFeedback:
                    Text(model.text("拖动顶部空白处可调整提醒位置", "Drag the space in the title bar to reposition it")).font(.caption).foregroundStyle(.tertiary)
                case .trainingInterrupted:
                    Button(model.text("重新识别", "Try again"), action: model.retryTraining)
                        .buttonStyle(.borderedProminent).tint(.teal)
                        .disabled(model.isCameraPaused || !model.cameraAuthorized)
                }
            }
        }
        .padding(22).frame(width: 360, height: 280)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 20).fill(Color(nsColor: .windowBackgroundColor)) }
            else { RoundedRectangle(cornerRadius: 20).fill(.regularMaterial) }
        }
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.10)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: symbol)
    }
    private var symbol: String {
        switch state.reminder {
        case .training, .trainingFeedback, .trainingInterrupted: return "eye"
        case .exercise(let kind, _):
            switch kind { case .lookFar: return "window.casement"; case .squeezeBlink: return "eye.slash"; case .lookSideways: return "arrow.left.and.right"; case .rotateEyes: return "arrow.triangle.2.circlepath" }
        case .rest: return "figure.walk"
        case nil: return "eye"
        }
    }
    private var title: String {
        switch state.reminder {
        case .training: return model.text("轻轻眨一下眼", "Take a gentle blink")
        case .trainingFeedback: return model.text("眨眼完成", "Blink complete")
        case .trainingInterrupted: return model.text("还没识别到眨眼", "Blink not detected yet")
        case .exercise: return model.text("给眼睛一点休息", "A little rest for your eyes")
        case .rest: return model.text("起来走一走", "Time to step away")
        case nil: return ""
        }
    }
    private var subtitle: String {
        switch state.reminder {
        case .training(let mode, _):
            if state.isPreview { return model.text("这是提醒样式预览。", "This is a preview of the reminder.") }
            return mode == .interactive ? model.text("检测到自然眨眼后自动收起。", "This reminder closes when a natural blink is detected.") : model.text("放松眼睛，完整地眨一下。", "Relax your eyes and make a complete blink.")
        case .trainingFeedback: return model.text("很好，让眼睛保持轻松。", "Keep your eyes relaxed.")
        case .trainingInterrupted:
            return model.text("暂时看不清眼睛，请回到摄像头前重试。", "Your eyes were not visible. Return to the camera, then retry.")
        case .exercise(let kind, _):
            switch kind {
            case .lookFar: return model.text("望向窗外或远处，让目光停留 10 秒。", "Look out of a window or into the distance for 10 seconds.")
            case .squeezeBlink: return model.text("轻轻挤紧眼睑并眨眼，持续 10 秒。", "Blink while gently squeezing your eyelids for 10 seconds.")
            case .lookSideways: return model.text("让眼睛左右移动，持续 10 秒。", "Move your eyes from side to side for 10 seconds.")
            case .rotateEyes: return model.text("缓慢转动眼睛，持续 10 秒。", "Slowly rotate your eyes for 10 seconds.")
            }
        case .rest:
            let minutes = Int(ceil(model.settings.naturalBreakDuration / 60))
            return model.text("离开屏幕，放松身体。连续空闲超过 \(minutes) 分钟后，提醒会自动收起。", "Step away and stretch. This reminder closes after more than \(minutes) minutes without keyboard or mouse input.")
        case nil: return ""
        }
    }
}
