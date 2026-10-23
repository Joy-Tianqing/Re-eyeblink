import SwiftUI
import EyeblinkCore

enum AppPage: String, CaseIterable, Identifiable {
    case training, breaks, statistics, camera, settings, about
    var id: Self { self }
    var symbol: String {
        switch self {
        case .training: return "eye"
        case .breaks: return "cup.and.saucer"
        case .statistics: return "chart.xyaxis.line"
        case .camera: return "camera"
        case .settings: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
    @MainActor func title(_ model: AppModel) -> String {
        switch self {
        case .training: return model.text("眨眼训练", "Blink training")
        case .breaks: return model.text("休息与眼操", "Breaks & exercises")
        case .statistics: return model.text("眨眼统计", "Blink statistics")
        case .camera: return model.text("摄像头", "Camera")
        case .settings: return model.text("设置", "Settings")
        case .about: return model.text("关于 Eyeblink", "About Eyeblink")
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var selection: AppPage? = .training
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section(model.text("护眼", "Eye care")) {
                    ForEach([AppPage.training, .breaks, .statistics]) { page in
                        Label(page.title(model), systemImage: page.symbol).tag(page)
                    }
                }
                Section(model.text("应用", "Application")) {
                    ForEach([AppPage.camera, .settings, .about]) { page in
                        Label(page.title(model), systemImage: page.symbol).tag(page)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Eyeblink")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Label(model.isPaused ? model.text("已暂停", "Paused") : model.text("正在守护双眼", "Looking after your eyes"), systemImage: model.isPaused ? "pause.circle" : "eye.circle")
                        .font(.callout.weight(.medium))
                    Text(model.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            Group {
                switch selection ?? .training {
                case .training: TrainingView(model: model)
                case .breaks: BreaksView(model: model)
                case .statistics: StatisticsView(model: model)
                case .camera: CameraView(model: model)
                case .settings: SettingsView(model: model)
                case .about: AboutView(model: model)
                }
            }
            .navigationTitle((selection ?? .training).title(model))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: model.togglePause) {
                        Label(model.isManuallyPaused ? model.text("恢复全部功能", "Resume all") : model.text("暂停全部功能", "Pause all"), systemImage: model.isManuallyPaused ? "play.fill" : "pause.fill")
                    }
                    .help(model.text("演示或专注时暂停全部提醒与摄像头", "Pause reminders and camera during a presentation"))
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            }
        }
        .disabled(model.isShuttingDown)
        .tint(.teal)
        .environment(\.locale, Locale(identifier: model.settings.language == .english ? "en" : "zh-Hans"))
        .frame(minWidth: 820, minHeight: 620)
        .onChange(of: model.settings) { _, _ in model.saveSettings() }
        .transaction { transaction in if reduceMotion { transaction.animation = nil } }
        .alert(model.text("操作未完成", "Unable to complete the action"), isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button(model.text("好", "OK"), role: .cancel) { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
