# 原版 CNN 人脸检测重建

本轮已确认原版使用官方 **2020-03-26 的 24 层 int8 模型参数**，使用同一官方版本的 libfacedetection V3 源码在 Apple Silicon 原生编译，并完成公开图片上的跨架构输出比较。后续已在原版代码段逐字节一致的独立调试副本中调用同图CNN，22张脸的评分/框/五点共330个整数与arm64全部一致。这个单图函数对照不能扩展为整条眨眼检测器已完全等价。

## 身份和模型

原对象为 `/Applications/eyeblink.app/Contents/MacOS/eyeblink`，SHA-256 `bd6808caee828c068c8d6614a96e9dabb9c02ecdc397d5be09da953cc6d134db`。

官方源锁定 [ShiqiYu/libfacedetection 的 2020-03-26 commit](https://github.com/ShiqiYu/libfacedetection/tree/77b54ba85601191b1ce61772e735b694faeaf714)。原二进制的 `f0_weight` 至 `f23_bias` 共 **48 个数组、2,326,816 字节全部逐字节匹配**；24 项 `param_pConvInfo` 的形状和 float32 scale 也全部精确匹配。2021 Tiny float 版、2020 后期 28 层版均不适用。

调查还比较过 2020-02-27 V3：其拓扑相同但 48 个数组都不同；直到追到 2020-03-26 的模型更新才得到完整匹配。不能凭同名 `facedetect_cnn` 或同为 V3 就选择任意版本。`weights-match-march2020.json` 为正向匹配证据，其余比较文件保留排除过程。

当前 vendor 的 `.cpp`、`-model.cpp` 与 `.h` 的 Git blob 均与上述 commit 一致（`facedetection_export.h` 仅为本项目提供的空导出宏）。原可执行文件的完整源码构建 commit 无法仅由这些匹配唯一断定，但模型 checkpoint 身份已经闭环。

`extract_model.py` 还独立通过 Mach-O 段映射和符号 VA，从原文件只读提取形状、scale、weights、biases，记录原 offset、长度及各 SHA。`materialize_official_model.py` 从这个已锁定的官方文本参数生成同一种二进制格式，结果与原文件提取物 SHA 完全一致，因此构建和安装不必依赖原 App 或 Rosetta。

生成文件放在忽略目录 `.deps/models/eyeblink-face-v3.bin`，大小 **2,327,596 字节**，SHA-256：

```
835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767
```

C API 加载器核验长度和这个完整 SHA，拒绝不匹配的模型。模型不加入源代码仓库；可通过已锁定的官方源和参数转换器重新生成，也可用本机原版独立核验。原 App、其偏好和统计文件均未改写。

对应证据：`evidence/static/recovered-face/identity.json`、`weights-match-v3.json`、`weights-match-latest2020.json`、`weights-match-march2020.json`、`extracted-model.json`、`official-model-materialization.json`、`compare_weights.py`、`extract_model.py`、`materialize_official_model.py`。

## 恢复的输入、输出及选脸规则

- `Model::detectBestNearestFace2` 位于原 VA `0x10013f200`。先将 OpenCV BGR 图以 `.25/.25` 缩小，插值为 `INTER_AREA`，再调用 `facedetect_cnn`（`0x10018efb0`）。`.25` 和输出 `4.0` 常量已从原文件读取。
- CNN 原输出是 int32 数量加每项 142 个 int16。`p[0] = short(score * score * 100)`；`p[1...4]` 为 x、y、w、h；`p[5...14]` 为五点 landmark。坐标回到原图时乘 4。
- CNN `detection_output` 参数为 overlap `0.3`、confidence `0.5`、top_k `1000`、keep_top_k `100`。原常量和调用已逐项对照。
- 无上一人脸时，仅保留 quarter 图 width ≥25（原图 width ≥100）且整数 score ≥90 的候选，选择**最大宽度**。相同宽度保留先出现者。
- 有上一人脸时，要求 width ≥25、score ≥40，然后选与上一框中心平方距离最小者。相同距离保留先出现者。
- 这条路径支持从多张脸中选择跟踪对象；不能因为原始候选数大于 1 就拒绝整个帧。
- 框按原分支裁切：x/y 至少 0；width/height 至多原图维度减原 x/y 再减 3。左右眼取 CNN 前两组 landmark，初始 eyeWidth 为原图框宽的一半。

对应证据：`detectBestNearestFace2.llvm.txt`、`facedetect_cnn.llvm.txt`、`objectdetect_cnn.llvm.txt`；C API 位于 `Sources/CFaceDetector/include/FaceDetector.h`。

## arm64 实现及使用

保留官方三个 C++ 文件与 BSD-3-Clause 声明，放在 `Sources/CFaceDetector/vendor/`。只有 `FaceDetector.cpp` 是本项目适配器。所有调用由同一互斥锁串行执行，避免上游全局 filter 初始化与并发检测竞态。

不要启用该旧版本的 `_ENABLE_NEON`：这个宏会把激活值范围从 255 改成 127，改变原版推理。原二进制实际采用普通 uint8×int8 点积，再由编译器生成 SSE4.1；arm64 同样用 portable 分支，由 clang 自动向量化。构建保留 `-ffp-contract=off`，避免合并乘加改变 float 量化。

```c
int eyeface_load_model(const char *path, char *error, size_t capacity);
int eyeface_detect_bgra(const uint8_t *pixels, int w, int h, int stride,
                       EyeFaceDetection *output, int capacity);
int eyeface_detect_bgr(const uint8_t *quarterBGR, int w, int h, int stride,
                      EyeFaceDetection *output, int capacity);
int eyeface_select(const EyeFaceDetection *faces, int count, int frameW, int frameH,
                   const EyeFaceRect *previousOrNull, EyeFaceSelection *output);
```

`detect_bgra` 包含 BGR 转换及 quarter resize；`detect_bgr` 的输入已是 quarter 图，但输出仍是原图坐标。返回 -1 表示不可检测，返回 0 表示合法图像没有候选。`select` 返回 1 才能将该帧交给五点/光流路径。`EyeFaceSelection` 提供裁切框、眼点、eyeWidth 和所选 candidateIndex。

应用层须在租约变化、设备变化或检测中断时丢弃上一框；不能让旧设备的选框继续影响新设备。

适配器明确增加了两项输入保护：quarter 图任一边小于 64 时返回错误（避免上游深层 pooling 产生空尺寸后误报零人脸）；裁切结果非正尺寸时返回选择失败。它们不是原版行为证据。

## 已执行验证

1. Apple Silicon arm64 原生编译 C API，黑色 640×480 BGRA 输入返回 0 人脸。
2. 初始最大宽度、跟踪最近中心、40 分边界、空候选共 4 个选脸夹具通过。
3. 16 个并发检测请求全部完成，均返回零候选；上游全局状态通过锁隔离。
4. 官方公开 `images/cnnresult.png`（1280×960）检出 22 张脸，原始 BGRA 接口和同图 quarter BGR 接口的全部 score、rect、landmark 精确一致，初次选择 candidateIndex=1。
5. 用相同源码和**提取的原参数**另编 x86_64 参考 CLI，只对同一 quarter BGR 文件运行。其 22 张脸所有整数输出与 arm64 完全一致。这个参考 CLI 是新编译程序，不是原 App；最终应用仍只有 arm64 运行时。

图片 SHA、输入 SHA、22 项原始输出及比较范围见 `architecture-comparison.json`、`image-results.json`、`x86-reference-results.json`。黑图和并发结果见 `contract-results.json`。测试 helper 放在同一证据目录，模型和图片位于忽略的 `.deps`。

重跑原生契约：`bash evidence/static/recovered-face/build-and-check.sh`。需要额外比较新编译的 x86 参考 CLI 时加 `--with-x86-reference`；该参考步骤不属于应用的运行时依赖。转换器会校验官方参数文本的 SHA，再原子生成已验证的模型文件。

## 原Model输入/选脸与眼区几何对照

后续在上述代码节一致的调试副本中调用真实`Model::detectBestNearestFace2`（VA`0x10013f200`）。使用1280×960公开图完整BGR与640×480纯黑BGR，各执行`selection-cases.txt`中6组上一脸条件。原函数自行完成quarter缩放、原CNN和选择；arm64端调用生产`eyeface_detect_bgra`与`eyeface_select`。12个条件的候选数、成功/失败、所选框、双眼中心及宽度全部一致，公开图22候选、黑图0候选。

同一隔离进程中给原`Model::detectEyes`（VA`0x10013fbe0`）提供8组公开dlib参考点的ABI夹具，眼宽scale按原init设2.0，得到48个眼区中心/宽度数值。输入点不是原shape_predictor实时执行结果。生产CameraPipeline已接入Core的`EyeGeometry`，测试夹具直接由原输出生成；保留整数距离四舍五入后乘2的眼宽、Float中心、caller中`sqrt(dx²−dy²)`及分别平方的Float运算顺序。不能把减号换成欧式距离。

证据`evidence/native-tests/original-selection-comparison.json`、`original-selection-results.json`、`original-eye-geometry-results.json`、`arm64-selection-full.json`、`arm64-selection-black.json`。新增2项Swift回归，全套83项通过；release优化下2项几何回归也通过。`original_selection_probe.py`沿用同一已核验副本，在main前调用Model构造并只初始化CNN缓冲区；不执行Model.init、相机或main。原5个用户数据文件哈希保持不变。

复现入口：`xcrun lldb --batch -o 'command script import evidence/static/recovered-face/original_selection_probe.py' -o original-selection-probe`。发布App仍仅arm64，调试副本及测试资源不进入包。

## 未闭环项与下一步

- **完整原构建身份未唯一确认**：模型参数和所用官方实现的源码 blob 已锁定，但这不代表整个 eyeblink 程序来自该同一 Git commit，也不能替代对实际原函数输出的验证。
- **单图原始CNN函数输出已取得**：原安装包带Hardened Runtime，直接LLDB入口探测lost connection；独立副本只改调试签名，原版所有有文件内容的节的哈希一致，`__TEXT,__text` SHA为`7a8f23e4d75f712c9dcd66a6e8db71dcd7b392a8e06fca0fcf21c546c1608536`。副本在main第一条指令前断住，以相同quarter BGR输入调用原VA `0x10018efb0`。22张脸的评分、框和五点共330整数与既有arm64结果逐项一致。main未执行，探测进程已结束，原5个用户数据文件哈希保持一致。调试副本只在忽略的`.deps/`，不进入原生发布包。证据`evidence/native-tests/original-cnn-comparison.json`、`original-cnn-probe-identity.json`、`original-cnn-result.json`、`original-cnn-debug-run.log`及脚本`evidence/static/recovered-face/original_cnn_debug_probe.py`。它仍不覆盖原Model的完整灰度/裁眼/实际Farneback/最终眨眼序列。
- **真实相机闭环仍属于应用验收**：设备输入、相机租约、CNN 选框、原五点参数、Farneback、双眼状态机到训练关闭/180 秒统计的链路，不能由这些独立 CLI 夹具替代。
- 还需用小脸、多脸、边缘脸、低照及帧间目标移动的冻结序列覆盖 source 分支，记录原版与重建差异。目录中的静态 feature 验收状态未因此被改成通过。

复现单图原函数对照（从项目根目录，需本机已安装的SHA匹配原版与既有BGR夹具）：

```sh
python3 evidence/static/recovered-face/prepare_original_cnn_probe.py
xcrun lldb --batch -o 'command script import evidence/static/recovered-face/original_cnn_debug_probe.py' -o original-cnn-probe
```

准备器只签名忽略目录的独立副本；调用前再次核对副本整文件SHA与节一致性报告。不得用这份Intel调试副本作为arm64产品依赖。

后续组件补证：真实原shape-predictor读取/推理8组40点与Swift相等；原calcAvgYandStdDev9组与修复后生产统计函数精确一致，见N045/N046。固定输入组件一致仍不代替完整跟踪和眨眼序列对照。
