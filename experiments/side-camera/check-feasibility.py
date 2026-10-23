"""Check the frozen public-image Vision feasibility evidence, not blink accuracy."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parents[2]
folder = root / 'evidence/native-tests'
names = ['side-camera-vision-implicit-pose.json', 'side-camera-vision-feasibility.json', 'side-camera-vision-black-control.json']
implicit, explicit, black = [json.loads((folder / name).read_text()) for name in names]
for report in [implicit, explicit, black]:
    assert not report['cameraAccessed'] and not report['userDataAccessed']
    assert report['requestRevision'] == 3 and report['constellation'] == 76
    assert (report['width'], report['height']) == (640, 480)
assert implicit['inputSHA256'] == explicit['inputSHA256'] == '75518f3e95798508647459687a79b6544525dd112bba62d75aaf971dc6034116'
assert not implicit['explicitPoseRequest'] and implicit['faceRectangleRevision'] is None
assert implicit['warmIterations'] == explicit['warmIterations'] == 20
assert implicit['faces'] and all(face['pitchDegrees'] is None for face in implicit['faces'])
assert explicit['explicitPoseRequest'] and explicit['faceRectangleRevision'] == 3
assert len(explicit['faces']) == 4
for face in explicit['faces']:
    assert face['landmarkCount'] == 76
    assert all(face[key] is not None for key in ['yawDegrees', 'rollDegrees', 'pitchDegrees'])
    for key in ['leftEye', 'rightEye']:
        assert face[key]['points'] == face[key]['precisionEstimateCount'] == 6
assert black['explicitPoseRequest'] and black['faces'] == []
binary = root / '.deps/side-camera-vision-probe'
assert subprocess.check_output(['lipo', '-archs', str(binary)], text=True).strip() == 'arm64'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
result = {
    'date': '2026-10-21', 'status': 'PASS',
    'scope': 'Offline Vision request/metadata feasibility on one frozen public crop and black control; not side-camera or blink accuracy acceptance',
    'userTarget': 'Camera physically right of screen, about 15–30 degrees; user naturally looks at screen',
    'nativeArchitecture': 'arm64', 'deploymentTargetCompiled': 'macOS 14.0',
    'sourceSHA256': sha(root / 'experiments/side-camera/vision-feasibility.swift'),
    'probeBinarySHA256': sha(binary),
    'reportSHA256': {name: sha(folder / name) for name in names},
    'explicitRequestFaceCount': len(explicit['faces']),
    'landmarksPerFace': 76, 'contourPointsPerEye': 6,
    'implicitPitchMissing': True, 'explicitPoseFieldsPresent': True, 'blackControlFaces': 0,
    'coldMilliseconds': explicit['coldRequestMilliseconds'],
    'warmMedianMilliseconds': explicit['warmMedianMilliseconds'],
    'warmP95Milliseconds': explicit['warmP95Milliseconds'],
    'limitations': ['Input is not a labelled 15–30 degree eye-closure sequence',
                    'Pose values and point precision estimates are present, not validated for accuracy',
                    'Repeated static image requests exclude camera conversion, tracking, fusion, UI and long-run overhead',
                    'macOS 14 deployment compile does not establish runtime acceptance on macOS 14 hardware',
                    'No new detector integration, calibration, blink accuracy, camera FPS or energy claim',
                    'No production app launch, camera access or user history access by this experiment']
}
(folder / 'side-camera-feasibility-check.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
print('PASS: arm64/macOS14 target; explicit pose + 76 landmarks/6 points per eye on four public-image faces; black control empty. Side-pose blink accuracy remains untested.')
