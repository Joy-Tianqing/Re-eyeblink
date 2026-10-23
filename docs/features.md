# 功能与待验证清单

由 `catalog/features.json` 生成，请修改源文件后执行 `npm run generate`。

当前 66 项，包括可见功能、部分行为、历史/平台候选；实现进度与验收独立记录，当前尚无整项功能完整验收通过。计数不是完整行为覆盖率。

|证据级别|数量|含义|
|---|---:|---|
|局部行为已观察|4|只证明账本中明确记录的局部前后态|
|部分行为已观察|6|已有操作，终态或其他分支未闭环|
|入口/文案可见|23|入口/说明存在，效果未完成验证|
|仅静态证据|33|字符串/符号/资源，不证明当前Mac可达|

## shell

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S001|主窗、托盘及后台运行|部分行为已观察|Mac目标 / P1-shell|O01, O14|N001, N005, N034, N035, N082, N088, N094, N095, N096|partial|
|S002|演示模式：暂停全部提醒、测量和屏幕调节|局部行为已观察|Mac目标 / P1-shell|O06|N013, N041, N082, N095, N096|implemented-awaiting-acceptance|
|S003|恢复全部功能|局部行为已观察|Mac目标 / P1-shell|O07|N013, N041, N095, N096|implemented-awaiting-acceptance|
|S004|独立暂停摄像头功能|局部行为已观察|Mac目标 / P1-shell|O08|N016, N035|implemented-awaiting-acceptance|
|S005|恢复摄像头功能|局部行为已观察|Mac目标 / P1-shell|O11|N016, N035|implemented-awaiting-acceptance|
|S006|退出程序|入口/文案可见|Mac目标 / P1-shell|O01|N005, N034, N035, N095, N096|implemented-awaiting-acceptance|

待补：N095中文应用菜单暂停/恢复及N096菜单退出通过，关闭/工具重开仍同一进程；继续右侧状态图标菜单动作、独立关闭停留、Dock双启动单实例与真实登录启动。

## camera

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S007|选择摄像头|入口/文案可见|Mac目标 / P3-camera|O04|N002, N033|implemented-awaiting-acceptance|
|S008|实时眨眼检测预览、不入统计|部分行为已观察|Mac目标 / P3-camera|O04|N007, N016, N033, N035, N042, N045, N046, N047, N048, N050, N051, N052, N053, N055, N056, N057, N058, N059, N060, N061, N062, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N082, N083, N084, N085, N086, N087, N088, N089, N090, N091, N092, N093, N094, N096, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|implemented-awaiting-acceptance|
|S009|预览叠加检测文本|仅静态证据|Mac目标 / P3-camera|无|N007, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|partial|
|S010|无脸、多脸、低帧率、被占用、断线及模型异常|部分行为已观察|Mac目标 / P3-camera|O01, O12|N033, N035, N039, N042, N043, N045, N046, N048, N050, N051, N052, N053, N055, N056, N057, N058, N059, N060, N061, N062, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N082, N083, N084, N085, N086, N087, N088, N089, N090, N091, N092, N093, N094, N096, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|partial|
|S011|摄像头设置按钮（Mac 实现仅 count，无设置动作）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|
|S012|相机隐私设置入口（含 Windows 文案，须区分平台）|仅静态证据|延后确认 / deferred|无|N002, N015|implemented-awaiting-acceptance|

待补：真实相机完成一次有效眨眼；检查拒绝权限、占用/拔出、无人脸、多脸、低FPS及释放后重开；预览不得污染统计。

## training

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S013|眨眼训练开关|入口/文案可见|Mac目标 / P2-reminders|O01|N031|implemented-awaiting-acceptance|
|S014|训练频率（秒）|入口/文案可见|Mac目标 / P2-reminders|O01, O13|N030, N082|implemented-awaiting-acceptance|
|S015|定时简单提醒、无需相机|入口/文案可见|Mac目标 / P2-reminders|O01, O08|N047|implemented-awaiting-acceptance|
|S016|低眨眼频率才出现的交互提醒|入口/文案可见|Mac目标 / P2-reminders|O01, O11|N045, N046, N047, N048, N050, N051, N052, N053, N055, N056, N057, N058, N059, N060, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N083, N084, N086, N087, N089, N090, N091, N092, N093, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|implemented-awaiting-acceptance|
|S017|眨眼关闭提醒|仅静态证据|Mac目标 / P2-reminders|无|N025, N045, N046, N048, N050, N051, N052, N053, N055, N056, N057, N058, N059, N060, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N083, N084, N086, N087, N089, N090, N091, N092, N093, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|implemented-awaiting-acceptance|
|S018|MGD 模式：定时出现、眨眼关闭|入口/文案可见|Mac目标 / P2-reminders|O01|N025, N045, N046, N048, N050, N051, N052, N053, N055, N056, N057, N058, N059, N060, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N083, N084, N086, N087, N089, N090, N091, N092, N093, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|implemented-awaiting-acceptance|
|S019|提醒音开关|入口/文案可见|Mac目标 / P2-reminders|O01|无|implemented-awaiting-acceptance|
|S020|拖拽/保存眨眼提醒位置|部分行为已观察|Mac目标 / P2-reminders|O09, O10|N011, N037|partial|
|S021|鼠标移入/操作关闭提醒（具体触发待体验）|仅静态证据|Mac目标 / P2-reminders|无|无|partial|

