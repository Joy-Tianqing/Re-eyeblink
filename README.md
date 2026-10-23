# Re-eyeblink

**为 Apple Silicon Mac 重建的中文原生眨眼提醒、训练与统计工具。**

使用 SwiftUI / AppKit 重现 eyeblink 3.7.4.0 的 macOS 行为，支持简体中文和英文。相机画面在本机分析，设置和统计保存在本机。

| 平台 | 当前版本 | 许可 |
| --- | --- | --- |
| macOS 14+ · Apple Silicon（arm64） | 1.0.0（build 2） | [PolyForm Noncommercial 1.0.0](LICENSE) · 禁止未经另行授权的商业使用 |

> 本项目是独立的行为重现项目，与原版 eyeblink / Blinking Matters 无隶属或背书关系。已有可运行的原生实现，但完整行为等价和真实相机识别效果仍在验收。公开源码采用非商业许可，属于 **source-available**，不属于 OSI 定义的开源软件。

## 能做什么

- **眨眼提醒与训练**：设置提醒间隔、训练方式和反馈；相机不可用时可使用定时提醒。
- **休息与眼操**：安排离开电脑的休息及眼部练习，并可将自然离开电脑的时间计入休息。
- **眨眼测量与历史**：通过相机分析眨眼，在本机查看测量历史和统计。
- **菜单栏常驻**：关闭、隐藏或最小化普通窗口后保留菜单栏入口；打开主窗口时恢复 Dock 图标。
- **暂停与恢复**：支持手动暂停，以及锁屏、睡眠、会话等系统状态的暂停处理。
- **原生运行**：面向 Apple Silicon 构建，无需 Rosetta；当前不提供 Intel / Universal 构建。

功能追踪见 [功能清单](docs/features.md)，实际验证范围见 [原生验收记录](docs/native-acceptance.md)。本工具不用于疾病诊断或治疗。

## 从源码构建

目前没有 GitHub Release 安装包，也尚未完成 Apple 公证。克隆仓库后，需准备工具链和检测模型才能构建。

### 环境要求

- Apple Silicon Mac，macOS 14 或更新版本。
- Xcode / Command Line Tools，提供 **Swift 6.0+**、macOS SDK、Clang 和 `codesign`。
- Python 3、可原生运行于 arm64 的 CMake，以及首次下载依赖所需的网络。
- 仅维护功能目录和文档时需要 Node.js **22.19+**；构建 Swift 应用不需要 Node.js。

### 1. 获取源码

```sh
git clone https://github.com/Joy-Tianqing/Re-eyeblink.git
cd Re-eyeblink
```

### 2. 准备检测模型

**仓库不分发原版应用、五点模型或模型打包产物。** 你需要自行合法取得并有权使用匹配的原版五点模型 `data.dat`。项目许可证不授予任何原版程序或外部模型的权利。

```sh
python3 scripts/prepare-models.py /absolute/path/to/data.dat
```

脚本将模型复制到被 Git 忽略的 `.deps/models/`，校验五点模型 SHA-256，并从固定的 libfacedetection 上游版本物化 CNN 模型；不会修改原版文件。

五点模型的预期 SHA-256：

```text
c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888
```

具体模型来源、固定版本和身份校验见 [人脸检测器说明](docs/face-detector.md) 及 [CNN 模型身份记录](evidence/static/recovered-face/official-model-materialization.json)。没有匹配模型时，当前版本不能完成标准应用打包。

### 3. 构建并启动

将下面的 CMake 路径替换为本机实际路径：

```sh
export EYEFLOW_CMAKE=/absolute/path/to/cmake
bash scripts/build-app.sh release
open build/Eyeblink.app
```

首次构建会下载并编译固定版本的 **OpenCV 4.4.0**（core / imgproc / video 静态库），校验源码与兼容补丁。依赖保存在项目的 `.deps/`，应用输出为 `build/Eyeblink.app`。

构建脚本优先使用本机可用的 Apple Development 身份，无可用身份时回退到临时签名。可通过 `EYEBLINK_SIGNING_IDENTITY` 指定签名身份；本地签名不等于 Apple 公证。

## 开始使用

