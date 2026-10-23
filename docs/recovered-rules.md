当前补证N091/N092（2026-10-21）：实际原12组quarter边界，6组空轴在CNN前抛出cv::Exception（-215、!dsize.empty()、resize），越过Model到仅分析C++捕获器；6组正尺寸正常无脸。未运行原main/Qt控制器，原应用是否崩溃未知。新版原通用catch会将错误持续喂成无效样本，在受控完整180秒后错误生成零眨眼测量；现以同一有序CameraFrameRun统一ready/分析/FPS/期限/失败，处理错误立刻终止取消，排队/晚到完成不保存。新增5回归，145 Swift/54 release通过；正常52帧元数据和跨重开事件保持。当前N093签名arm64包真实30.0FPS预览/暂停恢复/无脸训练停止/正常退出由N094补证，但实际AVFoundation到AppModel故障注入、物理释放重连与180秒成功仍待验收。见`evidence/native-ui/91-shipped-zero-quarter-exception.txt`及`evidence/native-ui/92-processing-failure-zero-result-fix.txt`。以下历史检查点的“待补”以本段新范围为准。

当前补证N089（2026-10-21）：公开像素5cases/6sessions/52帧，实际原CNN/dlib/flow/scanner/交换及一次同Model脸清理/预读重置，证明N086提前扫描的反例在图像链可达。46眼区/6无脸/12warmup/4事件与生产精确，140Swift/49release通过；无产品改动，N087签名产物字节保持。它仍不覆盖物理read/超时/Qt或AVFoundation排队控制器和准确率，见`evidence/native-ui/89-shipped-warmup-continuous-pixels.txt`。

当前新增检查点N086（2026-10-21）：原92帧固定特征证明无上一脸时写零样本但跳过scanner/merger；下一正常帧才扫描。修正native提前输出及跨重开少计，2回归先76断言失败后139Swift/48release通过。保留零基准/原始间隔，不清历史；实际待提交候选的像素丢脸恢复和物理全链仍待验收。见`evidence/native-ui/86-shipped-warmup-scanner.txt`。下列旧检查点保留当时范围与限制，后续N080/N083已分别修正无脸终止顺序和测量完成所有权。

最新无脸取时补证（N078，2026-10-21）：原2帧实际gray/CNN后timer首start/次retain、flow前顺序已观察；native另采posttracking rawFrameTimestamp并贯通Core，5回归10断言失败→121 Swift/30 release通过，帧间隔和原50图像结果不变。首探针未初始化prevgray失败保留。仍须解决原Error4的flow前终止与native当前flow后判断/merger候选影响，不宣称整条取消路径或物理camera等价。见`evidence/native-ui/78-shipped-no-face-clock-phase.txt`。

最新测量顺序补证（N083，2026-10-21）：原Model模式分支2组与注入整数elapsed4组证明180001ms在下一read前完成；native改由有序capture边界消费下一buffer前检查raw期限，FIFO显式完成，Core主ticker/normal sample不再独立保存。9新增回归先8断言失败后137Swift/46release通过。实际驱动callback与同步read仍有平台差异，完整180秒成功继续待验收。见`evidence/native-ui/83-shipped-measurement-deadline.txt`。


最新无脸毫秒补证（N076，2026-10-21）：实际原9重置门槛、QtCore12 ns→整ms与Model24比较确认严格>1000/8000，即1001/8001ms才终止；native sample直接比较秒会提前不足1ms取消，2回归8失败断言后修正。首轮加法顺序残1失败，先合成等待时长再加起点后116 Swift/25 release通过。无帧/startup watchdog不改；native pretracking时间与原posttracking no-face timer相位仍待核对。见`evidence/native-ui/76-shipped-no-face-milliseconds.txt`。

最新小尺寸CNN补证（N074，2026-10-21）：原Model完整quarter resize/CNN/选脸29组，quarter63仍有效选脸、below63为正常0脸；新版包装层256/64硬门槛误拒绝27/22组。2回归51失败断言→修正后114 Swift/23 release、58 BGRA/BGR输出精确及UBSAN10非法输入通过。厂商模型/卷积不变，仅按实际quarter取整与5pool空branch结果修正包装。没有相机/UI/显示状态访问，零尺寸quarter异常与上限/小图完整运动等继续待验收。见`evidence/native-ui/74-shipped-cnn-dimensions.txt`。

