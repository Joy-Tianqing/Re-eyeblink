"""Prepare ignored model assets from verified sources; never modifies the original app."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request

root = Path(__file__).resolve().parent.parent
models = root / '.deps/models'
models.mkdir(parents=True, exist_ok=True)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

shape = models / 'data.dat'
shape_sha = 'c4b1e9804792707d3a405c2c16a80a20269e6675021f64a41d30fffafbc41888'
if not shape.exists():
    source = Path(sys.argv[1] if len(sys.argv) > 1 else '/Applications/eyeblink.app/Contents/MacOS/data.dat')
    if not source.exists() or sha(source) != shape_sha:
        raise SystemExit('Provide the SHA-verified original 5-point model as the first argument.')
    shutil.copyfile(source, shape)
if sha(shape) != shape_sha:
    raise SystemExit('Shape model integrity failure; existing file was preserved.')

face = models / 'eyeblink-face-v3.bin'
evidence = root / 'evidence/static/recovered-face'
identity = json.loads((evidence / 'official-model-materialization.json').read_text())
if not face.exists():
    source = models / 'facedetectcnn-int8data.cpp'
    if not source.exists():
        with urllib.request.urlopen(identity['officialSourceURL'], timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != identity['sourceSHA256']:
            raise SystemExit('Official model source integrity failure.')
        source.write_bytes(data)
    subprocess.run([sys.executable, str(evidence / 'materialize_official_model.py'), str(source), str(face)], check=True)
if sha(face) != identity['serializedModelSHA256']:
    raise SystemExit('Face model integrity failure; existing file was preserved.')
print('PASS: both model identities verified; assets remain in ignored .deps/models')
