import SwiftUI
import EyeblinkCore

struct TrainingView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section {
                PageIntroduction(title: model.text("让眨眼回到自然节奏", "Make room for a natural blink"), detail: model.text("工作时轻轻提醒，给专注中的双眼一点照顾。", "Gentle reminders for your eyes while you focus."), symbol: "eye")
            }
            Section {
                Toggle(model.text("启用眨眼训练", "Enable blink training"), isOn: $model.settings.trainingEnabled)
                Group {
                    Picker(model.text("提醒方式", "Reminder style"), selection: $model.settings.trainingMode) {
                        Text(model.text("定时提醒", "Scheduled")).tag(TrainingMode.simple)
                        Text(model.text("低频时提醒", "When blinking slows")).tag(TrainingMode.interactive)
                    }
                    IntervalField(title: model.text("提醒间隔", "Reminder interval"), seconds: $model.settings.trainingInterval, unit: model.text("秒", "seconds"), range: OriginalControlRanges.trainingSeconds)
                    Toggle(isOn: $model.settings.mgdEnabled) {
                        HStack(spacing: 6) {
                            Text(model.text("MGD 模式", "MGD mode"))
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .help(mgdExplanation)
                    .accessibilityHint(mgdExplanation)
                    Toggle(model.text("播放提醒音", "Play a reminder sound"), isOn: $model.settings.reminderSoundEnabled)
                }.disabled(!model.settings.trainingEnabled)
            } header: {
                Text(model.text("眨眼提醒", "Blink reminders"))
            } footer: {
                Text(modeExplanation)
            }
            Section {
                if model.isCameraPaused || !model.cameraAuthorized {
                    ContextNote(text: model.text("当前使用无需相机的定时提醒。相机恢复后，将按所选方式提醒。", "Using timed reminders while the camera is unavailable. Your selected style resumes when the camera is ready."), symbol: "camera.slash")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.text("试一下提醒", "Try a reminder"))
                        Text(model.text("出现后可拖动顶部空白处，调整提醒位置。", "Drag the space in its title bar to reposition it.")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.text("预览提醒", "Preview reminder"), action: model.showReminderPreview)
                        .disabled(model.isPaused)
                }
                if model.settings.trainingMode == .interactive || model.settings.mgdEnabled {
                    ContextNote(text: model.text("交互提醒需要摄像头。检测到眨眼后自动关闭，也可以手动关闭。", "Interactive reminders use the camera and close when a blink is detected. You can also dismiss them manually."), symbol: "camera")
                } else {
                    ContextNote(text: model.text("定时提醒无需摄像头，适合仅使用轻量提醒。", "Scheduled reminders work without a camera."), symbol: "camera.slash")
                }
            }
            if model.isPaused {
                Section { ContextNote(text: model.isManuallyPaused ? model.text("全部功能已手动暂停。点击工具栏的恢复按钮继续。", "All features are manually paused. Resume from the toolbar to continue.") : model.text("全部功能已自动暂停，暂停条件解除后会自动恢复。", "All features are automatically paused and will resume when the pause condition ends."), symbol: "pause.circle") }
            }
        }
        .formStyle(.grouped)
    }

    private var mgdExplanation: String {
        model.text(
            "MGD（Meibomian Gland Dysfunction）即睑板腺功能障碍。睑板腺分泌的油脂帮助减少泪液蒸发；功能异常时，眼睛更容易干涩。\n\n开启后，按设定间隔提醒眨眼，检测到眨眼后自动关闭；相机不可用时使用定时提醒。\n\n此模式不用于诊断或治疗 MGD。",
            "MGD stands for Meibomian Gland Dysfunction. These glands in the eyelids produce oil that helps reduce tear evaporation. When they do not work properly, the eyes can become dry.\n\nWhen enabled, reminders appear at the selected interval and close after a detected blink. Timed reminders are used when the camera is unavailable.\n\nThis mode does not diagnose or treat MGD."
        )
    }

    private var modeExplanation: String {
        if model.settings.mgdEnabled {
            return model.text("MGD 模式按间隔提醒，并在检测到眨眼后关闭。", "MGD mode reminds you at each interval and dismisses after a detected blink.")
        }
        return model.settings.trainingMode == .simple
            ? model.text("按设定间隔提醒眨眼，无需开启摄像头。", "A gentle reminder at the selected interval, without using the camera.")
            : model.text("通过摄像头观察眨眼节奏，仅在眨眼频率偏低时提醒。", "Uses the camera to observe your blink rhythm and remind you when it slows.")
    }
}