待补：观察简单/交互/MGD提醒触发与消失；确定低频阈值、检查窗口、声音、位置保存和鼠标关闭条件。

## exercise

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S022|眼保健操开关、每20分钟|入口/文案可见|Mac目标 / P2-reminders|O01|N031|implemented-awaiting-acceptance|
|S023|远眺10秒|仅静态证据|Mac目标 / P2-reminders|无|N022|implemented-awaiting-acceptance|
|S024|挤眼睑眨眼10秒|仅静态证据|Mac目标 / P2-reminders|无|N023|implemented-awaiting-acceptance|
|S025|左右转眼10秒|仅静态证据|Mac目标 / P2-reminders|无|N024|implemented-awaiting-acceptance|
|S026|旋转眼球10秒|仅静态证据|Mac目标 / P2-reminders|无|N018|implemented-awaiting-acceptance|
|S027|跳过/终止眼操|仅静态证据|Mac目标 / P2-reminders|无|N018, N022, N023, N024|implemented-awaiting-acceptance|
|S028|眼操浮层拖拽和保存位置|仅静态证据|Mac目标 / P2-reminders|无|无|partial|

待补：等待20分钟或找到原版支持的测试入口，记录四种练习的顺序/轮换、10秒终态、跳过及自然休息重置。

## break

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S029|电脑休息开关与间隔（分钟）|入口/文案可见|Mac目标 / P2-reminders|O01, O13|N030, N031, N049|implemented-awaiting-acceptance|
|S030|休息提醒：连续空闲后关闭（默认约4分钟）|仅静态证据|Mac目标 / P2-reminders|无|N012, N026, N044, N049|implemented-awaiting-acceptance|
|S031|跳过一次休息|仅静态证据|Mac目标 / P2-reminders|无|N029, N044, N049|implemented-awaiting-acceptance|
|S032|休息推迟5分钟|仅静态证据|Mac目标 / P2-reminders|无|N012, N029, N044, N049|implemented-awaiting-acceptance|
|S033|休息浮层拖拽和位置保存|仅静态证据|Mac目标 / P2-reminders|无|N049|partial|
|S034|纳入自然休息（无键鼠操作）|入口/文案可见|Mac目标 / P2-reminders|O01|N026, N044, N049|implemented-awaiting-acceptance|
|S035|自然休息认定时长|入口/文案可见|Mac目标 / P2-reminders|O01|N026, N030, N044, N049|implemented-awaiting-acceptance|

待补：真实到期→推迟5分钟→再次到期→人工跳过已验证；仍需连续空闲严格超过阈值并在每分钟采样时自动结束、拖动位置及系统睡眠边界。

## measurement

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S036|眨眼频率统计开关；约30分钟一次/每次3分钟|入口/文案可见|Mac目标 / P4-statistics|O01|N017, N031, N053, N055, N054, N056, N057, N058, N059, N060, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N082, N083, N084, N085, N086, N087, N089, N090, N091, N092, N093, N094, N096, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|implemented-awaiting-acceptance|
|S037|立即进行首次/下一次测量|部分行为已观察|Mac目标 / P4-statistics|O12|N008, N038|implemented-awaiting-acceptance|
|S038|测量完成系统通知开关|入口/文案可见|Mac目标 / P4-statistics|O01|N036, N038|implemented-awaiting-acceptance|
|S039|主图及平均值/健康参考线|入口/文案可见|Mac目标 / P4-statistics|O01|N019, N054|partial|
|S040|独立历史图、悬停值、开始/结束日期筛选|仅静态证据|Mac目标 / P4-statistics|无|N019, N020, N021, N032|partial|
|S041|每分钟眨眼次数和平均眨眼时长（毫秒）|仅静态证据|Mac目标 / P4-statistics|无|N008, N021, N053, N055, N054, N056, N057, N058, N059, N060, N063, N064, N065, N066, N067, N068, N069, N070, N071, N072, N073, N074, N075, N076, N077, N078, N079, N080, N081, N082, N083, N084, N085, N086, N087, N089, N090, N091, N092, N093, N098, N099, N100, N101, N102, N103, N104, N105, N106, N107, N108, N109, N110, N111, N112, N113, N114, N115, N116|partial|
|S042|历史窗口最大化/还原|仅静态证据|Mac目标 / P4-statistics|无|N019|partial|
|S043|清空历史与确认|仅静态证据|Mac目标 / P4-statistics|无|N009, N036|implemented-awaiting-acceptance|
|S044|本地 JSON 测量持久化|仅静态证据|Mac目标 / P4-statistics|无|N010, N034, N053, N055|implemented-awaiting-acceptance|

