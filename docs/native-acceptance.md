# 原生重建验收进度 · 2026-10-22

当前是可运行的本机原生实现，完整复刻尚未准出。可运行产物：`build/Eyeblink.app`，最低macOS14；本机Apple Development签名，无Rosetta运行依赖。

## 已执行

当前N114/N115：识别确认窗口和睁眼学习避免累计漂移；运行错误/断开/系统中断与完成统一capture FIFO及终止门闩。206全量（151Core/55App）/119发布专项通过，新增8回归，当前单arm64签名包SHA前缀`2dd05ba84895`，129文件快照。设置、8历史、原软件文件及自定义icon保持。未启动真实相机，实机验收按用户要求暂缓；自然眨眼/旁人干扰/180秒合格记录和通知、物理断连与睡眠恢复仍待验。见[识别与稳定性设计](reliability-stability-design.md)及`evidence/native-tests/n115-native-build.json`。

此前多人环境增强N112/N113：单arm64签名包SHA前缀`7156ee0273b2`，198全量/107发布专项通过，53项相机增强测试含本轮15项目标跟踪回归。v3在明确锁定后继续跟踪原目标，旁人入镜不直接停止；目标丢失/重叠时暂停，重获清眼部校准。N111旧v2完整180秒覆盖率74.5364%未达85%，未入库；用户确认旁人入镜且无法保证单人，要求先离线完成。本轮只用模拟数据及公开图实际Vision，无真实相机/页面验收；8历史/设置/原软件文件及自定义icon保持。快照`evidence/native-tests/n113-native-build.json`；实机路过/交叉/人工计数和正式测量留待之后。详见[目标跟踪设计](primary-target-design.md)。

此前N096包（SHA前缀`9c2140ac563e`），快照`evidence/native-tests/n096-native-build.json`。在N093基础上仅修正应用菜单暂停后的文字为“恢复 Eyeblink”，已实操暂停→恢复→菜单文字复原；检测/Core/测试源码未变，145/54测试未为这一文字绑定重复运行。当前包真实预览30.2FPS、8条历史保持、从应用菜单正常退出并完成相机/存储收尾。右侧状态图标菜单和独立窗口关闭停留仍待验收。见`evidence/native-ui/95-application-menu-pause-label.txt`、`evidence/native-ui/96-menu-package-final-smoke.txt`。

最新检查点（N091–N094，2026-10-21）：原Model的12组quarter边界中，6组空尺寸实际抛cv::Exception（-215/resize），另外6组正常无脸；仅分析调用桥捕获，未证明原应用级崩溃或控制器终态。以此发现并修正新版持续处理错误会在180秒后保存“零眨眼”的缺陷：失败现会停止并取消本次测量，排队帧及晚到完成不保存。5项新增回归使总计达到145 Swift、54 release通过；正常52帧像素和重开事件保持。已重建并核验当前arm64签名包，真实预览30.0FPS、暂停恢复、到期训练无脸停止及正常退出通过，8条历史/设置/原5文件逐哈希保持。当前没有人脸/眨眼成功观察，真实180秒成功入库/通知及物理处理异常重连继续待验收。见`evidence/native-ui/91-shipped-zero-quarter-exception.txt`、`92-processing-failure-zero-result-fix.txt`、`93-processing-failure-native-package.txt`、`94-processing-package-live-preview.txt`；当前包快照为`evidence/native-tests/n093-native-build.json`。

