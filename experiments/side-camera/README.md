# 侧置识别离线可行性探针

设计入口：[side-camera-design.md](../../docs/side-camera-design.md)。目前仅探测Vision的API、元数据和单图请求时延，没有接入生产检测，也没有优化效果结论。

使用项目既有公开裁剪`.deps/eye-tracking/face.bgr`，SHA为`75518f3e95798508647459687a79b6544525dd112bba62d75aaf971dc6034116`；格式为两个little-endian Int32宽高与紧密BGR像素。不访问真实相机或用户数据，不重新构建正式App。

从项目根运行：

```sh
xcrun swiftc -O -target arm64-apple-macos14.0 experiments/side-camera/vision-feasibility.swift -o .deps/side-camera-vision-probe
.deps/side-camera-vision-probe .deps/eye-tracking/face.bgr 640 480 20 > evidence/native-tests/side-camera-vision-implicit-pose.json
.deps/side-camera-vision-probe .deps/eye-tracking/face.bgr 640 480 20 --explicit-pose > evidence/native-tests/side-camera-vision-feasibility.json
python3 - <<'PY'
from pathlib import Path
import struct
Path('.deps/side-camera-black.bgr').write_bytes(struct.pack('<2i',640,480)+bytes(640*480*3))
PY
.deps/side-camera-vision-probe .deps/side-camera-black.bgr 640 480 1 --explicit-pose > evidence/native-tests/side-camera-vision-black-control.json
python3 experiments/side-camera/check-feasibility.py
```

隐式请求固定landmarks revision3/76点，但本机实际未返回pitch；显式先运行face rectangles revision3，再把当帧observations传入landmarks，实际返回yaw/roll/pitch。角度和点位置精度估计存在不等于准确；缺失角度不能当作0。探针处理所有检测到的人脸，生产方案仍须实现目标连续性和多人歧义处理。

报告中的冷启动和20次预热后时延仅是当前机器、640×480静态图、Vision请求耗时；不等于相机帧率、端到端预算或15–30°识别效果。最初Swift overlay误将点精度当NSNumber的编译错误保留在`side-camera-vision-overlay-compile-attempt.log`；已按真实Float类型转换。最初无8字节图像头解析的运行被输入长度守卫拒绝，未执行Vision；最终明确解析并校验宽高头。