待补：先取得有效测量，再验BPM/眨眼时长/历史筛选/悬停/最大化/清空取消和确认；样本写入隔离目录。 2026-10-22按用户要求撤回侧置识别，当前只运行原CNN/dlib/光流；真人准确率与180秒实机成功仍待验，见docs/original-recognition-rollback.md。

## settings

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S045|使用电池时自动暂停相机（Mac 检测为空方法）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|
|S046|按前台/任意窗口标题关键词暂停摄像头|入口/文案可见|Mac目标 / P5-integrations|O02|无|implemented-awaiting-acceptance|
|S047|按运行进程关键词暂停全部功能|入口/文案可见|Mac目标 / P5-integrations|O02|N013, N041|implemented-awaiting-acceptance|
|S048|按窗口标题关键词暂停全部功能|入口/文案可见|Mac目标 / P5-integrations|O02|无|implemented-awaiting-acceptance|
|S049|镜像屏幕时暂停全部功能（Mac 检测为空方法）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|
|S050|快捷键总开关、亮度增减、色温切换（Mac构造时隐藏）|仅静态证据|延后确认 / deferred|无|无|original-mac-hidden-ui|
|S051|开机自启动|入口/文案可见|Mac目标 / P5-integrations|O02|N027|partial|
|S052|上传眨眼测量以供研究|入口/文案可见|Mac目标 / P5-integrations|O02|无|excluded-by-user-cloud-services|
|S053|语言选择与动态翻译|入口/文案可见|Mac目标 / P5-integrations|O03|N014, N015, N082|partial|
|S054|Beta 更新开关和版本检查|入口/文案可见|Mac目标 / P5-integrations|O02|无|excluded-by-user-cloud-services|

待补：逐个设置实测自动触发及恢复；区分用户暂停与自动暂停，重启持久化；不以勾选存在代替效果。

## legacy-screen

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S055|屏幕调节开关（Mac 调用仅存状态/日志）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|
|S056|色温预设4500/5500/6600K（Mac 控制仅日志）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|
|S057|软件-8~0/硬件0~10亮度（Mac setter为空方法）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|

待补：追踪实际调用链及Mac平台分支；当前UI无入口且部分方法空实现，首版延后，不直接重现Windows能力。

## legacy-license

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S058|Basic/Premium/试用及到期状态；当前关于页声称免费|仅静态证据|延后确认 / deferred|无|无|pending|
|S059|输入/校验许可证及错误状态|仅静态证据|延后确认 / deferred|无|无|pending|
|S060|HTTP/HTTPS 代理设置与连接验证|仅静态证据|延后确认 / deferred|无|无|pending|

待补：确认免费3.7.4是否可达；重现不依赖旧远程授权服务，保留历史分析资料。

## about

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S061|关于、FAQ、隐私、支持邮箱、Facebook、合作组织、捐赠|入口/文案可见|Mac目标 / P1-shell|O01, O05|N028|implemented-awaiting-acceptance|
|S062|第三方许可 notices.pdf|部分行为已观察|Mac目标 / P1-shell|O15|N028|partial|

待补：新版关于页已接线7个原作参考外链和独立项目声明，既有N028已确认入口可见；仍需逐一验证实际打开目的地，不能将原站内容当作新版政策。

## internal-candidate

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S063|休息期间相机判断在席（尚无已知 UI 入口）|仅静态证据|延后确认 / deferred|无|无|pending|
|S064|相机 backend 切换信号（尚无已知 UI 入口）|仅静态证据|延后确认 / deferred|无|无|pending|
|S065|自动亮度调节信号（非 Mac 有效功能证据）|仅静态证据|延后确认 / deferred|无|无|original-mac-noop-or-unreachable|

待补：定位真实调用者及入口；确认是否参与当前Mac行为，不凭符号名纳入用户功能。

## updater

|ID|功能|原版证据|范围/阶段|原版体验|新版实测|实现状态|
|---|---|---|---|---|---|---|
|S066|版本提示、下载进度、取消、损坏重下和安装流程|仅静态证据|延后确认 / deferred|无|无|excluded-by-user-cloud-services|

待补：用户2026-10-19明确选择保留本机完整功能，旧研究上传、Beta及云更新服务暂不接入；重新启用时需新的服务配置及验收。

每项静态英文引文、地址见 `evidence/static/feature-candidates.json`；原版操作见 `catalog/observations.json`，新版实测见 `catalog/native-observations.json`。新版记录含失败和预览路径，须按记录中的状态及范围阅读，不等于整项功能已准出。S066来自QM更新器上下文。所有候选的详细边界见 `evidence/static/symbol-findings.md`。
