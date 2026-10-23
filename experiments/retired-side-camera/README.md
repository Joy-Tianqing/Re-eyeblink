# 已撤回的侧置识别实验

2026-10-22，按用户要求回归原版识别。此目录保存撤回前的轮廓检测、空间目标锁定及对应测试，供追溯旧证据；不在 SwiftPM Sources/Tests 下，不编译、不打包，也不是备用开关。

历史中的 `side-contour-v1` 至 `v4` 元数据仍由 `Sources/EyeblinkCore/MeasurementDetection.swift` 兼容读取。新检测只使用已恢复的 CNN / dlib / Farneback 链路。旧实验测试包含被撤回的接口，仅供历史参考，不能当作当前测试套件。
