# Re-eyeblink

本项目重现本机 eyeblink 3.7.4.0 的 macOS 行为，默认简体中文。当前已有可运行 arm64 原生实现，完整行为等价和实机验收仍在进行。

- 首版以 Apple Silicon（arm64）原生运行、无需 Rosetta 为硬要求；P0即验证相机/检测/浮层的arm64可行性。App、检测库、动态库、辅助进程均须支持arm64，禁止打包原版Intel二进制依赖。Intel/Universal构建不在默认首版范围。
- 从摄像头生命周期、时间调度、实际系统能力出发设计；不要把跨平台旧字符串当作本机有效功能。
- `catalog/features.json` 为功能和证据状态的编辑源；`docs/features.md` 由脚本生成。
- 翻译英文源来自 `evidence/static/localization-source-catalog.json`；中文草案为 `catalog/zh-CN.draft.json`；Qt `.ts` 是 XML 翻译文件，与 TypeScript 不同。
- 行为声明必须链接实际证据。`behavior-partial`、`ui-visible`、`static-only` 都不能写成完整运行验收通过。
- 每次实验记录「前置状态 → 一个操作 → 后置状态 + 证据」。未观察到的终态继续保留为未知。
- 调度器只保留一个相机仲裁入口。提醒、测量、预览不能各自竞争打开相机。
- 测试使用可控时间和检测事件，不缩短生产断言或改变原版场景来制造通过。
- 原应用、用户偏好与统计不作为实现输出目录。新应用使用独立 Bundle ID 和数据目录。
- 不提交安装包、模型、用户数据或机器标识。`evidence/private/` 仅本机保留。
- 未经用户要求不初始化独立 Git 仓库、不提交、不推送。保留父目录其他项目的改动。
- 如果需要 JS/TS 工具，使用 TypeScript；本机工具脚本按 package.json 的 Node 要求运行。
- `npm run check` 验证目录、证据引用、源字符串、翻译占位符和生成文件一致性；它不是原应用 E2E 验收。
