#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
python3 scripts/prepare-models.py
if [[ ! -f .deps/opencv-install/lib/libopencv_video.a ]] || \
   ! python3 scripts/patch-opencv.py --check-install; then
  scripts/build-opencv.sh
fi
binary_dir="$(xcrun swift build -c "$configuration" --arch arm64 --show-bin-path)"
# SwiftPM does not track archives passed through -L/-l as declared inputs.
# A dependency-only rebuild must still relink the application.
dependency_fingerprint="$(python3 - <<'PY'
from pathlib import Path
import hashlib
root = Path('.deps/opencv-install/lib')
for module in ['core', 'imgproc', 'video']:
    print(module + ':' + hashlib.sha256((root / ('libopencv_' + module + '.a')).read_bytes()).hexdigest())
PY
)"
link_stamp="$binary_dir/.eyeblink-opencv-link-inputs.sha256"
if [[ ! -f "$link_stamp" ]] || [[ "$(<"$link_stamp")" != "$dependency_fingerprint" ]]; then
  rm -f "$binary_dir/Eyeblink"
fi
xcrun swift build -c "$configuration" --arch arm64
printf '%s\n' "$dependency_fingerprint" > "$link_stamp"
app_dir="${EYEBLINK_APP_OUTPUT:-$PWD/build/Eyeblink.app}"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Eyeblink" "$app_dir/Contents/MacOS/Eyeblink"
cp packaging/Info.plist "$app_dir/Contents/Info.plist"
cp packaging/Eyeblink.icns "$app_dir/Contents/Resources/Eyeblink.icns"
if [[ ! -f .deps/models/data.dat ]]; then
  echo "Missing model: restore the SHA-verified local original model to .deps/models/data.dat" >&2
  exit 1
fi
cp .deps/models/data.dat "$app_dir/Contents/Resources/data.dat"
cp .deps/models/eyeblink-face-v3.bin "$app_dir/Contents/Resources/eyeblink-face-v3.bin"
mkdir -p "$app_dir/Contents/Resources/Licenses"
cp LICENSE "$app_dir/Contents/Resources/Licenses/Re-eyeblink-LICENSE.txt"
cp NOTICE "$app_dir/Contents/Resources/Licenses/Re-eyeblink-NOTICE.txt"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.md"
cp .deps/opencv-install/share/licenses/opencv4/*.txt "$app_dir/Contents/Resources/Licenses/"
cp Sources/CFaceDetector/vendor/LICENSE "$app_dir/Contents/Resources/Licenses/libfacedetection-LICENSE.txt"
cp packaging/Licenses/dlib-LICENSE.txt "$app_dir/Contents/Resources/Licenses/dlib-LICENSE.txt"
# Release tests can leave their fixture bundles beside the executable. Package
# only the resource target used by the app, never the test fixture targets.
resource_bundle="$binary_dir/ReEyeblink_EyeblinkApp.bundle"
if [[ ! -d "$resource_bundle" ]]; then
  echo "Missing app resource bundle: $resource_bundle" >&2
  exit 1
fi
rm -rf "$app_dir/Contents/Resources/ReEyeblink_EyeblinkCoreTests.bundle"
cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
signing_identity="${EYEBLINK_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(python3 scripts/signing-identity.py)"
fi
codesign --force --deep --sign "$signing_identity" "$app_dir"
file "$app_dir/Contents/MacOS/Eyeblink"
codesign --verify --deep --strict "$app_dir"
echo "$app_dir"
