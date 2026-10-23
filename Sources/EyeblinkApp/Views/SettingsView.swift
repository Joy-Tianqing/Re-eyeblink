import SwiftUI
import AppKit
import EyeblinkCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section {
                Picker(model.text("语言", "Language"), selection: $model.settings.language) {
                    Text("简体中文").tag(AppLanguage.simplifiedChinese)
                    Text("English").tag(AppLanguage.english)
                }
                Toggle(model.text("登录时启动 Eyeblink", "Open Eyeblink at login"), isOn: Binding(get: { model.settings.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if model.loginApprovalRequired {
                    ContextNote(text: model.text("登录启动已登记，需要在系统设置中允许。", "The login item is registered and needs approval in System Settings."), symbol: "exclamationmark.circle")
                    Button(model.text("打开登录项设置", "Open Login Items Settings")) { model.openLoginSettings() }
                }
                ContextNote(text: model.text("关闭主窗口后，Eyeblink 会继续在菜单栏运行。可从菜单栏恢复、暂停或退出。", "Eyeblink keeps running in the menu bar when you close the main window. Reopen, pause, or quit from there."), symbol: "menubar.rectangle")
            } header: { Text(model.text("通用", "General")) }
            Section {
                LabeledContent(model.text("窗口标题权限", "Window title permission"), value: model.windowTitlePermissionGranted ? model.text("已授权", "Allowed") : model.text("未授权，窗口规则可能无法匹配", "Not allowed; window rules may not match"))
                ContextNote(text: model.text("此系统权限允许访问屏幕内容；Eyeblink 的窗口规则仅在本机读取标题，不保存屏幕画面。", "This system permission allows access to screen content. Eyeblink uses window titles locally for rules and does not save screen images."), symbol: "lock.shield")
                KeywordEditor(title: model.text("暂停摄像头的窗口关键词", "Window keywords that pause the camera"), placeholder: model.text("例如：视频会议", "For example: Video meeting"), keywords: $model.settings.pauseCameraKeywords)
                Toggle(model.text("摄像头规则只匹配前台窗口", "Apply camera rules to the frontmost window only"), isOn: $model.settings.pauseCameraFrontmostOnly)
                KeywordEditor(title: model.text("暂停全部功能的应用名称", "App names that pause all features"), placeholder: model.text("每行一个完整应用名称", "One full app name per line"), keywords: $model.settings.pauseProcessKeywords)
                KeywordEditor(title: model.text("暂停全部功能的窗口关键词", "Window keywords that pause all features"), placeholder: model.text("每行一个窗口标题关键词", "One window title keyword per line"), keywords: $model.settings.pauseWindowKeywords)
                if model.windowTitlePermissionGranted {
                    Button(model.text("打开窗口标题权限设置", "Open window title privacy settings"), action: model.openWindowTitlePrivacySettings)
                } else {
                    Button(model.text("授权窗口标题访问…", "Allow window title access…"), action: model.requestWindowTitleAccess)
                }
            } header: { Text(model.text("自动暂停", "Automatic pause")) } footer: {
                Text(model.text("规则不区分大小写。应用名称须完整匹配；窗口标题匹配关键词，读取受 macOS 隐私权限限制。匹配应用退出后自动恢复，手动暂停仍保留。", "Rules ignore case. App names must match in full; window titles match keywords and depend on macOS privacy permission. Features resume after matching apps quit, while a manual pause stays in effect."))
            }
            Section {
                LabeledContent(model.text("视频与测量", "Video & measurements"), value: model.text("本机处理与保存", "Processed and stored locally"))
                ContextNote(text: model.text("不录制视频，不上传测量数据。相机画面在本机处理，测量记录保存在这台 Mac 上。", "Video is not recorded and measurements are not uploaded. Camera images are processed locally and measurement history stays on this Mac."), symbol: "lock.shield")
            } header: { Text(model.text("隐私与数据", "Privacy & data")) }
        }
        .formStyle(.grouped)
    }
}

private struct KeywordEditor: View {
    var title: String
    var placeholder: String
    @Binding var keywords: [String]
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
                .onChange(of: text) { _, newValue in
                    let values = newValue.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if values != keywords { keywords = values }
                }
        }
        .padding(.vertical, 3)
        .onAppear { text = keywords.joined(separator: "\n") }
        .onChange(of: keywords) { _, values in
            let normalized = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if normalized != values { text = values.joined(separator: "\n") }
        }
    }
}