- Swift：206项全量测试通过，0失败（151项Core、55项App）；发布专项119项通过，无跳过。新增8项覆盖目标确认累计位移、渐变yaw/pitch学习与稳定恢复、平台故障/完成顺序、重复/旧租约终态和中断通知；已有调度/仲裁/存储/原检测链/公开图Vision回归保持。日志：`evidence/native-tests/reliability-stability-full-swift.log`及`reliability-stability-release.log`；旧检查点独立保留。
- 构建与包：release编译、codesign严格校验通过。包内仅1个Mach-O，arm64；所有动态依赖来自macOS系统。检测C++代码静态链接；4份第三方许可文件逐字节核对。测试夹具资源包不进入App，校验脚本拒绝Tests.bundle。源码快照及SHA：`evidence/native-build.json`。
- 检测独立契约：C光流37项检查通过UBSAN；人脸公开图arm64与x86参考22脸逐整数一致；dlib8夹具40关键点一致。上述参考夹具本身不作为原App实际函数对照；后续独立取得原始CNN代码相同副本的单图22脸/330整数输出，与arm64精确一致，见`evidence/native-tests/original-cnn-comparison.json`。该函数对照仍不覆盖完整眨眼路径。
- 真实相机：FaceTime摄像头预览实际识别到眨眼，约27–40FPS；暂停相机后停止预览，恢复后重新采集。未保存相机图像。
- 原版复刻分支早期完整测量：手动和自动两次180秒测量均完成并入库，分别记录15与24个检测事件；正常退出/重启保留记录。没有把检测次数等同人工真值准确率。
- 中文/英文即时切换与语言持久化；开发身份签名更新后相机授权保留。
- 清空历史确认框及取消路径，现有记录保留；真实UI没有执行不可恢复删除。
- 进程规则自动暂停→添加手动暂停→移除自动规则→手动暂停保留→手动恢复。临时关键词已移除。
- 眨眼/休息及四种眼操浮层预览可见；远眺、挤眼眨眼、左右转眼、旋转眼球内容和Escape关闭均已观察。休息预览推迟按钮已观察，预览不作为生产5分钟推迟准出。
- 关闭主窗后进程驻留，重新绑定/打开恢复窗口；菜单栏动作尚未全部逐项录制。
- 独立历史窗口打开、最大化已观察；数值参考线、均值线和日期入口可见。图表点击不同位置显示对应记录，用户实测确认悬停进入显示日期/频率/时长、移出消失，旧悬停失败项已修复。
- MGD真实生产提醒：临时打开MGD，保留30秒间隔；用户保持鼠标在主窗并自然眨眼，确认提醒出现且随眨眼关闭。已恢复MGD关闭，证据`evidence/native-ui/27-real-mgd-blink-dismissal.txt`。
- 休息语义修正：移除只影响显示的独立“每次休息时长”和倒计时，按原版连续空闲条件完成；关闭自然休息抵扣时，该空闲条件仍适用且可编辑。旧重建版设置兼容性已有回归。证据`evidence/native-ui/28-rest-semantics-fix.txt`。
- 登录项：真实UI开启后，系统sfltool记录为enabled/allowed；关闭后重新读取为disabled/allowed，Generation由1变2，原关闭状态已恢复。首次清理读取超时，重试取得终态；未执行注销/重新登录启动。证据`evidence/native-tests/login-item-registration.json`。
- 关于及许可入口：原站各链接可见，许可按钮实际打开包含4份许可的应用资源目录，随后关闭本次Finder窗口。dlib许可已改为随源码保存，首次构建不再依赖可选参考缓存。证据`evidence/native-ui/29-about-and-licenses.txt`。
- 5分钟资源采样完成：31次、每10秒一次；进程RSS约65–218MiB，末次约79MiB；ps的CPU估计范围1.7–173.0%。它不是功耗、长期泄漏或帧耗时验收。原始记录`evidence/native-tests/runtime-resource-smoke.json`。

逐操作账本：`catalog/native-observations.json`。原版体验仍独立保存在`catalog/observations.json`，不相互替代。

最新补证：真实生产休息到期后点击“5分钟后提醒”，观察完整五分钟倒计时及再次进入休息；用户确认随后点击“跳过本次”。这条链路已闭环，未代替连续空闲完成验收。证据`evidence/native-ui/30-production-rest-snooze-and-skip.txt`。

固定周期修正：移除原版没有的测量/眼操时长编辑项，恢复测量30分钟一次、每次3分钟、眼操19分钟；休息/眼操启动重置20秒训练timer。3项回归先失败后通过，新包真实UI已核对。证据`evidence/native-ui/32-fixed-schedule.txt`。

统计日期实操：自定义截至前一天无记录、恢复今天显示5条、起止同为今天仍显示5条、明天范围为空，最后恢复近7天。没有修改历史数据。午夜/夏令时边界仍需额外数据验收。证据`evidence/native-ui/33-date-range.txt`。

相机会话：补齐运行时错误和所选设备断开通知，按会话代数拒绝排队旧错误；明确选择的相机断开时不再自动改用第一台相机。4项真实NotificationCenter投递回归通过，另补前次训练失败→新预览状态清理回归。真实相机预览开启/停止/重开收到帧且未误报断开；物理拔线等平台场景仍待验收。证据`evidence/native-ui/34-camera-session-failures.txt`。

退出补证：真实模态RunLoop中待写历史收尾先失败后通过；已调整后台存储及模态完成交付。随后定位实际采集停止请求在帧队列中等待，进一步诊断一次等待约40秒。会话启停与有序帧分析现分属两条串行队列，保留单个相机仲裁。真实预览期间菜单退出和暂停→恢复→Command-Q的收尾分别约0.158秒、0.096秒，随后确认进程退出；5条历史字节未变。本机复现的退出延迟缺口已取得修复证据。见`evidence/native-ui/35-modal-termination.txt`及`36-camera-session-queue.txt`。

