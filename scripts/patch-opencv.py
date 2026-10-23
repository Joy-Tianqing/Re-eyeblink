"""Apply the one pinned compatibility patch, refusing unknown vendor source."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / 'scripts/opencv/patch.json'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    entry = json.loads(MANIFEST.read_text())
    patch = MANIFEST.parent / entry['patch']
    assert sha(patch) == entry['patchSHA256'], 'OpenCV compatibility patch drift'
    markers = ['FP_CONTRACT=OFF', entry['marker'], 'PATCH_SHA256=' + entry['patchSHA256']]
    if sys.argv[1:] == ['--check-install']:
        metadata = ROOT / '.deps/opencv-install/SOURCE.txt'
        return 0 if metadata.exists() and all(line in metadata.read_text().splitlines() for line in markers) else 1
    assert not sys.argv[1:], 'Usage: patch-opencv.py [--check-install]'
    source_root = ROOT / '.deps/opencv-4.4.0'
    source = source_root / entry['relativeSource']
    current = sha(source)
    if current == entry['patchedSHA256']:
        return 0
    assert current == entry['sourceSHA256'], 'Unknown OpenCV resize source; refusing to overwrite'
    subprocess.run(['/usr/bin/patch', '--batch', '--forward', '-p1', '-i', str(patch)], cwd=source_root, check=True)
    assert sha(source) == entry['patchedSHA256'], 'Unexpected patched OpenCV source'
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
