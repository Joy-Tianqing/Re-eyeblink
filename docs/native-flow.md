# Apple Silicon 原生光流检测

## 依赖与构建

使用官方 OpenCV **4.4.0** 源码，与原应用静态线索中的版本一致。源码从以下地址下载到本项目 `.deps/`，不修改全局工具环境：

- URL：`https://codeload.github.com/opencv/opencv/tar.gz/refs/tags/4.4.0`
- SHA-256：`bb95acd849e458be7f7024d17968568d1ccd2f0681d47fd60d34ffb4b8c52563`
- 本机复用工具：`/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/tools/cmake/bin/cmake`，已检查为 **CMake 3.24.3，含 arm64 的 Universal Mach-O**。
- 命令：`scripts/build-opencv.sh`。可通过 `EYEFLOW_CMAKE` 指定已有 CMake，通过 `EYEFLOW_JOBS` 调整并行度。
- 安装目标：`.deps/opencv-install/include/opencv4/` 与 `.deps/opencv-install/lib/`。
- 日志：`.deps/opencv-configure.log`、`opencv-build.log`、`opencv-install.log`。源码哈希不匹配会停止，保留原归档供检查；重复执行复用源码及构建缓存。

仅构建静态 `core`、`imgproc`、`video`，Release、PIC、arm64，部署目标 macOS 14。关闭测试、性能程序、示例、应用、Python/Java、GUI、摄像头/视频I/O、FFmpeg、IPP、OpenCL、CUDA、Accelerate/LAPACK、Eigen、TBB/OpenMP和额外图像编解码器。禁用 intrinsics 与 CPU dispatch，先以同版本标量实现建立基线。AppKit/AVFoundation 负责实际设备采集，不通过 OpenCV 打开相机。

OpenCV 的源码与静态库属于本机依赖缓存，不提交原版 Intel 库或安装包。分发新版时须随应用附带此版本 OpenCV 的第三方许可。

静态链接顺序为 `opencv_video`、`opencv_imgproc`、`opencv_core`，另链接系统 `c++` 与 `z`。旧版 bundled zlib 与当前 macOS SDK 的 `fdopen` 声明冲突，构建脚本明确选择 macOS SDK 的系统 `libz.tbd`，避免引入额外旧版压缩库。主 BSD 许可与内置 SoftFloat 许可位于 `.deps/opencv-install/share/licenses/opencv4/`。

## C 接口

声明位于 `Sources/CEyeFlow/include/CEyeFlow.h`，实现位于 `Sources/CEyeFlow/CEyeFlow.cpp`。

```c
EFContext *ef_create(void);
void ef_destroy(EFContext *context);
void ef_reset(EFContext *context);
int ef_prepare_gray(const uint8_t *bgra, int width, int height, size_t stride,
                    int apply_blur, uint8_t *output, size_t output_stride);
int ef_process(EFContext *context, const uint8_t *bgra,
               int width, int height, size_t stride,
               EFEye left, EFEye right, double normalizer, EFResult *result);
```

`EFEye` 含 `center_x / center_y / width`；`width = 2 * round(hypot(该眼两个关键点的差))`。`normalizer` 是原算法另行计算的双眼中心距离：`sqrt((Ax−Bx)^2−(Ay−By)^2)`。这里保留源算法的减号，不擅自改为欧氏距离。

`ef_prepare_gray` 使用 OpenCV 自身的 BGRA→灰度转换，`apply_blur=0` 输出原始灰度，`=1` 再加 3×3 box blur（BORDER_DEFAULT=4）。该函数无状态，返回 `EF_OK` 或负错误状态；源与输出 buffer 不得重叠。**原版 dlib 使用当前帧未模糊灰度，因此调用方传 0。**

每次传入**当前帧**眼坐标和当前 normalizer。接口内部缓存前帧灰度图、眼坐标及 normalizer；真正计算时使用缓存的前帧坐标与 normalizer。调用方不必另外维护 previous eyes。图像数据只在调用期间读取，函数返回前灰度图已经由 OpenCV 分配；不会保留输入 BGRA 指针。