最新重开/低FPS补证（N073，2026-10-21）：原3组终止清理/预读块实际清双脸指针、重开归零扫描/帧号而保留旧merger候选；原普通帧返回跳过清理。两组32帧均在frame31先合并.1875再得FPS9，非预览终止；实际blinkDetected消费槽仅预览响应，训练成功位于下一轮。生产-O64帧及相关release9项精确/通过，本次不改生产代码。未执行相机释放、Qt错误/成功信号送达或完整native平台失败/重开链，仍保留真实验收边界。见`evidence/native-ui/73-shipped-reopen-low-fps.txt`。

最新FPS/预读补证（N071，2026-10-21）：实际原18组31间隔窗口、模31门槛、10000槽环绕及预览/低FPS分支已对照；必须先sum/31再1/mean，合并count/sum有4组多1，修正后-O精确。fresh Model原预读完成时frameCounter0且CNN/dlib/flow命中0；native prime仅记尺寸/时基、ready单独通知而不喂测量样本，第一31分析间隔与黑预读后正向事件回归通过。112 Swift/21 release通过，未执行真实capture或原Qt ready/error信号；跨重开状态与lowFPS同帧事件继续待补。见`evidence/native-ui/71-shipped-fps-startup.txt`。

最新整数时间补证（N069，2026-10-21）：FrameTimestamp保留原始整数ticks与实际frequency，先差后除，原3组真实dt及近Int64计数上界短差-O精确；明确间隔传至motion/stream/scanner和FPS，避免从绝对秒二次相减。新C桥复用本机arm64 OpenCV Mach时钟，本机24MHz与ProcessInfo同域区间验证通过；原3组Rosetta记录为1GHz，不据此硬编码。6失败断言→107 Swift及13 release通过，原13段173帧22候选/8候选对和50图像/7原始尺寸正向保持。预读基准/首次31delta窗口与原FPS累加、低FPS同帧事件顺序仍待补，未宣称真实捕获准出。见`evidence/native-ui/69-integer-frame-time.txt`。

最新取时补证（N067，2026-10-21）：原Model在resize完成后、gray/tracking前getTickCount并保存当前tick，末尾以整数差/getTickFrequency写dt。已实际执行3次界限/顺序与dt槽核验；新生产clock移至归一化成功后，运动/回调/FPS共享，缩放失败不消费clock的回归1失败→debug/release通过，100 Swift0失败。原Integer tick与新版Double相减精度、预读基准/首次31delta窗口仍待处理；该检查点不是完整计时/相机准出。见`evidence/native-ui/67-shipped-frame-clock.txt`。

最新输入补证（N065，2026-10-21）：实际原首帧width/640 Float比例、后续缓存比例与BGR INTER_LINEAR/gray在22组输入、25518080颜色灰度字节精确对照；7帧公开正向图放大到1280×960，经实际原归一化后与N063640×480边界BGR/gray SHA相等。新生产FrameNormalizer接入同一frame stage，31失败断言→debug/release原始尺寸到.1875秒事件通过；99 Swift、144 C UBSAN检查通过。相机read、缩放后的tick采样位置和实机非VGA设备仍待验收。见`evidence/native-ui/65-shipped-frame-normalization.txt`。

最新串联补证（N061/N063，2026-10-21）：实际原CNN/dlib/眼区跟踪→flow/扫描/合并→交换已在6条50帧固定公开图/人工像素运动序列逐帧对照，含3帧无脸、47组眼区及两次.1875秒事件。无上一脸的非四帧重获只用CNN粗眼位，等四帧才精修；无当前脸仍按上一脸算flow，下一首脸跳过flow而不清时序。修正新版无脸即清缓存，7失败断言→debug/release通过；98 Swift及37 C UBSAN检查通过。范围不含相机归一化/read、真实时钟/无脸超时或准确率；遮挡样本仍被CNN选中，跨丢脸候选完成继续待补。见`evidence/native-ui/61-shipped-eye-tracking.txt`、`evidence/native-ui/63-shipped-tracked-motion.txt`。