完成通知：现有系统授权已读取为允许，未重新申请；测试通知由系统deliveredNotifications回读确认送达通知中心。设置入口已真实打开正确面板，系统选项未改；通知开关关闭立即禁用测试并失效旧任务，已恢复原开启偏好。4项新回归覆盖实际AppModel关闭/清空/退出的迟到通知等边界。未直接捕获横幅，也未将测试消息代替新的180秒测量完成链路。证据`evidence/native-ui/37-measurement-notifications.txt`。

生产通知补证：新增独立生产送达状态后，真实运行完整180秒测量，记录6→7，系统按该测量记录UUID回读到通知，界面显示“最近一次测量通知已送达通知中心”。本轮没有发送测试通知，旧记录均保留；80项测试通过。完整生产链路已闭环，直接横幅仍未观察。证据`evidence/native-ui/39-production-measurement-notification.txt`。

原版数值范围已恢复：训练2–60秒、休息间隔15–80分钟、空闲阈值2–9分钟。实际UI越界输入分别回到端点，休息步进50→51→50，最终恢复30秒/50分钟/3分钟。3项新增回归通过。证据`evidence/native-ui/31-original-control-bounds.txt`。

训练提醒位置：用户手动拖动顶部空白区并再次预览，确认可以移动且新位置保留。本次只覆盖同一会话训练预览，跨进程重启与眼操/休息浮层继续待验收。证据`evidence/native-ui/38-training-reminder-manual-drag.txt`。

正式休息空闲结束尝试：实际15分钟倒计时到期后回到下一周期，但未捕获浮层的出现/消失，用户对是否手动结束不确定，故仍未准出。临时设置已全部恢复。证据`evidence/native-ui/40-rest-idle-inconclusive.txt`。

自动暂停按需读取：空/空白规则不再枚举进程或窗口；清空规则仍清除旧自动原因。新增provider调用次数回归先失败后通过，签名包真实自身进程暂停→手动叠加→移除规则→手动恢复已闭环，设置全部恢复，窗口权限未变。证据`evidence/native-ui/41-lazy-pause-providers.txt`。

原函数对照补证：原Model完整尺寸缩放/CNN/选脸函数在公开图和纯黑图、各6个上一脸条件下，与发布用arm64适配器12组输出一致；原detectEyes用8组公开关键点ABI夹具得到48个中心/宽度数值，与生产EyeGeometry一致。Core新增2项回归，release优化下2项也通过；未调用原shape_predictor，仍不是完整眨眼链等价证明。证据`evidence/native-ui/42-face-selection-and-eye-geometry.txt`。

真实无脸测量：关闭训练以隔离提示后，依次观察到测量中/正在启动→无脸/28.5FPS→明确测量停止；立即测量入口恢复，历史8条字节SHA不变。训练恢复后正常退出，进程已消失。它不覆盖完全无帧、低FPS、物理断连或正向准确率。证据`evidence/native-ui/43-real-no-face-measurement.txt`。

休息结束原因：Core在实际开始/结束分支发出固定类型事件，经现有效果消费入口写入本机RestLifecycle系统日志。3项新增回归区分空闲完成、手动跳过、推迟、暂停、关闭与相机预览打断，不改变15分钟/3分钟/5分钟生产时序。最新签名包启动及正常退出通过；后续已在N049恢复正式空闲结束日志；N040原次尝试仍保持不确定。证据`evidence/native-ui/44-rest-end-cause-trace.txt`。

实际原预测器补证：已在main前的隔离原代码副本调用实际读取器和shape-predictor，8张固定灰度图/明确矩形的40点与新版Swift完全一致，新增回归逐图核验输入SHA，release优化下6项预测器测试也通过。首次错误灰度对象布局的失败保留，修正后才计入结果；原5个用户文件未变。见`evidence/native-ui/45-shipped-predictor.txt`。

光流统计兼容修复：原函数对照证明旧重建始终开方不符原variance<=1e-8保留分支，9组仅4组精确一致。已改为原两遍计算、列优先和独立Float乘加；9/9的mean/dispersion精确一致，UBSAN及27项C光流契约通过。该阶段未包含原Farneback；后续N051补上6组ROI对照，整条眨眼序列仍待验证。见`evidence/native-ui/46-flow-dispersion-fidelity.txt`。

预览打断周期恢复：已按原enableLivePreview分发表复用完成处理，打断正式休息重置休息/眼操，打断眼操推进下一动作并重置间隔，隐藏简单提醒重启训练间隔；修复前3项回归8个断言失败，修复后全套90项通过。尚未新增相应实机打断链路。见`evidence/native-ui/47-preview-interruption-cycles.txt`。

