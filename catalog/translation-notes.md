# 简体中文翻译初稿说明

`zh-CN.draft.json` 与 `evidence/static/localization-source-catalog.json` 的 237 条消息逐条对应，保持顺序及 context/source/comment，不新增、不删除。全部为 draft，尚未装入重现应用或经过真实界面验收。

已做静态校验：237 个键一一对应；翻译均非空；占位符数量与名称完全一致；4 条 HTML 的标签、属性、href URL 保持原样；相同英文源文本在不同上下文使用相同译文。`Version %1 of %2` 为符合中文语序改成“%2 的 %1 版本”，保留两个占位符。

统一术语：Blink training＝眨眼训练；Computer breaks＝离屏休息；Blink rate＝眨眼频率；Meibomian gland dysfunction/MGD＝睑板腺功能障碍；presentation mode＝演示模式；bpm/BPM＝次/分钟；Eye exercises＝眼部练习；License＝许可证；Proxy＝代理。

## 需要结合界面确认的文本

- `Downloader` 的独立 `of` 初译为“/”，用于下载进度中“已下载量 / 总量”的组合表达。实际控件拼接方式待验证；若是完整句子的组成部分，应根据最终布局调整。
- `Consider` 与 `of no mouse or keyboard activity as a break` 分别译为“将”和“无鼠标或键盘操作视为一次休息”，预期组合为“将［时长］无鼠标或键盘操作视为一次休息”。须与中间的数值及单位控件一起检查。
- `I stand up from my desk and take a break each` 译为“我起身离桌休息的间隔为”，随后接时长控件；应在真实布局中检查阅读顺序。
- 训练说明包含多行 CPU 与 Windows 电源设置文本。保留数值、含义及 5 行结构，但原版固定行宽未必适合中文，需要布局验收。
- `healthy` 图表标签译为“健康”；所指是原版参考范围，初稿未添加其阈值、医疗定义或有效性解释。
- 独立 `INSERT` 译为“输入”，当前语境为提交许可证的按钮，最终可根据复刻交互改为更明确的“验证”；本稿没有擅自改变其动作含义。
- `The reminder will be shown to use drag and drop.` 英文较含混，结合原版“更改提醒位置”的入口，初译为“显示提醒，以便通过拖动调整位置”；需要实际拖拽定位交互核对。

## 原文语气和历史范围

- “我的工作比我的静脉和眼睛更重要”“我的工作比我的眼睛更重要”均忠实保留了原文的责备语气。后续产品文案可单独讨论“跳过本次休息/练习”等改写；本初稿未改变原义。
- 关于页“完全免费”、对 2022 年新版本的期待、试用/高级版许可证、代理、Windows PATH/wmic.exe、隐私设置和屏幕调节等文本均保留并翻译。它们属于静态历史范围，不代表新版实现范围或当前 macOS 有效功能。
- 旧版关于干眼、静脉曲张、亮度与眨眼关系、医生建议及 CPU 占用的表述按原文翻译，未增加保证、疗效或更新事实。这些是旧应用的原文陈述，初稿不表示已独立验证。
- URL、data.dat、wmic.exe、Windows PATH、版本占位符、程序名及示例进程名保持技术标识。没有新增中文网站或改写链接目的地。