最新运行补证（2026-10-21）：N059新增7张固定彩色帧（给定眼几何/合成帧时钟）的下游正向事件原码对照，修正EF_WARMUP未进入temporal而漏掉第一运动的问题；原第5帧.1875秒事件与优化后的生产衔接逐值一致，debug/release回归及全套96测试通过。N056补10组原ROI→光流→统计连接对照；N057补5张固定彩色帧的灰度/前脸门槛/帧交换路径，修正首帧额外blur（3/5→5/5精确）。N053另补原时序块13序列173帧、22候选与8候选对，纠正先前合并比较方向/初始参照/参照生命周期并保留同帧全部事件；N054补原统计算术6组精确输出。本报告下文保留最初静态调查范围。实际原读取器/预测器8组40点、原光流统计9组、原灰度/blur组件3图307040字节已对照一致；N051新增实际原Farneback的6组ROI、39684个Float及下游统计逐值一致，独立原Float半尺寸缩放32组精确一致。生产OpenCV全局禁用FMA，并以固定SHA补丁保留四lane成对累加与标量尾部。参见`evidence/native-ui/51-shipped-farneback-float-resize.txt`；这些仍不是原Model完整帧循环、ROI跟踪和最终blink序列等价证明。

# 原版调度与检测规则补证

2026-10-19。本报告只读本机 `/Applications/eyeblink.app/Contents/MacOS/eyeblink`，未执行目标、未访问用户统计/偏好、未变更 REA active session。基线 SHA-256 为 `bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db`。当前无原生反编译 provider，因此结论来自有地址的机器指令、跳转表原字节、模型结构解析，不是恢复到原始 C++ 源码，也不是运行验收。

证据在 [recovered-rules](../evidence/static/recovered-rules/)。`collect.py` 校验目标 SHA 后重新产生有界反汇编，`inspect-model.py` 只读解析模型。`controller-model.disassembly.txt` 中线性反汇编会把代码段中的跳转表当作指令；表本身以 `jump-tables.json` 的小端 int32 解析为准，`decideWhatToRun.llvm.txt` 从真实入口重新解码。以下地址均为未加 ASLR slide 的 VA。

## 已恢复：状态与调度

`codeToText` 的跳转表 `0x100139a28` 加字符串实际分支恢复出：0=break、1=exercise、2=free camera、3=training（简单提醒）、4=interactive training、5=measurement。当前状态字段为 Controller+`0xb4`。

|规则|指令证据|结论与边界|
|---|---|---|
|调度轮询|`0x100137cb3` setInterval `0x7d0`，`0x100137ccb` 连接 `accessFeature()`|每 2000ms 检查一次，不能期望秒级定时正好触发|
|整体门槛|`0x10013a31b–0x10013a345`|仅 free、预览关闭(+8a)、全部暂停关闭(+8b)、退出关闭(+8d)才决策；非 free 不抢占|
|启动/恢复延迟|`0x10013a5e9–0x10013a603` 比较 +c8 到现在是否 <`0x3a98`；构造 `0x10013786c` 和恢复 `0x10013a24a` 写 +c8|启动或恢复全部后 15000ms 门槛，作用于所有调度功能。不是“每次相机停止后冷却”|
|测量优先|`0x10013a609–0x10013a633`，`0x10013a6e4`|相机未暂停(+8c=0)、测量开(+89)、测量单次 timer 已不活动才选 measurement；在 break/exercise/training 前检查|
|电脑休息|`0x10013a646–0x10013a667`|`now.secsTo(nextBreak)<0` 且开(+86)选 break。Qt 使用整数秒，因此与直接比较毫秒日期有边界差异|
|眼操|`0x10013a66d–0x10013a689`|眼操开(+87)、`now.secsTo(nextExercise)<0`，且到电脑休息仍 >=301 整数秒，才选 exercise。这个抑制条件未依赖电脑休息是否启用|
|交互/简单训练|`0x10013a68b–0x10013a6ed`|训练 timer 已不活动且训练开(+88)才选；相机可用且交互开(+82)→4，否则→3。相机暂停时退化为简单提醒|
|测量启用首轮|`0x1001392af–0x1001392c0`|开启后测量 timer=120000ms（2分钟），不是马上开始|
|立即测量|`0x10013a2e9–0x10013a303`|测量 timer start(1ms)，随后调用 accessFeature；仍受 busy、暂停、预览、启动延迟门槛限制|
|成功后测量间隔|`0x10013afba–0x10013afc6`|1800000ms（30分钟）|
|测量被停止后的重试|`0x100139902–0x100139922`|若当前 measurement，下一次 480000ms（8分钟），然后 free|
|设置休息间隔|`0x10013894d–0x100138998`|nextBreak += (newMinutes−oldMinutes)*60000，保留当前进度，不是从更改时间重新计时|

