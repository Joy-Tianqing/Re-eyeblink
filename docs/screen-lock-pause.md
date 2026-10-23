# 锁屏暂停与解锁恢复（2026-10-23）

## 原版依据

基线为本机 eyeblink 3.7.4.0，主程序 SHA256
`bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db`。
使用本机 LLVM 读取原二进制，未运行或修改原应用。此前 REA 可识别目标，但深度分析 provider 未配置；以下属于静态调用链证据。

- `SystemListenerMacOS::nativeEventFilter`：`com.apple.screenIsLocked` 发出事件 0，`com.apple.screenIsUnlocked` 发出事件 1；睡眠和唤醒分别为 2、3。
- `EyeblinkGUI::systemAdapter`：跳转表中事件 0 指向 `0x100175229`，标记锁屏原因后进入 `pauseApp()`；事件 1 指向 `0x10017523c`，清除该标记并调用 `resumeApp()`。
- `pauseApp()` 隐藏提醒并发出 `pauseRequested(true)`；`ApplicationController::pauseProgram` 暂停相机任务时有 `stopCameraUseRequested()` 分支。

原始反汇编及跳转表：[screen-lock.disassembly.txt](../evidence/static/recovered-rules/screen-lock.disassembly.txt)。这是原版实现依据，不是原版真实锁屏实测。

## 当前实现

`SystemPauseObserver` 统一管理通知订阅：锁屏/解锁来自 `DistributedNotificationCenter`；睡眠/唤醒、用户会话切换来自 `NSWorkspace.notificationCenter`。分别使用 `screen-locked`、`systemSleep`、`session-inactive` 暂停原因，不相互清除，也不清除手动和自动规则暂停。

事件在主队列按交付顺序处理，重复状态不推进调度器。退出时移除全部订阅，代数检查拒绝已排队的旧订阅回调。注册后读取当前会话的 `CGSSessionScreenIsLocked` 标志，避免锁屏期间启动必须等下一次锁屏才能暂停；该标志及分布式锁屏通知属于 macOS 的现有系统约定，并非公开稳定的 AppKit 锁屏 API。

AppModel 复用 `engine.setPaused` → `synchronize` → `syncCamera`，不增加第二条相机控制路径：

- 锁屏时释放相机租约、停止采集、隐藏提醒，取消未完成测量，不把部分数据保存为完整测量。
- 锁屏期间停止任务执行；训练与测量等待计时继续，到期后等待恢复保护期再调度。旧帧和旧测量完成回调不能写入统计。此处已由[前四项对齐](first-four-alignment.md)修正。
- 解锁只移除锁屏原因。没有其他暂停原因时恢复原有调度；原本开启的预览取得新的相机租约，被取消的测量不会接着凑满时长。
- 睡眠、会话切换、手动暂停、相机暂停等仍生效时，不提前恢复。

## 验证

- 新增 9 项 `SystemPauseTests`：通知中心归属、AppModel 状态、手动暂停叠加、睡眠/会话与解锁的两种顺序、锁屏中启动、重复事件、退出/重注册/释放、预览租约、测量取消/迟到回调、训练和计时恢复。
- 暂时移除两条锁屏订阅，专门回归产生 2 个失败断言；恢复实现后通过。见 [反向验证](../evidence/native-tests/screen-lock-regression-red.log)。
- Release 全套 194 项通过，0 失败。见 [测试日志](../evidence/native-tests/screen-lock-release.log)。
- arm64 应用构建、严格签名、系统动态依赖、模型及许可证校验通过；目录与翻译证据检查通过。
- 新签名包真实预览约 23.1 FPS；捕获两次系统锁屏/解锁，分别在锁屏回调后约 0.25 秒、0.36 秒完成 `AVCaptureSession.stopRunning()`，随后清除输入输出并结束分析；解锁后自动恢复采集，UI 显示约 23.6 FPS。见 [系统及相机日志](../evidence/native-tests/screen-lock-live.json)。
- 两次锁屏实际持续约 2.64 秒和 2.09 秒；未把这次验收扩展为长时间睡眠/唤醒验收。用户随后明确确认：锁屏时相机指示灯熄灭；这是人工观察，和系统停止日志分别记录。恢复后“未检测到人脸”不影响采集恢复判断，也不作为真人识别准确率证明。
- 验收预览已关闭；随即触发的自动测量通过暂停/恢复取消。设置、既有 8 条历史和原版程序哈希复核不变。

正式结果与边界保存在 [验收报告](../evidence/native-tests/screen-lock-pause.json)。
