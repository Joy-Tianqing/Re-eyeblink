最新检查点（2026-10-21）：N049从原私有OSLog恢复15次实际idleCompletion，首条idle188.533935秒；同时浮层视觉仍未捕获。设置与8条历史完整恢复。N050已打包最新光流/预览中断修复并实际启动：90项Swift、9组统计、307040灰度字节对照通过，真实相机约37–39FPS、1事件，正常退出。包校验新增Package.swift/模型SHA/图标/Bundle信息。下方各阶段保留原日期及数量。

最新检查点：90项Swift测试通过；预览打断休息/眼操/简单提醒现复用原完成语义，3项回归先失败后通过。原OpenCV灰度/blur3图307040字节与生产BGRA接口精确一致，UBSAN通过。当前正式休息实测仍继续，用户确认前两次点击过推迟5分钟，不能记自动空闲结束。见N047/N048。

最新检查点：87项Swift回归通过，新增实际原预测器8图40点金值与灰度SHA对照；原光流统计9组从4/9修正为9/9精确一致，恢复两遍方差、variance<=1e-8不sqrt和列优先顺序，27项C光流契约及9组统计UBSAN通过。真实15分钟休息仍在此前签名包中计时，未为编译中断或替换。见N045/N046。

最新检查点：全套86项测试（74Core+12App）通过；生产休息生命周期由实际调度分支发出typed effect，App在原有消费入口写本机OSLog，避免把倒计时重置当作自动结束。3项新回归覆盖结束原因和原时钟边界；签名包启动/正常退出已观察。尚未取得新的正式15分钟休息事件日志，N040仍不确定。见`evidence/native-ui/44-rest-end-cause-trace.txt`。

最新检查点：83项Swift测试（71Core+12App）通过，另有2项release眼区几何回归通过。原Model两图12组选脸及8组眼区几何函数对照一致；生产CameraPipeline接入提取的EyeGeometry，保留原Float减号与非合并运算顺序。新租约清零FPS/显示启动中，测量无预览时显示实时FPS；真实28.5FPS无脸测量→停止→历史字节不变已观察。发布只复制App资源并拒绝Tests.bundle。见`evidence/native-ui/42-face-selection-and-eye-geometry.txt`及`43-real-no-face-measurement.txt`。下方测试数量和行号保留各阶段历史，不能作为当前快照。

按需采样补证：自动暂停每2秒检查一次；当前空规则仍查询进程/窗口的旧行为已有失败回归。现由同步闭包按所需数据源读取，全空/空白规则零读取，清空规则仍返回空匹配以移除旧原因。新增1项回归后全套81项通过，真实自身进程规则暂停→叠加手动暂停→移除规则仍暂停→手动恢复已观察；屏幕录制权限未申请或修改。见`evidence/native-ui/41-lazy-pause-providers.txt`。

# 原生运行集成审查

通知最新补证：新增授权状态、明确授权入口、前台展示delegate、系统送达回读及迟到任务失效；4项回归含实际AppModel关闭/清空/退出和提交结果未知的清理。后续增加生产通知回读与迟到回读失效2项回归，通知阶段总计80项通过，后续按需采样回归后总计81项。系统测试通知已送达，后续真实180秒完成→保存→自动通知系统回读已通过N038，直接横幅仍待观察，见`evidence/native-ui/37-measurement-notifications.txt`及`39-production-measurement-notification.txt`。

最新状态：采集中退出延迟进一步定位为停止请求等待帧队列，诊断一轮等待约40秒。会话启停与分析分成两条串行队列，停旧delegate后再等待有限分析；真实菜单退出与暂停/恢复后Command-Q收尾分别约0.158/0.096秒，进程均终止。74项测试通过。见`evidence/native-ui/36-camera-session-queue.txt`；冷启动中止、物理断连与真实OS退出仍待验收。

