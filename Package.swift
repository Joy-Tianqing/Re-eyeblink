// swift-tools-version: 6.0
import PackageDescription
import Foundation

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let opencvRoot = projectRoot + "/.deps/opencv-install"

let package = Package(
    name: "ReEyeblink",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EyeblinkCore", targets: ["EyeblinkCore"]),
        .executable(name: "Eyeblink", targets: ["EyeblinkApp"])
    ],
    targets: [
        .target(name: "EyeblinkCore"),
        .target(name: "CEyeFlow", exclude: ["Tests"], publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-ffp-contract=off", "-I" + opencvRoot + "/include/opencv4"])],
                linkerSettings: [.unsafeFlags(["-L" + opencvRoot + "/lib", "-lopencv_video", "-lopencv_imgproc", "-lopencv_core", "-lc++", "-lz"])]),
        .target(name: "CFaceDetector", exclude: ["vendor/LICENSE"], publicHeadersPath: "include",
                cxxSettings: [.unsafeFlags(["-ffp-contract=off", "-I" + opencvRoot + "/include/opencv4"])],
                linkerSettings: [.unsafeFlags(["-L" + opencvRoot + "/lib", "-lopencv_imgproc", "-lopencv_core", "-lc++", "-lz"])]),
        .executableTarget(name: "EyeblinkApp", dependencies: ["EyeblinkCore", "CEyeFlow", "CFaceDetector"], resources: [.process("Resources")]),
        .testTarget(name: "EyeblinkCoreTests", dependencies: ["EyeblinkCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "EyeblinkAppTests", dependencies: ["EyeblinkApp", "EyeblinkCore", "CEyeFlow", "CFaceDetector"], resources: [.copy("Fixtures")])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