灰度组件对照：按原Model参数调用实际原OpenCV cvtColor/blur，3个确定颜色输入（含奇数尺寸、填充stride、单像素）的153520像素、307040输出字节与生产BGRA灰度接口完全一致，UBSAN通过；调试器收尾警告保留并确认进程消失。仍不是整条Model循环/ROI/Farneback序列证明。见`evidence/native-ui/48-shipped-gray-blur.txt`。

中断恢复补证（10月21日）：原15分钟正式休息日志含17次开始、2次人工推迟及15次空闲完成；首条明确自动结束发生于10月19日20:08:51，idle188.533935秒，未混入跳过/推迟分支。设置经UI完整恢复、历史8条字节不变；当时浮层收起画面仍未直接捕获。见`evidence/native-ui/49-rest-idle-log-recovered.txt`。

当前签名包复核：纳入最新光流与预览打断修复，10月21日重跑90项Swift、9组光流和3图灰度对照均通过。模型/图标SHA、Bundle信息、Package.swift编译选项纳入包校验；真实相机约37–39FPS，观察到1个检测事件，授权保留、预览不入统计、正常退出。见`evidence/native-ui/50-latest-package-live-smoke.txt`。

原Farneback数值修复：N051直接调用旧版OpenCV实际函数，6组固定灰度ROI包含奇数尺寸、上下/对角移动和金字塔。初始4组仅1/4逐字节相同；全局禁止FMA后扩大到6组仍5/6，最终固定SHA源码补丁保留半尺寸Float的四lane成对累加/标量尾部，达到6/6、39684个Float及mean/dispersion精确一致。另直接调用旧版resize验证32组通道1/4、填充stride、短行/尾部，旧库18/32→补丁32/32，UBSAN通过。没有放宽误差或用新版替换原预期。见`evidence/native-ui/51-shipped-farneback-float-resize.txt`。

光流修正包实测：三静态库指纹纳入重新链接条件，release实际重新Linking后签名/严格包校验通过；90项Swift0失败，灰度3图、统计9组及原CNN22脸结果仍精确一致。新包真实预览34.4FPS/1→32.3FPS/4检测事件，正常退出，设置与基线相等、8条历史及原版5个用户文件不变。见`evidence/native-ui/52-farneback-package-live-smoke.txt`。相机画面没有截图或保存，检测事件不是人工真值准确率。

时序原码修正：N053实际执行原mergeBlinks及两眼扫描块，纠正先前静态比较方向（原为ratio<.3）、首候选.25秒参照和跨相机重开的参照保留。13段173帧、22候选与8候选对，逐帧报告事件/计数/累计时长和候选元组均精确一致，-O契约通过。实际原码可同帧产生.375/.3125两事件，现已从相机到测量统一传列表，新增生产15秒启动/180.001秒边界回归验证不漏不重复。见`evidence/native-ui/53-shipped-temporal-sequences.txt`。

测量算术补证：N054直接执行原输出范围，修正“先除count再乘1000”及频率Float转换；6/6固定输出一致，包含原99ms而旧重建100ms的舍入顺序例。修正前5断言失败，修正后全套95项0失败。见`evidence/native-ui/54-shipped-measurement-arithmetic.txt`。

本次离线包：N055重新构建/签名/严格检查arm64包，源码快照最新。按用户息屏安排，本轮不启动界面/摄像头，不检查或改变锁屏/显示状态；设置、8条历史和原版5文件均未变。N052真实相机证据属于前一包（快照已归档`evidence/native-tests/n052-native-build.json`），不能代替新时序/统计算术包的真实采集验收。亮屏后需要新预览、MGD/普通提醒以及完整180秒测量→保存→通知。见`evidence/native-ui/55-temporal-offline-package.txt`。

ROI连接补证：N056实际执行原Model的ROI计算、原OpenCV子Mat/Farneback及原统计串联，10组边界/半像素/奇数宽/极小/零面积/金字塔输入与生产共用eye_region/sample_flow、Swift normalizer精确一致，UBSAN通过。见`evidence/native-ui/56-shipped-roi-flow-statistics.txt`。

首帧衔接修正：N057用5张固定640×480彩色帧执行原灰度准备、首次无前脸跳过、ROI/flow/stats和Mat交换；原首脸缓存未经模糊的current。旧新版warmup多一次blur，严格对照仅3/5；移除后5/5双眼特征和5缓存SHA（1536000字节）精确，27项C契约及10组ROI对照通过。原Model预读模糊图在首次无前脸分支被丢弃，不能据此给首个有脸warmup加blur。见`evidence/native-ui/57-shipped-gray-flow-warmup.txt`。

