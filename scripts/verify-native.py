"""Read-only arm64 bundle and source snapshot verification."""
from pathlib import Path
import subprocess
import hashlib
import json
import datetime
import sys
import plistlib

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / 'build/Eyeblink.app'

def run(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

objects = []
for path in sorted(app.rglob('*')):
    if not path.is_file(): continue
    description = run('file', '-b', str(path))
    if 'Mach-O' not in description: continue
    archs = run('lipo', '-archs', str(path)).split()
    if archs != ['arm64']: raise SystemExit(f'Unexpected runtime architecture: {path}: {archs}')
    objects.append({'path': str(path.relative_to(app)), 'architectures': archs, 'sha256': sha(path)})
assert objects, 'No Mach-O found'
assert not list((app / 'Contents/Resources').rglob('*Tests.bundle')), 'Test fixture resources must not ship in the app'
assert (app / 'Contents/Resources/ReEyeblink_EyeblinkApp.bundle').is_dir(), 'Missing runtime app resources'
run('codesign', '--verify', '--deep', '--strict', str(app))
license_sources = {
    'dlib-LICENSE.txt': root / 'packaging/Licenses/dlib-LICENSE.txt',
    'libfacedetection-LICENSE.txt': root / 'Sources/CFaceDetector/vendor/LICENSE',
    'OpenCV-LICENSE.txt': root / '.deps/opencv-install/share/licenses/opencv4/OpenCV-LICENSE.txt',
    'SoftFloat-COPYING.txt': root / '.deps/opencv-install/share/licenses/opencv4/SoftFloat-COPYING.txt',
}
licenses = {}
for name, source in license_sources.items():
    packaged = app / 'Contents/Resources/Licenses' / name
    assert packaged.is_file(), f'Missing packaged license: {name}'
    assert packaged.read_bytes() == source.read_bytes(), f'Packaged license drift: {name}'
    licenses[name] = sha(packaged)
binary = app / 'Contents/MacOS/Eyeblink'
asset_expectations = {
    'data.dat': 'c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888',
    'eyeblink-face-v3.bin': '835305bfac324d22102580f598a7df6419378b7d68138c085c43665a977d7767',
    'Eyeblink.icns': sha(root / 'packaging/Eyeblink.icns'),
}
assets = {}
for name, expected in asset_expectations.items():
    packaged = app / 'Contents/Resources' / name
    assert packaged.is_file(), f'Missing runtime asset: {name}'
    assets[name] = sha(packaged)
    assert assets[name] == expected, f'Packaged runtime asset drift: {name}'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
source_info = plistlib.loads((root / 'packaging/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == source_info['CFBundleShortVersionString'] == json.loads((root / 'package.json').read_text())['version'], 'Packaged version drift'
assert info['CFBundleVersion'] == source_info['CFBundleVersion'], 'Packaged build number drift'
assert info['CFBundleIdentifier'] == 'org.reeyeblink.app', 'Unexpected bundle identifier'
assert info['CFBundleExecutable'] == 'Eyeblink', 'Unexpected bundle executable'
assert info['LSMinimumSystemVersion'] == '14.0', 'Unexpected minimum macOS version'
assert info.get('NSCameraUsageDescription'), 'Missing camera permission explanation'
links = run('otool', '-L', str(binary))
for line in links.splitlines()[1:]:
    dependency = line.strip().split(' (')[0]
    if not dependency.startswith(('/usr/lib/', '/System/Library/')):
        raise SystemExit(f'Unexpected non-system dynamic dependency: {dependency}')
source_paths = [root / 'Package.swift']
opencv_build = (root / '.deps/opencv-install/SOURCE.txt').read_text()
assert 'FP_CONTRACT=OFF' in opencv_build.splitlines(), 'OpenCV must disable floating-point contraction'
run('python3', str(root / 'scripts/patch-opencv.py'), '--check-install')
source_paths += [p for directory in ['Sources', 'Tests', 'scripts', 'packaging'] for p in sorted((root/directory).rglob('*')) if p.is_file()]
report = {
    'date': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'scope': 'bundle-architecture-signature-and-source-snapshot-only',
    'status': 'PASS', 'app': str(app), 'machO': objects, 'dynamicDependencies': links, 'licensesSHA256': licenses,
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'runtimeAssetsSHA256': assets,
    'opencvBuild': opencv_build,
    'opencvArchiveSHA256': {name: sha(root / '.deps/opencv-install/lib' / ('libopencv_' + name + '.a')) for name in ['core', 'imgproc', 'video']},
    'sources': {str(p.relative_to(root)): sha(p) for p in source_paths},
    'limitations': ['Not notarized', 'No real-camera acceptance claim', 'No full original-app equivalence claim']
}
output = root / 'evidence/native-build.json'
output.write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
print(f'PASS: {len(objects)} arm64 Mach-O; signature verified; system-only dynamic dependencies; {len(licenses)} license files verified')