最新补证：2026-10-19增加相机会话错误/设备断开通知、会话代数过滤及停止清理，4项NotificationCenter集成测试通过；另修复旧检测失败覆盖暂停/新预览状态。当前全套73项通过。真实预览开关/重开已观察，物理断连与系统中断仍待验收，见`evidence/native-ui/34-camera-session-failures.txt`。下文保留原审查快照及当时证据，历史行号与测试数量不代表当前源码。

审查日期：2026-10-19。范围是AppModel、相机队列、提醒浮层、应用退出/重开及它们与Core/HistoryStore的调用关系。本轮仅只读审查这些实现，没有启动或操作用户原应用，也没有实际授予权限、断开相机、触发系统睡眠或改用户偏好。下列复现步骤是需要平台夹具或实机执行的验收步骤；不能把源代码分析写成已完成实机复现。

本轮原模型的5项Dlib测试、官方arm64 dlib参考夹具只证明关键点预测器边界。Core调度/存储测试通过也不能证明AVCapture、TCC、MainActor或NSPanel集成完成。

## 应先处理的发现

### R1 · P1 · 清空记录期间新测量会绑定旧存储代数

位置：`Sources/EyeblinkApp/AppModel.swift:170` 的clearMeasurements、`:140`/`:250`绑定测量代数；`Sources/EyeblinkCore/Measurements.swift:85`拒绝不匹配代数。

clearMeasurements先取消现有测量，再创建一个Task；这个Task要等history.clear后才通过另一次await读取新generation。清空开始和historyGeneration更新之间，应用没有“清空处理中”状态，startMeasurement仍可读取旧historyGeneration。此期间开始的新测量在结束时被HistoryStore正常拒绝，但AppModel仅在append返回true时更新UI，false不会给出原因。

可复现调度：让history.clear的持久化稍慢；在调用clearMeasurements后、MainActor缓存generation更新前调用startMeasurement；等待这个新测量结束。预期新测量可以保存；当前链路会以旧代数append并返回false。这个问题在AppModel跨await窗口，HistoryStore内部“拒绝清空前的旧结果”机制应保留。

建议把清空作为一个有状态事务：先禁止新测量，actor单次清空并返回新代数+snapshot，更新MainActor后恢复新测量；或在MainActor先推进可传入actor的epoch。加一个可控延迟的平台/协调器回归，验证“清空前旧任务被拒、清空后新任务被保存”。

### R2 · P1 · 退出没有等待最后一次测量写入

位置：`AppModel.swift:264`创建异步append Task，`:320`terminate；`EyeblinkApp.swift:28`菜单直接terminate应用、`:54`applicationWillTerminate。

完成测量的effect只创建Task保存，AppModel不保留/等待该Task。菜单调用terminate后立即NSApp.terminate；delegate终止回调也只停止相机/计时器。刚完成的记录可以仍停在MainActor待运行Task或HistoryStore待处理请求中，进程已经退出；原子写盘只能保护已经开始的那次写入，不能让尚未执行的Task自动完成。

可复现调度：在同一MainActor测试步骤里交付measurementCompleted并立即请求退出，或在慢持久化夹具中等待append排队后退出；重开核对记录。需要确保应用退出前最后一次被接受的测量已落盘。

建议由AppModel追踪存储任务，delegate使用applicationShouldTerminate返回terminateLater，await drain后reply；Command-Q、菜单退出、系统退出统一走同一路径，不在菜单提前做两套终止动作。此项还没有平台终止夹具的实测结果。

### R3 · P2 · 旧输出回调可能被赋予新相机token

位置：`Platform/CameraPipeline.swift:46`切换handler/generation，`:84`设置delegate，`:97`stop，`:117`captureOutput，`:171`构造观察值；`AppModel.swift:295`只核对观察中的generation。