当前离线包N058：重编译C模块、95项Swift0失败、release签名及arm64/系统动态依赖/模型许可/源码快照校验通过；无UI/相机/显示状态访问，原5文件、设置与8条历史不变。N055旧包快照已归档。该阶段没有新包的真实预览或测量验收；当时待补的暖机到temporal正向事件现已由N059补上7帧给定眼几何的路径，完整归一化/CNN/dlib/追踪和无脸恢复继续待补。见`evidence/native-ui/58-gray-flow-offline-package.txt`。

正向事件衔接修正：N059使用7张固定彩色眼区patch移动帧，实际执行原灰度/前脸门槛/ROI/flow/stats、扫描/合并及Mat交换，在第5帧捕获.1875秒事件。生产段原先不向temporal传EF_WARMUP，导致第一个有效运动被数组首元素规则跳过；新回归5断言失败后，通过传递暖机零基点修正。实际CEyeFlow的原生特征接入-O生产CameraMotionAnalysis/Core后，7/7缓存SHA/特征/状态/事件/count/total精确；新增App用例debug/release通过，全套96项0失败。见`evidence/native-ui/59-positive-flow-motion-handoff.txt`。

当前N060包：稳定签名arm64，严格包/源码快照验证通过，新增AppTests资源未进入App；本轮仍未启动UI/相机/屏幕状态访问，设置和8条历史、原版5文件未变。N058旧包快照已归档。给定眼几何和合成时钟的正向事件不是完整相机/CNN/dlib/追踪或真实准确率证明，当前包实机预览/提醒/180秒测量继续等亮屏。见`evidence/native-ui/60-motion-handoff-offline-package.txt`。

## 仍需闭环

1. 训练浮层手动拖动及再次预览保留已由用户确认；跨进程重启位置对照、眼操/休息拖动仍待补；自动化多窗口输入曾出现noWindowsAvailable/elementHasNoFrame，失败尝试不计PASS。图表悬停及四种眼操预览已取得后续成功证据。
2. 普通交互模式真实眨眼关闭及鼠标移入关闭；真实休息自动收起浮层的同时视觉观测、自然休息与睡眠边界；正式空闲结束原因已由N049日志闭环。MGD眨眼关闭、真实到期→推迟5分钟→再次到期→人工跳过已取得实测结果。
3. 多屏/全屏Space、断连相机、低照/多人/低FPS及系统睡眠/会话恢复；窗口规则授权/撤权（用户明确暂不授权，保留待验收）；真实重新登录后的自动启动。登录项系统注册/注销链路已验证。
4. 清空/退出的数据协调已有6项Core及2项实际AppModel门闩回归，另补真实模态RunLoop存储收尾；本机采集中停止/退出延迟已修复并取得两条真实链路。仍需冷启动中途退出、实机OS退出、迟到output及设备快速切换注入。AppModel夹具使用临时目录，不创建窗口、不启用相机或系统监控。
5. 原始CNN、12组选脸、8组眼区、8组预测器、9组光流统计、6组原Farneback、32组Float缩放、13段原时序块/8候选对及6组统计算术已对照；原Model在给定眼几何上的10组ROI/flow/stats和5彩色连续帧灰度/首次脸门槛/交换已对照；N063已补6条50帧固定图像CNN/dlib/flow到两次正向事件精确对照；N065已补22组归一化及7帧原始1280尺寸正向衔接；原始采集和真实时钟、更多边界序列、CPU/内存/功耗长期运行、目标最低系统macOS14实机仍待验证。当前仅在本机macOS26运行。
6. 真实180秒测量→落盘→自动通知系统送达已通过N038；仍未直接捕获横幅，不覆盖或更改系统专注/共享屏幕等展示选择，拒绝/撤权路径继续待验收。

按用户明确选择，旧研究上传、Beta/云更新服务暂不接入，不计入本机功能准出。原Mac空方法/不可达旧授权分支继续保留在功能矩阵，不虚构有效功能。

用户选择暂不授权屏幕录制。新版提供明确的窗口标题授权入口及用途说明，但未点击申请按钮、未变更该权限；窗口标题自动暂停保留待验收。进程关键词暂停的既有验收独立有效。

2026-10-21跟踪连接检查点：N061实际原灰度/CNN/预测器/复用/交换14帧，发现非四帧重获人脸应先用CNN粗眼位置、等四帧再精修；新增回归12断言失败后修正，12组有脸双眼几何debug/release精确，含两次重获、两次无脸和跨序列重置。首次半尺寸公开图因脸宽<100未覆盖跟踪，保留失败尝试后改固定640×480裁剪；这不是相机归一化证明。N062全套97项及新签名arm64包离线验证，未访问UI/相机/显示状态；当前包实机仍待亮屏，完整tracking→flow→event及更多输入边界继续待补。见`evidence/native-ui/61-shipped-eye-tracking.txt`、`evidence/native-ui/62-eye-tracking-offline-package.txt`。

