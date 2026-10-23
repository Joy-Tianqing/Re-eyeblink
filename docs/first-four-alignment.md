# 前四项原版行为对齐（2026-10-23）

范围来自本轮差异审计的前四项。原版为本机 eyeblink 3.7.4.0，SHA256 `bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db`。通过本机 LLVM 读取原版二进制，未运行或修改原应用；[反汇编证据](../evidence/static/recovered-rules/first-four.disassembly.txt)属于静态依据，不是原版实机 A/B。

## 行为与依据

| 项目 | 对齐后的行为 | 原版依据 |
|---|---|---|
| 屏保、显示器息屏 | 分布式屏保通知、Workspace 显示器睡眠通知分别维护暂停原因；与锁屏、系统睡眠、会话、手动暂停叠加，只有全部原因解除才恢复 | `SystemListenerMacOS` 注册和事件分发；`systemAdapter` 事件 4/5/6/7 分别进入恢复/暂停分支 |
| 暂停期间计时 | 训练与测量等待计时继续，暂停时不执行任务；恢复仍经过生产默认 15 秒保护期；测量取消后 480 秒重试等待也继续。正在显示的简易提醒被收起时重新计满训练间隔 | `pauseProgram`（0x10013a0c0）保留 QTimer；简易提醒走 `hideBlinkReminder`，在 0x100139024 重启训练定时器 |
| 重新开启训练 | 关闭再开启时，从当前配置的完整间隔重新计时；无关设置修改不重置计时 | 启用分支在 0x100138e12 调用训练 QTimer.start，禁用分支调用 stop |
| 自动进程暂停 | 只取运行应用的 localizedName，转小写后完整匹配；不再对子串或可执行文件别名匹配。窗口关键词仍使用不区分大小写的包含匹配 | `getAllProcesses` 使用 localizedName；`setProcessesToCheck` 转小写；0x1001215c7 调用 QString 相等比较 |

沿用当前设置字段和逐行输入格式，忽略空行及输入两端空白，不做用户规则迁移。界面说明明确要求完整应用名称。未改识别链路、存储结构、其他审计项和生产计时间隔。

## 自动化与包验证

- 新增 11 项测试：8 项 `PauseAlignmentTests`、3 项系统通知/相机租约测试；原有锁屏及自动暂停断言按原版规则更新。
- 覆盖短暂停、长暂停、15 秒恢复保护、480 秒测量重试、测量优先级、迟到结果不保存、关闭后重开、暂停中重开、无关设置修改、简易提醒收起重计、全名与部分名称、窗口规则不变、多原因叠加及通知注销。
- 先写测试再修复：旧实现分别产生 [16 个失败断言](../evidence/native-tests/first-four-red.log)、[14 个系统分支失败断言](../evidence/native-tests/first-four-system-red.log)，简易提醒边界单独产生 [5 个失败断言](../evidence/native-tests/first-four-simple-red.log)。其中未修复测量重试测试的 XCTUnwrap 失败计为 unexpected assertion；没有测试进程崩溃。
- 最终 `xcrun swift test -c release`：**205 项，0 失败**，见 [完整日志](../evidence/native-tests/first-four-release.log)。测试使用可控时间与临时数据目录。
- `scripts/build-app.sh release` 和 `scripts/verify-native.py` 通过：arm64、严格签名、系统动态依赖、模型和许可证完整，见 [构建日志](../evidence/native-tests/first-four-package.log)、[包报告](../evidence/native-tests/first-four-build.json)。目录/翻译完整性检查也通过。

## 实机验收及边界

新签名包先开启预览，23.1 FPS；启动真实系统屏保后，14:35:55.795586 收到屏保暂停，14:35:56.273364 完成 `AVCaptureSession.stopRunning()`，间隔约 **0.48 秒**。14:36:03.953653 屏保结束时锁屏原因仍存在，应用继续暂停；14:36:04.275687 解锁后才恢复。随后界面确认预览 23.1 FPS，采集恢复。[系统日志](../evidence/native-tests/first-four-live.json)仅保留时间、类别和消息，无相机图像。

用户明确要求“不要息屏测试了”，因此未触发显示器息屏实测；该分支仅有自动化证据，不能写成实机通过。本轮屏保期间的物理相机灯未获人工确认。计时和进程匹配使用可控单测验证，没有修改实际用户规则做 UI 计时实验。

验收预览已关闭；关闭后立即调度的任务通过暂停/恢复取消，正常调度已恢复，应用停留设置页。

## 数据保护

操作前后比较 SHA256：`settings.json`、包含既有 **8 条**记录的 `measurements.json`、新版偏好、两个原版偏好文件以及原版主程序均逐字节不变。没有清空、迁移或补写用户记录。详细摘要见 [本轮报告](../evidence/native-tests/first-four-alignment.json)。