`accessFeature` 的跳转表在 `0x10013a5b4`。break/exercise 启动时把训练 timer 设为20000ms；simple 启动独立隐藏 timer=3000ms，发提醒；interactive/measurement 刷新相机列表后发对应启动信号。timer 值与连接关系均在保存的指令中。

## 已恢复：自然休息与眼操

自然休息 checker 每60000ms执行（`0x100137d60`、`0x100138a87`/`0x100138b97`）。它不直接读取系统 idle 秒数：

1. `0x1001381b4` 读光标位置；`0x1001381c5–0x1001381cf` 调 `CGEventSourceCounterForEventType(1,10)`。
2. 键盘计数有变化或光标坐标有变化，+d0记录**当前采样时刻**（`0x1001381d4–0x100138226`）。
3. `0x100138242–0x100138251` 判 `now−lastObservedActivity > naturalMinutes*60000`，严格大于。
4. 满足后若 includeNatural 开(+84)，把 nextBreak=now+配置分钟、nextExercise=now+1140000ms（`0x1001383af–0x10013844d`）。持续闲置时每分钟都重新顺延。
5. `0x100138452–0x100138480` **无论 includeNatural 开关**，当前为 break 则 quitBreak；当前为 exercise 则发送 exerciseFinished 并 free。

因此默认3分钟自然休息，配合每分钟采样会出现约4分钟终态；源码没有独立固定240000ms的休息完成倒计时。改变 naturalMinutes 会改变这个边界。直接使用更精确的系统 idle API 会改变原版采样语义（原版也可能漏掉两次采样间移动后回原位的活动），只能作为明确的新实现差异。

- `quitBreak` 仅当前状态为0时生效；重置 nextBreak 和 nextExercise，发 breakFinished/free。证据 `0x10013851b–0x10013861d`。
- `skipBreak` 只重置 nextBreak=now+配置分钟，然后 free，不重置眼操（`0x1001386bf–0x100138712`）。
- `snoozeBreak` 只设 nextBreak=now+300000ms（5分钟），然后 free（`0x100138765–0x1001387a8`）。
- 眼操 nextExercise 常量为 `0x116520`=1140000ms=**19分钟**，见构造 `0x1001378d3`、quitBreak `0x1001385db`、quitExercise `0x1001388ae`。文案“20分钟”不能覆盖这个指令事实。
- 每次眼操显示**一个动作10秒**：ExerciseReminderWidget::fadeIn `0x100183c33` start(10000)；fadeOut `0x100183e99` 隐藏、`0x100183eb6–0x100183ec6` 动作索引加1并模4、`0x100183f07` 发完成。下一次提醒才显示下一动作，不能实现为一次连续4×10秒。

## 已恢复：交互训练、MGD 与预览

`training-signal-wiring.txt` 保存实际 QObject::connect 调用：`0x10012444d–0x100124468` 将 trainingStarted 接到 adjustBlinkTrainingForMGD；`0x100124481–0x10012449c` 将 blinkReactionToReminder(bool) 接到 processBlinkForTraining。

- Model训练开始清 count、false已发送标志，设无脸参数3000ms，再进入检测（`0x10014456f–0x100144596`）。相机成功启动后发 trainingStarted（`0x10014048a–0x100140496`）。
- MGD 开时，adjustBlinkTrainingForMGD立即请求显示提醒（`0x1001390bf–0x1001390c8`）。
- 普通训练等 elapsed>=4001ms 且尚未发 false，再发 false（`0x1001405d4–0x1001405f9`）；Controller仅在非MGD时据 false 显示提醒（`0x1001391c4–0x1001391ce`）。
- 发 false 后**相机保持检测**，不是4秒后无条件释放。检测到一个合并 blink 后释放相机并发 true（`0x1001405a5–0x1001405ca`）；Controller 发 userBlinked、重启训练间隔 timer、变 free（`0x100139196–0x1001391bb`）。
- 简单提醒通过3000ms独立timer调用 hideBlinkReminder，再从隐藏时刻重新计训练间隔（`0x100137bd6–0x100137bf4`、`0x10013a45a–0x10013a466`、`0x100139012–0x10013902e`）。默认30秒间隔不包含显示的3秒。
- 预览(+8a)使自动调度完全跳过。enableLivePreview 的跳转表详见 JSON：开启时如果break则quitBreak，exercise则finish，simple则hide，再启动预览；interactive/measurement先stopCamera，等 stopped 后启动预览（`0x100139eea–0x100139f2f`、`0x100139933–0x100139949`）。普通到期任务不会抢占预览。