1. 启动应用，按需允许相机权限；拒绝权限后可在「系统设置 → 隐私与安全性 → 相机」中调整。
2. 在「眨眼训练」设置提醒方式和间隔，在「休息与眼操」配置休息计划。
3. 通过相机相关页面检查设备与预览，在「眨眼统计」查看测量结果。
4. 演示或暂时不需要提醒时，可从主窗口工具栏手动暂停；关闭主窗口后仍可通过菜单栏重新打开或退出。

识别结果会受光线、摄像头角度、遮挡和帧率影响。自动化测试通过不代表你的设备上已完成真实眨眼准确性验证。

## 隐私与本机数据

- 相机帧在本机处理，不保存或上传视频。
- 设置与统计目录：`~/Library/Application Support/ReEyeblink/`。
- Bundle ID：`org.reeyeblink.app`；与原版数据目录独立。
- 从旧开发构建升级后，macOS 会将此标识视为新应用，可能需要重新授予相机和通知权限，并重新选择摄像头及提醒位置；上述设置与统计数据目录保持不变。
- 当前未接入原版研究上传、Beta 或云更新服务。
- 构建阶段会联网下载 OpenCV 和 CNN 模型源文件；原版程序、模型、用户数据和实机日志不纳入 Git 仓库。

## 开发与验证

先完成上述依赖准备和应用构建，再运行测试：

```sh
xcrun swift test -c release --arch arm64
```

这会运行 Swift 核心逻辑和应用集成相关测试，不替代真实摄像头、屏幕状态与浮层的设备验收。

维护功能目录时可运行：

```sh
npm run generate
npm run check
```

`catalog/features.json` 是功能状态源，`docs/features.md` 由脚本生成。`npm run check` 还依赖未公开的本机调查档案，**不是干净克隆即可运行的通用 CI 检查**。历史文档中的部分 `evidence/` 链接与参考对照脚本同样仅在维护者本机可用；公开仓库只包含构建和单测必需的少量证据输入。

| 目录 | 内容 |
| --- | --- |
| `Sources/EyeblinkApp/` | SwiftUI / AppKit 界面、相机、菜单栏、提醒浮层及系统适配 |
| `Sources/EyeblinkCore/` | 调度状态机、测量、历史、关键点与眨眼判定 |
| `Sources/CEyeFlow/`、`Sources/CFaceDetector/` | OpenCV 光流与 CNN 人脸检测桥接 |
| `Tests/` | Swift 测试和参考夹具 |
| `scripts/`、`packaging/` | 构建、依赖校验、资源与打包配置 |
| `catalog/`、`docs/` | 功能追踪、设计和验收记录 |
| `experiments/` | 历史实验；不代表当前生产识别链路 |

当前识别链路为 **CNN 人脸检测 → dlib 五点关键点 → Farneback 光流 → 眨眼时序判定**。侧置轮廓和校准实验已撤出生产链路，详见 [原版识别回归记录](docs/original-recognition-rollback.md)。另见 [锁屏暂停与恢复](docs/screen-lock-pause.md)、[行为对齐记录](docs/first-four-alignment.md) 和 [重现计划及验收缺口](docs/reconstruction-plan.md)。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/Joy-Tianqing/Re-eyeblink/issues) 报告问题，提供 macOS 版本、芯片、摄像头类型、复现步骤和预期/实际结果。请勿上传个人视频、用户统计、凭据或无权分发的模型。

提交改动前请运行相关测试；行为变化应说明验证证据。贡献须为你有权提交的内容，并允许按本项目相同许可发布；第三方内容须保留原始许可和来源。

## 许可证与禁止商用

本项目中由维护者拥有权利的原创代码、文档及资源采用 **[PolyForm Noncommercial License 1.0.0](LICENSE)**。

- 允许按许可证进行非商业使用、学习、研究、修改和再分发。
- 未经权利人另行书面授权，不得进行商业使用，包括商业销售、付费服务或商业产品集成等用途。
- 再分发需保留许可证、[Required Notice](NOTICE) 和适用的第三方声明。
- 对非商业机构等允许用途的具体定义，以英文许可证正文为准；本节是说明，不修改许可证条款。

第三方代码、依赖和模型保留各自许可，不被本项目的非商业条款重新授权。详见 [第三方声明](THIRD_PARTY_NOTICES.md)。如需商业授权，请通过 [仓库 Issue](https://github.com/Joy-Tianqing/Re-eyeblink/issues/new) 联系维护者。