同一串行队列避免了两个方法同时修改状态，但captureOutput不校验传进来的AVCaptureOutput身份。若旧输出对象的待交付回调在新start之后被派发，它读取的是self新的handler/generation，因此会被标记成新lease的帧；上层token校验无法辨别。这是缺失入口约束的静态风险，AVFoundation实际排队行为仍需注入/快速切换相机验证，不能声称本轮已观察到串流污染。

建议保存当前activeOutput，captureOutput先guard identity；停止/替换前清除旧输出delegate，始终在这条队列处理。回归应把“旧output的迟到sample”和“旧generation的迟到MainActor观察”分开注入，二者都必须拒绝。

### R4 · P2 · 训练计时从申请相机开始，早于真实相机就绪

位置：`EyeblinkCore/EyeblinkEngine.swift`中设置trainingStartedAt的调度分支；`CameraPipeline.swift:59`首次解析模型、`:67–88`配置/启动采集；`AppModel.swift:290`启动异步相机。

原版trainingStarted信号在相机初始化、有效帧读取后发出。当前Core取得lease时就开始MGD显示/4.001秒观察/无帧计时；首次模型加载、系统相机冷启动会消耗这些时间。新加入的1秒training-no-frames watchdog能解除旧版“启动错误只报一次，训练永久busy”的问题，但也可能在合法慢启动期间提前取消训练。

建议区分cameraRequested/cameraStarted/terminalFailure：启动阶段使用独立超时；收到started后才开始观察和无脸窗口。只对检测事件计时的Core测试无法覆盖真实设备冷启动延迟。

### R5 · P2 · 登录启动状态只反映用户请求，未反映系统实际状态

位置：`AppModel.swift:160–168`；`Views/SettingsView.swift:14`。

register无异常后直接把settings.launchAtLogin写成true；初次读取设置时也没有向SMAppService核对。用户从系统设置禁用登录项、或服务处于requiresApproval时，应用仍可能显示开启。现有catch只修复抛异常路径，不能表达“注册完成但待用户批准”。

建议以SMAppService.status作为当前状态，区分enabled/requiresApproval/notRegistered，恢复前台时刷新；需要批准时给出系统登录项入口。此项需在最终签名app路径稳定后实测，不能用CLI构建成功证明。

## 已看到的正确约束与仍需平台验证的范围

|主题|本次可确认|尚缺的实际验收|
|---|---|---|
|相机序列化|session修改、样本分析在同一queue；stop清handler；上层有cameraToken和measurement ID双层过滤|迟到旧output、快速preview/measurement切换、选择设备/拔出设备后的自动恢复|
|测量无帧|Core有measurement-no-frames；本次审查期间也增加training-no-frames|一次启动错误后能否释放lease、status是否稳定保留、首帧慢启动是否误杀|
|历史清空|HistoryStore actor串行检查generation且原子持久化，旧结果无法在clear之后写回|R1中跨MainActor/actor事务的新任务边界、R2退出drain|
|全部暂停|手动、睡眠、会话失活和自动规则使用不同reason，恢复一个reason不清其他reason|锁屏→解锁、系统睡眠→唤醒、自动规则消失但手动暂停保留、相机灯及时灭|
|自然休息|新增SampledIdleTracker镜像原版分钟级光标/键盘计数采样；tick向engine传idle|采样时钟与Core分钟检查的边界同步、睡眠恢复后的样本是否跨session重用|
|窗口标题自动暂停|读取真实CGWindow列表；设置页已说明隐私权限并提供系统入口|未授权/授权/撤权三种状态；当前读取不到标题时未发布独立能力状态|
|高频MainActor工作|每个camera观察创建MainActor Task；receive每次synchronize并更新多项Published、调用panel.show/orderFrontRegardless|实际FPS/CPU/主线程队列积压；可将全部检测样本送engine但将非关键UI发布限频，不能凭代码检查声称性能合格|
|浮层拖拽/多屏|按training/exercise/rest分键保存位置；恢复前检查完整frame是否落在某屏visibleFrame，超界钳回main|不同缩放、多屏负坐标、拔外接屏、跨屏拖动、全屏Space、VoiceOver/减少动态效果|
|浮层观察者|didMove回调另起MainActor Task读取当前key/frame|快速模式切换时应验证记录仍落到正确提醒类型；close后observer清理尚未显式进行，但当前close只走退出，未确认用户可见泄漏|
|窗口重开|最后窗口关闭不退出；菜单/系统reopen通过openWindow和activate恢复|真实关闭再菜单重开、Dock重开、系统启动隐藏/显示策略|

