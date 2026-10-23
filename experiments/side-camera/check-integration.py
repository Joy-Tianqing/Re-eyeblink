"""Bind implemented side-camera contracts to tests and the signed bundle.

This verifies evidence integrity, not natural blink or 15–30 degree accuracy.
"""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[2]
folder = root / 'evidence/native-tests'
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
counts = {}
for name, expected in [('side-camera-full-swift.log', 164), ('side-camera-release.log', 73)]:
    log = (folder / name).read_text()
    values = re.findall(r'Executed (\d+) tests, with 0 failures', log)
    assert values and int(values[-1]) == expected
    assert 'skipped' not in log.lower()
    for test in ['testBothCameraSidesAtTargetAnglesCountTenClosuresOnceEach',
                 'testPoseJumpGapOcclusionAndLeaseResetCannotCompleteHalfBlink',
                 'testOutsideSupportedAngleHasExplicitReasonAndNeverCounts',
                 'testLowQualityCompletionCancelsInsteadOfSavingFalseZeroAndLateCompletionCannotReviveIt',
                 'testOldHistoryWithoutAlgorithmMetadataDecodesUnchanged',
                 'testRealVisionSinglePublicFaceProducesResolvedEyeGeometryAndPose',
                 'testSideModeDeadlineBeforePixelAcquisitionCarriesZeroCoverageAndLatches',
                 'testOriginalPixelsThroughPendingCandidateLossRecoveryAndActualReopenReference']:
        assert test + "]' passed" in log, (name, test)
    counts[name] = expected
build = json.loads((root / 'evidence/native-build.json').read_text())
assert len(build['machO']) == 1 and build['machO'][0]['architectures'] == ['arm64']
assert sha(root / 'build/Eyeblink.app/Contents/MacOS/Eyeblink') == build['machO'][0]['sha256']
assert all(sha(root / path) == digest for path, digest in build['sources'].items())
assert 'PASS:' in (folder / 'side-camera-package-verification.log').read_text()
report = {
    'date': '2026-10-21', 'status': 'PASS',
    'scope': 'Implemented ordered camera integration, synthetic contour/Core state machine and public-image Vision adapters; not human side-pose accuracy acceptance',
    'swiftTests': counts['side-camera-full-swift.log'], 'releaseSelectedTests': counts['side-camera-release.log'],
    'newSideCameraTests': 19, 'executableSHA256': build['machO'][0]['sha256'],
    'implementation': ['Same capture/session queues, generation guard, FIFO and pre-acquisition completion boundary',
                       'Explicit Vision rectangles revision3 then 76-point landmarks; image-local eye aperture',
                       'Independent open-eye baselines, three calibration closures excluded from statistics',
                       'Numeric calibration survives leases; candidate state never does; device/manual/resolution reset invalidates calibration',
                       'Both-eye closure evidence, hysteresis, finite duration, pose/movement/gap/visibility gates',
                       'Side-mode completion requires 85 percent time coverage; invalid completion cancels; old history remains decodable',
                       'Original analysis still available with the side-camera toggle off'],
    'sourceSHA256': {p: h for p, h in build['sources'].items() if 'SideCamera' in p or p.endswith(('CameraFrameRun.swift', 'CameraPipeline.swift', 'AppModel.swift', 'Measurements.swift', 'CameraView.swift'))},
    'limitations': ['Contour tests at signed 15/30 degree metadata are synthetic, not physical pose or Vision accuracy evidence',
                    'Public input checks cover actual Vision single-face/multi-face/black-frame metadata, not natural eye closure',
                    'Initial thresholds and 85 percent coverage are provisional pending labelled evaluation',
                    'Current initial calibration learns open-eye baselines and verifies three closures; it does not fit a separate closed-eye distribution',
                    'Plane translation/rotation/scale are removed by local contour geometry; nonrigid head motion is gated, not reconstructed in 3D',
                    'No single-eye-only counting, camera frame recording or upload',
                    'Human calibration, ten-blink comparison, interference cases and 180-second measurement remain separate live gates']
}
(folder / 'side-camera-integration-check.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
print('PASS: 164 Swift/73 release, 19 new side-camera tests; signed arm64 bundle/source match. Human side-camera blink acceptance remains separate.')