2026-10-21完整固定帧连接检查点：N063执行原CNN/dlib跟踪→灰度/前脸门槛/flow→temporal→交换6序列50帧，含47组有脸眼几何、3帧无脸和两次.1875秒正向事件。旧新版遇无脸即清flow/时序产生7断言失败，改为每帧缓存、按上一脸决定flow、保留时序后，debug/release逐帧严格一致；全套98项及37项C UBSAN通过。遮挡样本仍被CNN选中，仅计遮挡证据，不能声称跨丢脸候选已闭环；组件探针无脸超时明确禁用，不代替生产实机时序。N064当前签名arm64包离线更新，无UI/相机/显示状态访问；真实链继续等亮屏。见`evidence/native-ui/63-shipped-tracked-motion.txt`与`evidence/native-ui/64-tracked-motion-offline-package.txt`。

2026-10-21原始尺寸输入检查点：N065实际执行原首帧Float缩放比例/后续缓存比例/resize/gray，22组25518080颜色灰度字节、系数bits和尺寸精确；144项归一化C UBSAN检查通过。新增7张公开正向图放大到1280×960，原缩放后BGR/gray SHA与N063640×480边界一致，新版原始输入→CNN/dlib/flow/event用例31失败断言→debug/release通过，99 Swift0失败。设备预设改为加输入后canSet逐项选macOS支持的VGA/high/medium/low；物理非VGA采集仍待验收。N066签名arm64包离线更新，无UI/相机/屏幕状态访问。原tick采样点/读取与更多维度边界仍待补，真实链等亮屏。见`evidence/native-ui/65-shipped-frame-normalization.txt`与`evidence/native-ui/66-frame-normalization-offline-package.txt`。

2026-10-21时间采样位置检查点：N067实际执行原缩放终点→getTick/store、灰度前和整数差/频率计算，3组顺序/界限与dt槽验证通过。新版clock移到normalizer成功后，与运动/观察时间/FPS共享；C缩放失败不消费时钟回归1断言失败→debug/release通过，100 Swift0失败，release3项frame stage与原22归一化/50帧门槛均通过。N068签名arm64包离线更新，无UI/相机/屏幕状态访问。原Integer tick数值精度、预读基准/首次31delta窗口和低FPS同帧事件顺序继续待补，不把取样位置等同完整计时或实机准出。见`evidence/native-ui/67-shipped-frame-clock.txt`与`evidence/native-ui/68-frame-clock-offline-package.txt`。

2026-10-21整数间隔检查点：N069以原3组实际tick差建立6失败断言后，使用同一原始clock快照保留Integer差，再除实际频率，生产FrameTimestamp-O三组及近Int64上界短间隔精确。显式间隔已传入运动/scanner/FPS，绝对秒仅供调度观察；原生clock本机24MHz与调度基准区间检查通过，不硬编码旧Rosetta1GHz。reset/invalidate新时基回归、107 Swift和13项release通过，原13时序段173帧22候选、50图像及7原始尺寸正向均保留。N070签名arm64包离线更新，无UI/相机/屏幕状态访问。预读基准/首次31delta窗口、FPS原求和/事件顺序、物理捕获与完整测量仍待验收。见`evidence/native-ui/69-integer-frame-time.txt`与`evidence/native-ui/70-integer-frame-time-offline-package.txt`。

2026-10-21FPS/预读检查点：N071直接执行18组原FPS门槛/31槽/环绕/均值倒数及分支，发现count/sum合并使4组多1，改原sum/31→1/mean后debug/release/-O精确。新Model预读帧号0、无CNN/dlib/flow调用已实测；native现在先prime尺寸/时基，再从第一分析帧记间隔，3失败断言→通过，黑预读后正向7帧仍精确。ready单独通知不参与测量样本；1/8秒无分析帧超时与无入库回归、FIFO33元数据桥通过，112 Swift/21 release0失败。N072签名arm64包离线更新，无UI/相机/屏幕状态访问。这里只验证fresh Model预读及组合原块，跨重开状态/同帧低FPS事件/真实捕获仍待验收。见`evidence/native-ui/71-shipped-fps-startup.txt`与`evidence/native-ui/72-fps-startup-offline-package.txt`。

