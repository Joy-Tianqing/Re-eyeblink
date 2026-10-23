# 识别链路对齐原版（2026-10-23）

本轮承接 2026-10-22 的侧置检测撤回，处理随后只读审计列出的七组差异。原版基线为本机 eyeblink 3.7.4.0，主程序 SHA256 `bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db`。未修改原应用、设置或历史数据。

| 差异 | 当前实现 | 证据与验证 |
|---|---|---|
| 已识别事件被当前帧有效性清空 | AppModel 交付事件不再依赖当前人脸；originalElapsedTime 计数保留无脸帧产出的眨眼，租约和重复时间戳仍隔离旧事件 | 原 mergeBlinks `0x100144411–0x100144441`；OriginalRecognitionRegressionTests / MultipleBlinkFrameTests |
| 启动预读缺失 | Model 的七次丢弃读取后，第八次图像建立灰度和时基；不提前计 FPS、无脸计时或扫描 | 原 `0x10013fe5d–0x10013fec7`；CameraFrameSourceTests / 原图像帧入口回归 |
| 每帧全历史重扫 | 10000 槽环形特征存储、左右独立持久游标/phase，保留 start+2 回溯、暂停补扫及跨重开 merger | 原 `0x100141e3d–0x1001423cb`；原版事件夹具及跨三次环回、跨环回拒绝回溯测试 |
| GUI 独立无帧超时 | 移除启动10秒和训练1秒/测量8秒的样本交付 watchdog；无脸期限仍由画面处理判断 | CameraStartupTests；原无脸和31帧FPS夹具继续通过 |
| 采集与完成检查顺序 | 独立 AVFoundation 采集队列；worker 每轮检查成功/截止，然后阻塞等待新回调；只保留最新缓冲，不重播积压图像；停止唤醒阻塞读取；终态释放相机后交付 | 原随包 videoio 静态反汇编；CameraFrameSourceTests / CameraTerminalOrderingTests；真实预览开关与退出日志 |
| 异常数值整帧过滤 | 非有限眼部特征进入各自状态机，按原浮点比较推进；不因一眼异常跳过另一眼。诊断 valid 不再决定事件是否计数 | 原左右 scanner 分支；NaN 保留phase、单眼 NaN/±Infinity 回归 |
| 训练收尾与提醒时序 | worker 下一轮优先检查计数，成功释放后直接隐藏；4001ms 提示由 worker 发出；MGD ready 即显示；无脸直接隐藏；原可恢复采集错误转3秒简单提醒，测量失败480秒后重试 | Controller/GUI 静态路径；TrainingFeedbackTests / DetectorFailureTests / CameraRunBoundaryTests |

## 采集后端的新确认

不能把 `alwaysDiscardsLateVideoFrames` 改为 false 来假装对齐。原版随包 `libopencv_videoio.4.4.0.dylib` 的 SHA256 为 `80286d04ba269bbd4693ca70bf8eb7cc57b6d81cec92cd40cf81005abd57489b`，实际使用：

- `0xdf23–0xdf35`：迟到帧丢弃为 true。
- `0xdf51–0xdf65`：Medium preset，之后通过输出 videoSettings 请求640×480，并接受设备实际尺寸。
- `0xe990–0xe9f8`：独立 callback 更新最新缓冲并 signal；`0xea10–0xea82`：每次 read 等待下一个 signal，不消费过去积压的帧。
- `0xe100–0xe185`：读取超时为1秒；常量 VA `0x2ad00` 解码为 Double 1.0。这是原后端 read 失败，和已移除的 GUI watchdog 不同。
- open 和设置尺寸各有一次 flush，之后才进入 Model 的7次预读和1次初始化读。

证据：[videoio-capture.disassembly.txt](../evidence/static/recovered-rules/videoio-capture.disassembly.txt)。使用本机 otool/LLVM 静态读取；REA 已识别目标，但深度分析 provider 未配置，未安装新工具。

## 训练 UI

实际连接 `userBlinked()` → `EyeblinkGUI::responceToBlink()`（`0x10012461e–0x100124636`）；普通训练走 hide/rollIn，直接隐藏，未启动额外成功动画。实时预览页可见时走播放声音分支，不关闭预览。生产识别不再进入自定义0.7+0.3秒成功动画；独立美术预览仍可预览既有图像。

错误掩码 `0x16c` 只覆盖 `{2,3,5,6,8}`，这些采集错误在交互训练中显示3秒简单提醒。Error4无脸直接隐藏，不显示重试按钮。测量错误重试间隔480秒，不暂停全部后续相机任务。模型损坏、内部计算异常等原版未给出可恢复控制路径的情况仍保留明确失败保护，不伪造成功。

证据：[controller-model.disassembly.txt](../evidence/static/recovered-rules/controller-model.disassembly.txt)、[recognition-alignment-training-ui.txt](../evidence/static/recovered-rules/recognition-alignment-training-ui.txt)。

## 验证与边界

详见 [验收报告](../evidence/native-tests/recognition-alignment.json)。Debug全套184项通过；随后新增终态顺序回归，最终Release全套185项通过。固定原版真实图像/事件夹具继续通过；新增长序列和异常值预期按原版指令推导，未新增原版长序列运行时夹具。

真实本机 FaceTime 相机预览两次进入“正在识别眨眼”，观察到23.2 FPS，关闭/重开/退出完成；未保存图像，未把预览写入统计。随后只修正了两处仍声称成功播放动画的说明文案，并重新构建、签名及运行Release测试。既有8条历史、设置文件、原版程序哈希复核未变。

这确认了列出的代码路径、固定输入与采集生命周期，不等于真人自然眨眼准确率验收，也不证明不同架构、不同驱动下所有输入逐位等价。