## 已恢复：眨眼特征与时间状态机

原版不是“眼睑长宽比 EAR 小于阈值连续N帧”。它用关键点定位眼区，再计算两帧之间眼区的垂直运动。

### 输入特征链

- 原始画面按宽640缩放（`0x10014076f`）。当前帧经灰度转换(code6)写到Model+1e0（局部-1f8）；3×3 box blur、anchor(-1,-1)、borderType4原地作用于**上一帧**Model+240（局部-208）。dlib读取当前未模糊灰度；Farneback输入依次为上一帧模糊灰度ROI、当前未模糊灰度ROI，末尾交换两Mat。证据 `0x1001407c9–0x100140895`、`0x10014110b–0x1001411d9`、`0x100142cf3`。初始化预读灰度在 `0x1001402ed–0x100140396` 模糊一次、首循环又模糊，但新Model的previous-face为0会跳过这次flow，随后交换未经模糊的current。N057实际执行灰度/无前脸分支/交换并逐帧核对，证明首个实际比较所用previous只模糊一次；N059进一步证明暖机零特征必须传入temporal作为时间基点，原扫描器会在后续扫描此前的零槽，丢弃暖机会使首个真实运动变成新版数组首元素而不被扫描；先前据预读推导warmup也应blur的解释已纠正。5帧缓存SHA及双眼特征精确，见`evidence/native-ui/57-shipped-gray-flow-warmup.txt`。
- `0x10014089a` 测帧序号低两位：每4帧走CNN和精细关键点更新，其余帧存在上一face时复用先前坐标（`0x1001408cd–0x1001408f7`）。没有上一face时仍会尝试初检；N061原码实测非四帧重获仅保存CNN粗中心与脸宽一半，跳过dlib直到下一四帧。
- detectBestNearestFace2 把图缩小0.25后调 facedetect_cnn（`0x10013f309–0x10013f33c`），并以旧框距离/面积/score等选框。该步骤并非dlib模型的全部职责。
- `detectEyes` 在 `0x10013fbf7–0x10013fc61` 取 p0/p1 平均坐标作为眼A中心、点间欧氏距离四舍五入；`0x10013fc65–0x10013fcca` 同理取 p2/p3 为眼B；宽度再乘2（+2b0=2）。p4在此函数未用。5点模型因此无法提供68点眼睑EAR。
- 正常检测循环内同样内联此公式（`0x100140cab–0x100140dbd`）。眼区围绕前一帧中心、边长来自前一帧眼宽，裁到图像边界；这些边界操作保存于 `0x100140e61–0x1001410e2`，N056已在10组给定眼几何和灰度输入的完整ROI→Farneback→统计块实测精确（含零面积/4与6像素/金字塔）。
- 两眼ROI分别调用 `cv::calcOpticalFlowFarneback`，参数 `pyr_scale=.5, levels=3, winsize=15, iterations=3, poly_n=5, poly_sigma=1.2, flags=0`。证据 `0x100141193–0x1001411d9` 与 `0x100141755–0x10014179b`。
- `calcAvgYandStdDev` 对圆内光流样本计算：令 `r=trunc(previousEyeWidth*.5)`、scale=2，只选 `sqrt(dxPixel²+dyPixel²)<r/scale` 且 `flowX²+flowY²<225` 的样本。每个样本 `v=flowY/max(normalizer,1)`；mean=平均v；先算总体variance，只有variance>1e-8才开方，否则原样返回variance（并非所有非零方差都开方）。证据 `calcAvgYandStdDev.llvm.txt`：`0x10013f81c–0x10013f83b`、`0x10013f8ea–0x10013f951`、`0x10013fabb–0x10013fb78`。
- normalizer由上一双眼中心得到：`sqrt((Ax−Bx)²−(Ay−By)²)`（**减号**），见 `0x1001410ca–0x1001410e2`。这是当前机器指令，不能直接“修正”为hypot再宣称同算法；倾斜头部/NaN处理的实际影响仍待同帧对照。
- 环形缓冲10000帧保存每眼mean/std与帧间dt（`0x100140df1–0x100140e49`、`0x100141a36–0x100141a86`）。dt=`(getTickCount(current)−getTickCount(previous))/getTickFrequency()`；std累积是逐帧求和，不乘dt；mean阈值也未发现额外fps归一化。

### 每眼三态机

