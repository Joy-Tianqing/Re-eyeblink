import SwiftUI

struct CameraView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Form {
            Section {
                PageIntroduction(title: model.text("看见一次自然的眨眼", "See your natural blink"), detail: model.text("检查取景和检测状态，让交互提醒与测量正常工作。", "Check the camera and detection before using interactive reminders or measuring."), symbol: "camera")
            }
            Section {
                LabeledContent(model.text("状态", "Status")) {
                    Text(model.cameraStatus).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                if !model.cameraAuthorized {
                    HStack {
                        Button(model.text("允许使用摄像头", "Allow camera access"), action: model.requestCamera)
                            .buttonStyle(.borderedProminent)
                        Button(model.text("打开隐私设置", "Open Privacy Settings"), action: model.openCameraPrivacySettings)
                    }
                }
                if model.hasCameraFailure {
                    Button(model.text("重新连接摄像头", "Reconnect camera"), action: model.requestCamera)
                }
                Picker(model.text("摄像头", "Camera"), selection: Binding(get: { model.selectedCameraID }, set: { model.chooseCamera($0) })) {
                    if !model.selectedCameraID.isEmpty && !model.cameraDevices.contains(where: { $0.id == model.selectedCameraID }) {
                        Text(model.text("所选摄像头已断开", "Selected camera disconnected")).tag(model.selectedCameraID)
                    }
                    if model.cameraDevices.isEmpty {
                        Text(model.text("未发现摄像头", "No cameras available")).tag("")
                    }
                    ForEach(model.cameraDevices) { device in Text(device.name).tag(device.id) }
                }
                .disabled(model.cameraDevices.isEmpty)
                Toggle(model.text("启用摄像头功能", "Enable camera features"), isOn: $model.settings.cameraEnabled)
                HStack {
                    Text(model.text("摄像头任务", "Camera tasks"))
                    Spacer()
                    Button(model.isCameraManuallyPaused ? model.text("恢复摄像头", "Resume camera") : model.text("暂停摄像头", "Pause camera"), action: model.toggleCameraPause)
                        .disabled(model.isPaused || !model.settings.cameraEnabled)
                }
            } header: { Text(model.text("设备与权限", "Device & permission")) }
            Section {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.black)
                    if model.cameraPreviewEnabled && model.cameraAuthorized && !model.isCameraPaused {
                        CameraPreviewView(model: model).clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 34, weight: .light))
                            Text(model.isPaused || model.isCameraPaused ? model.text("摄像头已暂停", "Camera is paused") : model.text("摄像头预览已关闭", "Camera preview is off")).font(.headline)
                            Text(model.text("开启预览以调整位置并观察眨眼检测。", "Turn on the preview to adjust your position and check detection."))
                                .font(.callout).foregroundStyle(.white.opacity(0.7))
                        }.foregroundStyle(.white).padding(24)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxHeight: 320)
                .accessibilityLabel(model.text("摄像头实时预览", "Live camera preview"))
                HStack {
                    Text(model.cameraStatus).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.cameraPreviewEnabled ? model.text("关闭预览", "Stop preview") : model.text("开启预览", "Start preview"), action: model.togglePreview)
                        .disabled(!model.cameraAuthorized || model.isPaused || model.isCameraPaused || !model.settings.cameraEnabled || model.cameraDevices.isEmpty)
                }
                if (model.cameraPreviewEnabled || model.isMeasuring) && !model.isPaused && !model.isCameraPaused {
                    HStack {
                        LabeledContent(model.text("帧率", "Frame rate"), value: "\(model.framesPerSecond.formatted(.number.precision(.fractionLength(1)))) FPS")
                        Divider()
                        LabeledContent(model.text("已检测眨眼", "Blinks detected"), value: "\(model.blinkCount)")
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text(model.text("实时预览", "Live preview")) } footer: {
                Text(model.text("预览不会写入统计。保持自然看屏幕的姿势，并尽量让画面中只有一张脸。", "Preview does not add measurements to your history. Look at your screen naturally and keep one face in view."))
            }
            Section {
                ContextNote(text: model.text("相机画面在本机处理，不保存或上传视频。只有有效测量的眨眼数据会保存在本机。", "Camera images are processed on your Mac. Video is not saved or uploaded. Only valid blink measurements are stored locally."), symbol: "lock.shield")
            }
        }
        .formStyle(.grouped)
    }

}