`EFResult` 含左右眼的 `mean_y`、`stddev_y`（总体标准差）及 `sample_count`。返回 `EF_OK=1` 表示帧间运算成功，`EF_WARMUP=0` 表示首帧/分辨率改变，负数为无效输入或处理异常。无效输入、异常、显式 reset 都会清掉前帧；无脸、摄像头切换及采集中断时，调用方应调用 reset。每个 context 只在同一串行队列使用。

`EF_OK` 不保证两眼一定有可用样本。原算法中 ROI 太小或没有有效光流时，该眼返回 `sample_count=0 / mean_y=0 / stddev_y=0`。normalizer 为 NaN 时，不使用 `fmax` 或改写距离公式掩盖它；在有样本时结果保留 NaN，让上层按无效检测处理。

## 已恢复的原算法规则

证据及反汇编路径见 [recovered-rules.md](recovered-rules.md) 的 `EyeBlinkController::model()` 与 `calcAvgYandStdDev` 条目。

1. 当前 BGRA 转灰度，**当前帧不模糊**。对缓存的上一帧调用 `cv::blur`，`3 × 3`，anchor `(-1,-1)`，border type `4`。原版初始预读帧已 blur 一次，首对计算前再次 blur，因而首对前帧双 blur；之后每个前帧 blur 一次。这个不对称来自源码地址/对象跟踪，不改写成两帧均 blur。
2. 每眼以前帧坐标裁切：`r=trunc(prevWidth×0.5)`，`x=max(trunc(prevX)−r,1)`，`y=max(trunc(prevY)−r,1)`，`side=max(min(prevWidth,cols−2−x,rows−2−y),0)`。**同一个 rect 同时裁前帧与当前帧**。`side<6` 时该眼输出零值。
3. `cv::calcOpticalFlowFarneback(blurredPreviousROI,unblurredCurrentROI,flow,0.5,3,15,3,5,1.2,0)`。完成后将当前未模糊灰度作为新的 previous 缓存。
4. `sampleR=trunc(side×0.5)`；取以 `(sampleR,sampleR)` 为中心、严格 `sqrt(dx²+dy²)<sampleR/2.0` 的像素。`/2` 为实数运算。仅纳入 `flowX²+flowY²<225` 的向量。
5. `value=flowY/denominator`，`denominator` 为保留 NaN 语义的 `maxss(1,prevNormalizer)`。计算平均与总体标准差；零样本返回零。

当前 C 接口负责灰度预处理与光流统计。人脸/关键点推理、原眨眼状态机、相机生命周期及测量入库由上层负责。使用相同 OpenCV 版本和参数不等于已证明原软件与新软件在真实摄像头下逐帧等价；该结论仍需实机对照证据。

## 验证状态

已从固定源码完成三份静态库构建，`lipo -archs` 对每份均只返回 `arm64`，约 `4.0M + 4.0M + 405K`。C 接口在此环境以 UndefinedBehaviorSanitizer 执行 **27 项检查通过**：OpenCV 灰度定点转换、可选 blur、小图边界、静止均匀图像、向下 1 像素平移、前帧 ROI、重置、分辨率改变、非法输入/stride、NaN normalizer 传播与小 ROI 零输出。首对的原版非对称 blur 保留，不能要求任意纹理静止图都严格零光流。

回归源为 `Sources/CEyeFlow/Tests/flow-contract.cpp`，此目录应从 SwiftPM 库 target 中排除。执行方式：

```sh
clang++ -std=c++17 -arch arm64 -mmacosx-version-min=14.0 \
  -fsanitize=undefined -fno-omit-frame-pointer \
  -ISources/CEyeFlow/include -I.deps/opencv-install/include/opencv4 \
  Sources/CEyeFlow/CEyeFlow.cpp Sources/CEyeFlow/Tests/flow-contract.cpp \
  -L.deps/opencv-install/lib -lopencv_video -lopencv_imgproc -lopencv_core -lz \
  -o .deps/flow-contract-ubsan
.deps/flow-contract-ubsan
```

本机 AddressSanitizer 运行未完成：进程采样显示在进入 `main` 之前，Clang 17 的 ASAN 初始化在 macOS 26.7.1 系统分配器中递归自旋。已停止该测试进程，未将其记为检查通过。UBSAN 运行正常。

应用相机实测、前帧/当前帧与原软件的对照仍待完成；构建、C 接口回归不能代替完整眨眼验收。