2026-10-21重开/低FPS检查点：N073实际原3组终止清理/预读初始化证明清人脸、扫描归零、旧merger候选保留；原普通帧返回跳过终止清理。2组32帧固定特征均先在frame31合并.1875再得FPS9，非预览终止、预览继续；实际blinkDetected消费槽仅预览转向userBlinked，训练成功在下一轮，因此未据内部顺序臆测性提前native Core sample。-O生产64帧events/FPS精确，相关release9项通过。无生产修改/重复构建，当前N072包与源码、设置/8历史/原5文件保持；完整Qt送达/真实低FPS重试和设备重开仍待验收。下一离线重点为更多尺寸/CNN最小输入/无脸超时与错误边界；当前包UI/相机等亮屏。见`evidence/native-ui/73-shipped-reopen-low-fps.txt`。

2026-10-21小尺寸CNN检查点：N074实际原Model quarter缩放/CNN/选脸29组（19黑图/10公开裁剪）证实quarter63有效、below63正常0脸；原full256/quarter64包装guard有27/22组不符，新增2回归51失败断言→修正后114 Swift、23 release通过。BGRA/原smallBGR共58结果的count/置信度/rect/landmarks/选脸精确，生产prime→640x255有脸与640x240无脸不再抛错，UBSAN及10非法输入通过。N075新签名arm64离线包/源码快照校验，设置/8历史/原5文件保持，无UI/相机/屏幕状态访问。下一步仍为quarter零尺寸/原异常、无脸超时和小图运动序列/平台晚到回调等离线边界；实机非VGA与当前包预览/提醒/180秒测量等待亮屏。见`evidence/native-ui/74-shipped-cnn-dimensions.txt`和`evidence/native-ui/75-cnn-dimensions-offline-package.txt`。

2026-10-21无脸毫秒检查点：N076实际原9计时重置条件、QtCore12纳秒→整数毫秒和Model24门槛分支，确认严格>1000/8000意味着1001/8001ms才终止。新增Core2项8失败断言→修正sample边界，首轮相加顺序残1失败（debug/release）→先合并等待时长后通过；116 Swift（91Core/25App）、25 release及原29CNN/18FPS门槛通过。连续无脸不重启、有脸恢复后再丢失重新计时、取消不入库均回归。N077新签名arm64离线包/源码快照通过，设置/8历史/原5文件保持；没有UI/相机/显示状态访问。native tracking前frame时间与原tracking后no-face timer相位仍待单独核对，不能据整数规则宣布完整时钟等价；当前包实机验收继续等亮屏。见`evidence/native-ui/76-shipped-no-face-milliseconds.txt`与`evidence/native-ui/77-no-face-timeout-offline-package.txt`。

2026-10-21无脸取时相位检查点：N078原2帧真实blackCNN证明frame tick→tracking完成→无脸timer首start/次retain在flow之前；首探针缺预读gray的boxFilter失败保留，补真实初始化后通过。生产新增posttracking faceClock/原始FrameTimestamp，经元数据FIFO/AppModel到Core共用FaceAbsenceTimer，保留整数差/实际频率，frame dt/FPS/光流时间不变。5回归10失败断言→121 Swift（94Core/27App）、30 release通过，FIFO33和近Int64边界毫秒通过；50原固定帧显式faceClock仍精确。N079新签名arm64离线包/源码快照通过，设置/8历史/原5文件保持，无UI/相机/屏幕状态访问。下一离线优先解决原超时flow前终止与native当前Core在flow后判断的顺序/merger候选影响及timer单一所有权；不把本次时钟组件通过视为完整取消链或实机验收。当前包UI/相机继续等亮屏。见`evidence/native-ui/78-shipped-no-face-clock-phase.txt`与`evidence/native-ui/79-no-face-phase-offline-package.txt`。

2026-10-21无脸终止顺序检查点：N080实际原构造器/注入整数毫秒四组分支均停在flow前，候选/累计未改；native改为CameraFrameAnalysis独占tracking后raw无脸时钟，到期在flow/scanner前抛错并锁存至新租约，FIFO向Core送显式failure取消，移除Core重复计时。新7回归先16失败断言后通过，含实际固定公开/黑帧恢复、禁用预览、下一租约对照、晚到/旧/重复failure；128 Swift（98Core/30App）、37 release通过，原50图像仍精确。初全量3失败来自旧sample超时夹具，改相同时间显式failure注入后通过，日志保留。N081已构建稳定签名arm64包并严格验证、保存数据不变；用户已亮屏，正在验证本包实机。原probe停在release/error前，native未LLDB计数C函数；完整队列/物理释放及主ticker可能早于worker失败而保存的竞态仍待补，不宣布完整复刻。见`evidence/native-ui/80-shipped-no-face-termination.txt`与`evidence/native-ui/81-no-face-termination-package.txt`。

