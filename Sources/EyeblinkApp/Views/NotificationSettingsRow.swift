import SwiftUI
import AppKit

struct NotificationSettingsRow: View {
    @ObservedObject var notifications: MeasurementNotifications
    var english: Bool
    var enabled: Bool
    private func text(_ zh: String, _ en: String) -> String { english ? en : zh }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(text("系统通知权限", "System notification access"), value: statusText)
            HStack {
                if notifications.authorization == .notDetermined {
                    Button(text("允许完成通知…", "Allow completion notifications…")) { notifications.requestPermission() }
                        .disabled(!enabled || notifications.isRequesting)
                } else if notifications.authorization.canDeliver {
                    Button(text("发送测试通知", "Send test notification")) { notifications.sendTest(english: english) }
                        .disabled(!enabled)
                }
                Button(text("通知设置…", "Notification Settings…")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
                }
            }
            if notifications.isRequesting { ProgressView(text("正在等待系统授权…", "Waiting for system permission…")).controlSize(.small) }
            if let delivery = notifications.measurementDelivery {
                Text(delivery == .delivered ? text("最近一次测量通知已送达通知中心。", "Latest measurement notification reached Notification Center.") : text("最近一次测量通知已提交，等待系统送达。", "Latest measurement notification submitted; waiting for system delivery."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let delivery = notifications.testDelivery {
                Text(delivery == .delivered ? text("测试通知已送达通知中心。", "Test notification reached Notification Center.") : text("测试通知已提交，等待系统送达。", "Test notification submitted; waiting for system delivery."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = notifications.lastError { Text(error).font(.caption).foregroundStyle(.secondary) }
            Text(text("仅在测量完成后通知。系统专注模式和通知样式也会影响显示。", "Notifications appear after a measurement. Focus and system notification styles also affect presentation."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { notifications.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in notifications.refresh() }
    }
    private var statusText: String {
        switch notifications.authorization {
        case .unknown: return text("正在读取系统状态", "Checking system settings")
        case .notDetermined: return text("尚未授权", "Not yet authorized")
        case .denied: return text("系统已关闭通知，请在通知设置中开启", "Disabled in system settings")
        case .authorized: return text("已获得通知权限", "Authorized")
        case .provisional: return text("已获得静默通知权限", "Quiet notifications authorized")
        }
    }
}
