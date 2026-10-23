#!/bin/bash
# Project-local, pinned OpenCV 4.4.0. No global tools or Intel binaries installed.
set -euo pipefail

task_root="$(cd "$(dirname "$0")/.." && pwd)"
deps_root="$task_root/.deps"
source_root="$deps_root/opencv-4.4.0"
build_root="$deps_root/opencv-build"
install_root="$deps_root/opencv-install"
archive="$deps_root/downloads/opencv-4.4.0.tar.gz"
source_url="https://codeload.github.com/opencv/opencv/tar.gz/refs/tags/4.4.0"
expected_sha="bb95acd849e458be7f7024d17968568d1ccd2f0681d47fd60d34ffb4b8c52563"
cmake_tool="${EYEFLOW_CMAKE:-/Applications/Cocos/Creator/3.8.8/CocosCreator.app/Contents/Resources/tools/cmake/bin/cmake}"
jobs="${EYEFLOW_JOBS:-8}"
sdk_root="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This project builds native arm64 on an Apple Silicon Mac." >&2
    exit 1
fi
if [[ ! -x "$cmake_tool" ]]; then
    echo "Set EYEFLOW_CMAKE to an existing arm64-compatible CMake executable." >&2
    exit 1
fi
mkdir -p "$deps_root/downloads"
if [[ ! -f "$archive" ]]; then
    /usr/bin/curl --fail --location --retry 3 "$source_url" -o "$archive.part"
    mv "$archive.part" "$archive"
fi
actual_sha="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "OpenCV source checksum mismatch; archive retained for inspection: $archive" >&2
    exit 1
fi
if [[ ! -f "$source_root/CMakeLists.txt" ]]; then
    /usr/bin/tar -xzf "$archive" -C "$deps_root"
fi
python3 "$task_root/scripts/patch-opencv.py"

echo "Configuring OpenCV 4.4.0 core/imgproc/video for arm64…"
if ! /usr/bin/arch -arm64 "$cmake_tool" -S "$source_root" -B "$build_root" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$install_root" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_CXX_STANDARD=11 \
    -DCMAKE_CXX_FLAGS=-ffp-contract=off -DCMAKE_C_FLAGS=-ffp-contract=off \
    -DBUILD_LIST=core,imgproc,video -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF -DBUILD_PERF_TESTS=OFF -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOCS=OFF -DBUILD_opencv_apps=OFF -DBUILD_JAVA=OFF \
    -DBUILD_ZLIB=OFF -DZLIB_LIBRARY="$sdk_root/usr/lib/libz.tbd" \
    -DZLIB_INCLUDE_DIR="$sdk_root/usr/include" -DWITH_QUIRC=OFF \
    -DBUILD_opencv_python2=OFF -DBUILD_opencv_python3=OFF -DBUILD_opencv_js=OFF \
    -DWITH_IPP=OFF -DWITH_ITT=OFF -DWITH_TBB=OFF -DWITH_OPENMP=OFF \
    -DWITH_OPENCL=OFF -DWITH_OPENCLAMDBLAS=OFF -DWITH_OPENCLAMDFFT=OFF \
    -DWITH_OPENCL_SVM=OFF -DWITH_VULKAN=OFF -DWITH_CUDA=OFF \
    -DWITH_ACCELERATE=OFF -DWITH_LAPACK=OFF -DWITH_EIGEN=OFF \
    -DCV_ENABLE_INTRINSICS=OFF -DCPU_BASELINE= -DCPU_DISPATCH= \
    -DENABLE_NEON=OFF -DENABLE_VFPV3=OFF \
    -DWITH_QT=OFF -DWITH_GTK=OFF -DWITH_OPENGL=OFF \
    -DWITH_AVFOUNDATION=OFF -DWITH_FFMPEG=OFF -DWITH_GSTREAMER=OFF \
    -DWITH_1394=OFF -DWITH_V4L=OFF -DWITH_MSMF=OFF \
    -DWITH_JPEG=OFF -DWITH_PNG=OFF -DWITH_TIFF=OFF \
    -DWITH_WEBP=OFF -DWITH_OPENEXR=OFF -DWITH_JASPER=OFF \
    -DWITH_PROTOBUF=OFF -DWITH_ADE=OFF \
    > "$deps_root/opencv-configure.log" 2>&1; then
    tail -80 "$deps_root/opencv-configure.log" >&2
    exit 1
fi
echo "Building static libraries ($jobs jobs); log: .deps/opencv-build.log"
if ! /usr/bin/arch -arm64 "$cmake_tool" --build "$build_root" --parallel "$jobs" \
    > "$deps_root/opencv-build.log" 2>&1; then
    tail -100 "$deps_root/opencv-build.log" >&2
    exit 1
fi
if ! /usr/bin/arch -arm64 "$cmake_tool" --install "$build_root" \
    > "$deps_root/opencv-install.log" 2>&1; then
    tail -80 "$deps_root/opencv-install.log" >&2
    exit 1
fi
for module in core imgproc video; do
    library_arch="$(/usr/bin/lipo "$install_root/lib/libopencv_${module}.a" -archs)"
    if [[ "$library_arch" != "arm64" ]]; then
        echo "Unexpected architecture in libopencv_${module}.a: $library_arch" >&2
        exit 1
    fi
done
mkdir -p "$install_root/share/licenses/opencv4"
cp "$source_root/LICENSE" "$install_root/share/licenses/opencv4/OpenCV-LICENSE.txt"
cat > "$install_root/SOURCE.txt" <<EOF
OpenCV 4.4.0
URL: $source_url
SHA256: $expected_sha
Architecture: arm64
Modules: core,imgproc,video
FP_CONTRACT=OFF
EOF
python3 - "$task_root" >> "$install_root/SOURCE.txt" <<'PY'
from pathlib import Path
import json, sys
entry = json.loads((Path(sys.argv[1]) / 'scripts/opencv/patch.json').read_text())
print(entry['marker'])
print('PATCH_SHA256=' + entry['patchSHA256'])
PY
echo "OpenCV arm64 headers and static libraries are ready: $install_root"
