import SwiftUI
import EyeblinkCore

struct BreaksView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section {
                PageIntroduction(title: model.text("休息，也是工作的一部分", "A little space to rest"), detail: model.text("离开屏幕，活动双眼。让下一段专注更舒服。", "Look away from the screen and give your eyes a change of pace."), symbol: "cup.and.saucer")
            }
            Section {
                Toggle(model.text("提醒离开电脑休息", "Remind me to take a computer break"), isOn: $model.settings.breakEnabled)
                IntervalField(title: model.text("休息间隔", "Break interval"), seconds: $model.settings.breakInterval, unit: model.text("分钟", "minutes"), divisor: 60, range: OriginalControlRanges.breakMinutes)
                    .disabled(!model.settings.breakEnabled)
                if model.settings.breakEnabled {
                    if model.isTakingBreak {
                        LabeledContent(model.text("正在休息", "Break in progress")) {
                            Button(model.text("查看当前提醒", "Show current reminder"), action: model.revealBreakReminder)
                        }
                    } else {
                        LabeledContent(model.text("下次休息提醒", "Next break reminder")) {
                            Text(nextBreakText).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                Button(model.text("预览休息提醒", "Preview break reminder"), action: model.previewBreak).disabled(model.isPaused)
            } header: { Text(model.text("电脑休息", "Computer breaks")) } footer: {
                Text(model.text("提醒出现后，可跳过本次，或推迟 5 分钟。离开电脑并满足下方空闲条件后，提醒会自动收起。", "Skip a reminder or snooze it for 5 minutes. It closes after you step away and meet the idle condition below."))
            }
            Section {
                Toggle(model.text("将自然休息计入休息时间", "Count time away as a natural break"), isOn: $model.settings.naturalBreaksEnabled)
                IntervalField(title: model.text("连续空闲超过", "After being idle for more than"), seconds: $model.settings.naturalBreakDuration, unit: model.text("分钟", "minutes"), divisor: 60, range: OriginalControlRanges.naturalMinutes)
            } header: { Text(model.text("自然休息", "Natural breaks")) } footer: {
                Text(model.text("没有键盘或鼠标操作并超过此时长后，结束当前休息。开启计入选项时，也重新计算下一次休息与眼操。", "A break ends after keyboard and mouse inactivity exceeds this duration. With this option enabled, time away also resets the next break and exercise."))
            }
            Section {
                Toggle(model.text("启用眼保健操", "Enable eye exercises"), isOn: $model.settings.exerciseEnabled)
                LabeledContent(model.text("眼操间隔", "Exercise interval")) {
                    Text(model.text("19 分钟", "19 minutes")).foregroundStyle(.secondary)
                }
                LabeledContent(model.text("练习内容", "Exercises")) {
                    Text(model.text("远眺 · 挤眼眨眼 · 左右转眼 · 旋转眼球", "Look far · Squeeze blink · Look sideways · Rotate eyes"))
                        .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                Menu(model.text("预览眼保健操", "Preview eye exercises")) {
                    ForEach(ExerciseKind.allCases, id: \.self) { kind in
                        Button(exerciseTitle(kind)) { model.previewExercise(kind) }
                    }
                }.disabled(model.isPaused)
            } header: { Text(model.text("眼保健操", "Eye exercises")) } footer: {
                Text(model.text("每个动作 10 秒，可以随时跳过。", "Each exercise takes 10 seconds and can be skipped at any time."))
            }
        }
        .formStyle(.grouped)
    }
    private var nextBreakText: String {
        if model.isPaused { return model.text("已暂停", "Paused") }
        if model.nextBreakRemaining <= 0 { return model.text("等待当前任务结束", "Waiting for the current task") }
        let seconds = Int(ceil(model.nextBreakRemaining))
        return model.text("\(seconds / 60) 分 \(seconds % 60) 秒后", "In \(seconds / 60) min \(seconds % 60) sec")
    }
    private func exerciseTitle(_ kind: ExerciseKind) -> String {
        switch kind {
        case .lookFar: return model.text("远眺", "Look far")
        case .squeezeBlink: return model.text("挤眼眨眼", "Squeeze blink")
        case .lookSideways: return model.text("左右转眼", "Look sideways")
        case .rotateEyes: return model.text("旋转眼球", "Rotate eyes")
        }
    }

}