Model::init写入 `a=.0025`(+61dc8)、`b=.0075`(+2b8)、maxDuration=.5(+61dd8)、minDuration=.1(+61de0)。指令 `0x10013e4b2–0x10013e4de`；浮点原字节和值见 `floating-constants.json`。

两个对称状态机分别从 `0x100141e3d` 和 `0x10014210b` 开始。以下使用mean=m、std=s、当前帧间隔dt、候选期间累计标准差sumS、累计秒数t：

1. 所有非0态：t>.5时放弃候选，回溯从旧start+2重新搜索，不只是丢当前帧（`0x100141e4e–0x100141ebf`）。
2. 状态0：m>a且s>a→状态1；sumS=s、t=dt、start=i−1（`0x100141f4c–0x100141fab`）。
3. 状态1：m<−a且s>a且sumS>b→状态2，sumS重置为s，t+=dt；否则m>−a且s>a时sumS+=s；若m<−a且s>a但sumS不够则放弃重搜；其余继续累加t。对应 `0x100141ecf–0x100141f47`、`0x100141ff0–0x100142020`、`0x1001420d1–0x100142106`。
4. 状态2：m<a且s>a时sumS+=s并t+=dt；否则若sumS>b且t>.1则输出候选(start,end=i−1,t,sumS)并回状态0；若未满足候选且m>a且s>a则放弃重搜，其余继续t。对应 `0x100141fb0–0x100141feb`、`0x100142025–0x1001420a6`、`0x1001420d9–0x100142106`。

边界比较均是严格大于/小于；不存在已恢复的“闭眼N帧”常量。s低于阈值并不直接清状态1；持续时间门槛仍会清理。

### 眼候选提交、合并与统计（实际原码修正）

`mergeBlinks` 的前候选为prev、当前为cur；start/end为**帧索引**，duration才是累计秒数。不是用时间戳计算重叠率。原每轮先扫左眼全部待处理帧，再扫右眼，没有按候选end排序（`0x100141a99–0x100141ab2`）。原表达式为：

```text
ratio = (prev.end − cur.start) / (cur.end − prev.start)
if ratio < 0.3:
    count += 1
    totalDuration += 0.5 * (prev.duration + cur.duration)
    emit blinkDetected()
prev = cur  // 接受与否都更新
```

此前静态报告误读了比较方向；2026-10-21已直接调用原函数及实际扫描块，N053实测确认严格小于0.3，强重叠反而跳过，相接/不相交也可能计数。原构造器的prev为帧0/0、duration0.25，开启相机只清扫描状态，不重置prev；不能换成nil初值、强重叠配对或正分母门槛。13段173帧、22个候选和8组明确候选对已经逐值对照，并捕获同一帧发出两个事件。新版链路现传递事件列表，保留全部输出。指令 `0x100144354–0x1001443ba`、`0x100144411–0x100144441`、`0x100144446–0x100144465`，常量0.3在VA `0x10020bc40`；证据`evidence/native-ui/53-shipped-temporal-sequences.txt`。固定特征序列仍不代替完整图像/裁眼/跟踪链。

测量成功出口读取 elapsed，>=180001ms即结束（`0x10014053f–0x100140551`），是墙钟时间，不是累计有效脸帧时间。BPM先以Double算count/3，再cvtsd2ss转换为Float输出；平均长度=count>0时严格按 `int(totalDuration/count*1000)` 顺序，不能先乘1000再除，否则[.09,.09,.12]会从原99ms变100ms。无事件均为0（`0x100140567–0x10014059b`）。N054直接执行该算术范围的6组固定输出现已精确对照，见`evidence/native-ui/54-shipped-measurement-arithmetic.txt`。

无脸参数在训练为3000ms、测量为10000ms；比较实际是 `elapsedNoFace > parameter−2000`（`0x1001412ee–0x10014130b`），即严格超过1000/8000ms后释放并报错。timer在第一失败帧或从有face转无face时重置（`0x100140e53–0x10014126b`、`0x1001412d0–0x1001412de`）。该段最初为静态解释；后续N076实际验证重置门槛/整数毫秒/超时分支，N078另以2帧真实blackCNN确认tracking后起时，N080将native超时移到flow前并由分析器独占；完整物理相机/Qt送达仍待验收。低FPS终止分支比较整数FPS<=9（`0x100141d78–0x100141e33`）；UI建议20FPS并非这条实际终止阈值。

## data.dat 与 Apple Silicon