## 审查状态

R1/R2已将完整调用链及时发给主实现者；R3/R4/R5是需要对应平台夹具或实机条件验证的风险，不应冒充本轮观察结果。发现旧training无帧永久busy后，已看到Core加入training-no-frames，故本报告不继续把“永久busy”作为未修结论。最终应复查主实现后续改动，并以新的文件快照和实际日志关闭各项。

审查末读取的源码SHA-256（行号以正文所述调用为定位锚点；并行实现可能继续变更）：

- `Sources/EyeblinkApp/AppModel.swift`：`b66381d13941269013424a32a46aebe4d2d2eb6b901ff3bfc06cab13cdcfa164`
- `Sources/EyeblinkApp/Platform/CameraPipeline.swift`：`e7eabb10ba95826771e359790038155b35e840a230bacd5729060d70c2152da4`
- `Sources/EyeblinkApp/Platform/ReminderWindowController.swift`：`975048f44696323d969d6d9aa7bf32f3443c52859f22b73d4dc49f0299a7a3a8`
- `Sources/EyeblinkApp/EyeblinkApp.swift`：`6ebcd747bbf2be478b0319013bd9eef3d18651d921a43049e702ac37efab3925`
- `Sources/EyeblinkCore/EyeblinkEngine.swift`：`3d464ae3842d775247c08ac2dc90a387b5c95dfe119215b8d3240b258c64892e`
- `Sources/EyeblinkCore/Measurements.swift`：`c3c4fd6ca66fe49d19099411dc3713f6f880ddbde04b9d7e5d985de469cf2c60`

## 后续修复快照（2026-10-19）

主实现已加入：R1清空事务状态与相机暂停屏障；R2追踪pendingWrites并通过terminateLater等待；R3activeOutput identity检查与解绑delegate；R4cameraDidStart与独立启动watchdog；R5以SMAppService.status刷新enabled/requiresApproval并提供系统入口。窗口标题权限另通过CGPreflightScreenCaptureAccess显示能力状态，未自动申请权限。浮层close现在清理观察者，显示期间不反复orderFront。

这些是代码修复状态；R1/R2的平台并发夹具、R3快速设备切换及R5真实登录启动尚未实机验收，仍保持待验证。

## 数据事务回归

AppModel已改用`MeasurementHistoryCoordinator`，不再维护独立的generation映射、清空Task和pendingWrites集合。`HistoryStore.snapshotState()`原子返回records/generation/revision，append和clear成功后推进revision，旧快照不能回滚当前界面。clear先同步禁止新测量绑定、丢弃旧绑定，结束后才恢复相机；close同步冻结提交并等待保存、加载及清空任务。关闭期间的清空回调不再重开相机。

新增6项带门闩的异步回归，使用生产协调器和真实HistoryStore，控制旧读取、append、clear的返回顺序，无sleep：旧初始读取晚到、清空期间新测量、append旧快照晚于clear且不得通知、退出等待写盘、退出等待清空、清空失败恢复。随后增加2项实际AppModel生命周期回归，验证提交后才恢复相机、退出等待清空且晚到完成不得恢复相机。目前总计59项测试通过。AppModel夹具不创建窗口、不启用相机或系统监控，数据写入临时目录。R1/R2的数据协调边界已有可执行回归；OS termination与相机输出边界仍分别保留实机验证，不扩大为全部平台问题已准出。
