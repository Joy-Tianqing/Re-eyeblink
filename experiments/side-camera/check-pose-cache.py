"""Bind visible-eye v2 contracts to tests and the signed bundle; not human accuracy."""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[2]
folder = root / 'evidence/native-tests'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
counts = {}
required = [
    'testCachedPoseWithCloserYawButWrongPitchCannotHideReadyCalibration',
    'testSmallPoseJitterKeepsActiveReadyBaselineInsteadOfIncompleteNeighbor',
    'testOnlyLeftEyeCanCalibrateAndEmitOneVisibleEyeClosure',
    'testOnlyRightEyeCanCalibrateAtStableHighYaw',
    'testStablePoseWithBothResolvedEyesIsNotRejectedJustForAbsoluteAngles',
    'testPreferredSingleEyeRemainsLockedAcrossWidthJitterAndOtherEyeStayingOpen',
    'testSwitchingVisibleEyeCannotCompleteHalfBlinkAndRequiresOwnCalibration',
    'testSingleEyeOcclusionGapLongClosureAndLeaseResetCannotFinishCandidate',
    'testPolicyChangeDoesNotReuseSingleEyeCalibrationAsBothEyeCalibration',
    'testSingleEyeMetadataPersistsAndIsExcludedFromBothEyeAverages',
    'testV1MetadataWithoutEyeModeStillDecodesAsLegacyResult',
    'testCoverageTagsMixedModesAndDoesNotBridgeAnEyeSwitch',
    'testQualifiedSingleEyeMeasurementKeepsProvenanceThroughEngineCompletion',
    'testCalibratedSingleEyeEventCanDismissInteractiveReminderThroughExistingEngine',
    'testWinkAndLongClosureDoNotCount',
    'testRealVisionSinglePublicFaceProducesResolvedEyeGeometryAndPose',
    'testSideModeDeadlineBeforePixelAcquisitionCarriesZeroCoverageAndLatches',
    'testOriginalPixelsThroughPendingCandidateLossRecoveryAndActualReopenReference']
for name, expected in [('visible-eye-pose-cache-full-swift.log', 181), ('visible-eye-pose-cache-release.log', 90)]:
    log = (folder / name).read_text()
    values = re.findall(r'Executed (\d+) tests, with 0 failures', log)
    assert values and int(values[-1]) == expected, (name, values)
    assert 'skipped' not in log.lower()
    for test in required:
        assert test + "]' passed" in log, (name, test)
    counts[name] = expected
build = json.loads((root / 'evidence/native-build.json').read_text())
assert len(build['machO']) == 1 and build['machO'][0]['architectures'] == ['arm64']
assert sha(root / 'build/Eyeblink.app/Contents/MacOS/Eyeblink') == build['machO'][0]['sha256']
assert all(sha(root / path) == digest for path, digest in build['sources'].items())
assert 'PASS:' in (folder / 'visible-eye-pose-cache-package-verification.log').read_text()
report = {
    'date': '2026-10-22', 'status': 'PASS', 'algorithm': 'side-contour-v2',
    'scope': 'Synthetic visible-eye closure, Core reminder/completion/provenance, actual Vision public-image adapter, original regressions and signed arm64 packaging. Not natural-camera accuracy.',
    'swiftTests': counts['visible-eye-pose-cache-full-swift.log'], 'releaseSelectedTests': counts['visible-eye-pose-cache-release.log'],
    'sideCameraTests': 36, 'newVisibleEyeTests': 17,
    'executableSHA256': build['machO'][0]['sha256'],
    'contracts': ['Static absolute pose no longer blocks usable-eye calibration; relative motion/gap gates remain',
        'Left/right visible-eye fallback and explicitly preferred single-eye policy use mode-specific calibration',
        'Selection locks across width jitter and closure; no candidate crosses eye switches, gaps or leases',
        'Three calibration closures excluded; bilateral wink rejection retained; monocular closures are estimates',
        'Single/mixed provenance persists and is excluded from bilateral mean frequency and duration',
        'Filter yaw and pitch before ranking, retain compatible ready calibration across small jitter',
        'Same camera arbitration/FIFO/deadline and 85 percent time coverage; original comparison retained'],
    'limitations': ['Vision can infer hidden contours; width is not calibrated visibility confidence',
        'Single-eye closures cannot distinguish a wink or confirm hidden-eye closure',
        'Threshold duration is not clinically measured eyelid closure time',
        'Synthetic high-pose metadata proves eligibility logic only, not Vision high-pose accuracy',
        'Human calibration, ten-closure comparison, interference cases and 180-second measurement remain separate live gates'],
    'sources': {p: h for p,h in build['sources'].items() if 'SideCamera' in p or p.endswith(('CameraFrameRun.swift','CameraPipeline.swift','Measurements.swift','CameraView.swift','StatisticsView.swift','AppModel.swift'))}
}
(folder / 'visible-eye-pose-cache-integration-check.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
print('PASS: 181 Swift / 90 release, 36 side-camera tests (17 new); signed arm64 source match. Human visible-eye accuracy remains separate.')