`inspect-model.py` 按官方dlib序列化结构完整消费文件到EOF：

- 9150489字节，SHA-256 `c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888`。
- shape_predictor版本1；初始shape=10×1浮点矩阵，即5点。
- 15级×每级500棵回归树，共7500棵；每树15个split、16个leaf；每个leaf输出10×1。
- 每级800个anchor/delta，anchor只引用0…4；全部索引和矩阵维数校验通过，末尾剩余0字节。

结果在 `model-structure.json`。这推翻了 `file` 将其识别为PDP-11的magic误判：它是数值序列化模型，不是Intel执行代码。结构依据见官方 [shape_predictor](https://github.com/davisking/dlib/blob/master/dlib/image_processing/shape_predictor.h)、[serialize](https://github.com/davisking/dlib/blob/master/dlib/serialize.h)、[matrix](https://github.com/davisking/dlib/blob/master/dlib/matrix/matrix.h)。按后续明确授权，原模型只复制到已忽略的`.deps/models/data.dat`，未进入源文件或提交范围。已用官方dlib19.24源码编译arm64参考程序，真实反序列化该模型并对8个固定灰度/边界框夹具执行推理；40个关键点输出存于`dlib-reference-results.json`。构建参数、源归档/模型/程序/结果SHA和Mach-O arm64身份存于`dlib-reference-build.json`。这证明该模型可在本机arm64官方dlib上加载与推理，仍不证明原应用完整相机流水线兼容或等价。

原程序x86汇编出现SSE操作，只能证明原构建使用x86 SIMD，不能证明源算法必须依赖Intel。当前官方dlib [simd4f](https://github.com/davisking/dlib/blob/master/dlib/simd/simd4f.h)包含SSE2、NEON和普通回退分支，[simd_check](https://github.com/davisking/dlib/blob/master/dlib/simd/simd_check.h)按ARM NEON宏选择分支；抽取行号/SHA在`dlib-portability-sources.json`。这支持重编译路线，仍需检查所选精确版本和CNN源码，不能把原版Intel dylib直接打包。

为接近同帧结果，原算法移植仍需：锁定CNN源码/嵌入权重版本；arm64重建CNN+dlib+OpenCV；保留或逐项记录灰度、resize、blur、ROI裁切、Farneback数值与候选重扫差异；用相同录制帧分别喂原版与新版比较face/眼区/mean/std/最终blink。Vision定位+EAR是另一检测器，不能仅凭都能计数称为算法复刻。

## Swift预测器实现与验证

新增`Sources/EyeblinkCore/DlibShapePredictor.swift`：只读版本1模型、加载15级回归树/anchor/delta、逐级提取灰度特征、逐树评估、输出5点。对数组维度、完整树、索引、截断文件和尾随字节有校验；坐标采用dlib的`floor(x+.5)`，图外采样补0。相似变换用与Umeyama数学等价的二维闭式解，再转Float；它不是通用逐位浮点等价声明。

`Tests/EyeblinkCoreTests/DlibPredictorTests.swift`覆盖已知单树严格分支/边界取整、图外补零/不裁输出、坏模型/图像、真实模型结构/确定性，以及8个官方C++参考夹具的40个关键点逐点比较。测试日志在`dlib-swift-tests.log`；若机器无本地模型，真实模型测试明确skip，不能称模型验收通过。参考程序未调用原版应用；这些合成输入证明的范围止于该预测器，不涵盖人脸框来源、光流或最终眨眼决策。

## 尚未回答

- 多个人脸在真实相机中的选择与追踪表现；精确源码及权重身份已经补齐，见`face-detector.md`。
- 全部ROI边界、原图像/追踪/特征时钟链，以及normalizer减号的同帧实测影响；候选重扫/提交顺序已在13段固定特征序列对照，仍需与图像链衔接。
- 同帧检测等价、arm64 CPU/功耗/FPS和相机长期运行证据。
- 权限拒绝、相机断开、睡眠/唤醒与模式切换的实际竞态证据。

因此本文件是可供实现引用的静态规则补证，不是“完全复刻已完成”的证明。

## 补证：鼠标关闭与图表参考线

`BlinkReminderWidget::changePosition` 在0x100184eb5将+0x38设为1，savePosition在0x100184f20设回0；该字段是位置编辑模式。普通模式的enterEvent在0x100184a71检查该字段，最终在0x100184acb发hideBlinkReminderByMouseRequested。位置编辑模式允许左键拖动，移入不关闭。新版普通训练浮层移入关闭，预览用于拖动调整。证据：blink-reminder-{events,position,constructor}.llvm.txt。

主图configurelGraphAppearance为+0x178的QCPItemLine设置两个端点y=10.0：0x100172810与0x100172828都引用Double常量0x100201b38（文件偏移0x201b38，`0000000000002440`）。+0x180文字坐标同样取y=10；configureGraphLanguage在0x10015fcc9–0x10015fcf8将该文字设为healthy。新版显示每分钟10次的原版参考线；这是复刻原软件显示，不作为额外医学阈值。证据：graph-appearance.otool.txt、graph-language.otool.txt。

测量完成路径0x10014055f–0x10014059b先将平均眨眼时长乘1000，再用cvttsd2si截断为整数毫秒；没有眨眼时esi保持0。新版每条记录的时长显示保持该规则（空结果为0，非四舍五入）。浮点频率仍按count/3的180秒生产时钟计算。

## 补证：原版历史JSON结构

`collect-statistics.py`校验原二进制SHA后，仅反汇编`loadMeasurementsFromJson`和`addMeasurement`的有界范围；产物及SHA在`statistics-identity.json`，未读取用户统计文件。

空文件初始化在0x100156c63–0x100156cb2构造对象和空数组，插入顶层`data`。追加记录在0x100159c00–0x100159c3d取`data`数组，再构造对象并插入以下字段：

|字段|静态恢复的类型|关键地址|
|---|---|---|
|datetime|字符串|0x100159e18–0x100159e46|
|blinkrate|double|0x100159e7b–0x100159ead|
|note|字符串，来自addMeasurement参数|0x100159ee2–0x100159f0f|
|length|int，平均眨眼毫秒|0x100159f44–0x100159f71|

datetime从当前QDateTime按DateFormat枚举1序列化；保留本地UTC偏移，零偏移分支将末尾Z替换成`+00:00`（0x100159cd5–0x100159d71）。0x100159fae–0x100159fbe把记录对象追加至数组，后续重新插入`data`并序列化JSON。

这是字段及写入类型的静态证据，不能宣称已完成原版文件回读或迁移。原版只保存频率和平均时长，不能据此还原逐次眨眼事件；未来兼容导入必须保留这些汇总值，不能编造`blinkDurations`。新版仍使用独立数据目录及原始事件记录。

## 补证：原版数值控件范围

原二进制SHA校验后的只读`otool -tvV`结果中，按构造函数对象名、成员偏移及直接QSpinBox setter追踪得到：

|控件|单位|范围|直接setter地址|
|---|---|---|---|
|spinBox_trainingPeriod，成员+0x5d0|秒|2–60，显式步长1|0x10016e075 / 0x10016e086 / 0x10016e097|
|spinBox_timeBetweenBreaks，成员+0x6b0|分钟|15–80，显式步长1|0x10016f298 / 0x10016f2a9 / 0x10016f2ba|
|spinBox_naturalBreaksDuration，成员+0x6d8|分钟|2–9|0x10016f5ad / 0x10016f5be|

证据`evidence/static/recovered-rules/spinbox-ranges.otool.json`与`ui-spinboxes.otool.txt`。空闲阈值没有发现显式singleStep setter，不据此声称二进制证明其步长。训练控件Designer初始15不覆盖后续控制器/设置中的有效默认30秒。

新版以`OriginalControlRanges`集中约束原生UI及设置加载/保存，保留Core受控时钟测试能力。3项回归验证端点、旧重建版越界设置收敛、整数及坏值回退；实际UI验证见`evidence/native-ui/31-original-control-bounds.txt`。

## 补证：固定周期与训练衔接落实

生产设置入口只允许原版存在的可调项。测量间隔1800秒、测量时长180秒、眼操间隔1140秒统一来自`OriginalSchedule`，设置加载/保存会将早期重建版的自定义值恢复为这些固定值。原生界面改为只读展示；Core仍允许受控夹具时钟。

`accessFeature`在发breakRequested和exerciseRequested前分别于0x10013a383/0x10013a3f2传入20000并调用同一训练QTimer（+0x118）的start。这是从当前功能开始时重计20秒，不能在10秒眼操结束时立即拿此前过期的训练计时触发提醒，也不能在结束时另加完整20秒。当前实现与两项衔接回归已修正，见`evidence/native-ui/32-fixed-schedule.txt`。