2026-10-21亮屏实机检查点N082：N081实际预览31.9FPS，无脸0事件；无脸场景立即测量从0%转停止，8条历史不变，AX合并no-face/no-frames原因不能细分。正常退出日志确认相机队列及写盘收尾，重开设置保持；应用菜单暂停/快捷键恢复通过。自动拖动保存坐标未变，仍待验证；用户暂不方便完整180秒测量，成功入库/通知待续。详见`evidence/native-ui/82-current-package-live-partial.txt`。

2026-10-21测量完成顺序N083/N084：实际原deadline4/模式2分支确认180001ms且下一read前判断；新9回归先8断言失败后修正。capture队列在消费下一buffer前检查raw期限，经FIFO显式完成；主ticker与normal sample只更新进度/事件，不再提前保存。失败/完成锁存、近Int64最后纳秒、重prime不重启、旧/重复拒绝及实际Dispatch时序回归通过。137 Swift（102Core/35App）、46release及旧50图像等门槛通过，新稳定签名arm64包已验证。原probe无read/release/Qt成功执行，native callback驱动已取buffer，真实平台延迟/完整180秒成功仍待验收；详见`evidence/native-ui/83-shipped-measurement-deadline.txt`、`evidence/native-ui/84-measurement-deadline-package.txt`。

2026-10-21当前包N085：N084真实预览29.9FPS，暂停后系统stopRunning/分析队列收尾，恢复瞬时158.2后稳定30.1FPS，0检测事件；仅AX未截相机图像。关闭预览使到期自动测量排队，随后实际noFace日志及stop收尾可见，最终立即测量/8条历史，全部数据保持。purpose未记录，不能以约8秒墙钟差替代精确超时验收；后续手动pause时可能已失败，不计受控取消。成功180秒/历史追加/通知仍按用户选择待续，见`evidence/native-ui/85-current-package-camera-resume.txt`。

2026-10-21恢复首帧扫描N086/N087：原10cases/11sessions/92固定特征帧中，24warmup四零写入后跳过双眼scanner，保持计数/候选/扫描状态；之后控制组frame5、一帧warmup后frame6、三帧后frame8发.1875。待提交时实际重置扫描块，下一段仍计一次。新2回归先76断言失败，修为保留同一有序零样本/索引/原始间隔，仅EF_OK时扫描；139 Swift（102Core/37App）和48release、原50图像仍通过。新稳定签名arm64包已验证、原5文件/设置/8历史保持。普通行直接scanner、warmup注入previous-face空，不是完整像素/物理循环；长10000槽预览与完整180秒仍待验收。见`evidence/native-ui/86-shipped-warmup-scanner.txt`、`evidence/native-ui/87-warmup-scanner-package.txt`。

2026-10-21 N088新包冒烟：N087真实预览30.1FPS/0检测事件，关闭后明确待机；统计仍8条，CmdQ正常退出且当前进程消失，匹配本包日志stopRunning/分析队列/shutdown/reply均完成。设置/历史/原5文件保持，未保存相机像素。它只验证当前包可采集/收尾，N086待提交候选跨丢脸恢复仍需真实像素连续对照，180秒成功/通知按用户选择待续。详见`evidence/native-ui/88-warmup-package-preview-smoke.txt`。

2026-10-21 N089/N090连续图像：有限14遮罩找到9组实际CNN丢脸/恢复反例，固定公开像素5cases/6sessions/52帧实际原tracking/flow/scanner/swap与同Model脸清理/预读重置对照；46眼区、6无脸、12warmup、4个.1875事件严格一致。单帧恢复frame6、三帧frame8才发，待提交时重开后下一段frame5仍计一次。新生产图像回归同时用旧scan反事实确认提前/重开少计，不是全零用例；140 Swift（102Core/38App）、49release通过。没有产品源改动，48个源/二进制/运行资源与N087相同，严格签名核验后保留原包，N088冒烟仍只证明该产物可启动采集收尾。探针无物理read/timer/Qt控制器，时间1/32/超时关闭仅属组件隔离；物理摄像头/长10000槽/180秒成功仍待验收。见`evidence/native-ui/89-shipped-warmup-continuous-pixels.txt`和`evidence/native-ui/90-warmup-pixels-unchanged-package.txt`。


N107正式测量尝试：当前N105包从0%推进至47%/58%，期间单眼就绪30FPS，随后因质量不足结束且未入库，旧8条逐对象保持。用户的“可以了”仅确认短测可用，不能覆盖这一失败。已复现FIFO挤掉验证校准和姿态窗口边缘抖动，后续补保留/有限迟滞；85%覆盖率门槛保持，不制造低质量测量通过。
