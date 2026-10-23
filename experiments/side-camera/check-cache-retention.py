"""Bind visible-eye v2 contracts to tests and the signed bundle; not human accuracy."""
from pathlib import Path
import hashlib, json, re
root = Path(__file__).resolve().parents[2]
folder = root / 'evidence/native-tests'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
counts = {}
required = [
    'testUnverifiedPoseExplorationCannotEvictVerifiedCalibration',
    'testVerifiedPoseHysteresisDoesNotRecalibrateAtWindowEdge',
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
for name, expected in [('visible-eye-retention-full-swift.log', 183), ('visible-eye-retention-release.log', 92)]:
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
assert 'PASS:' in (folder / 'visible-eye-retention-package-verification.log').read_text()
report = {
    'date': '2026-10-22', 'status': 'PASS', 'algorithm': 'side-contour-v2',
    'scope': 'Synthetic visible-eye closure, Core reminder/completion/provenance, actual Vision public-image adapter, original regressions and signed arm64 packaging. Not natural-camera accuracy.',
    'swiftTests': counts['visible-eye-retention-full-swift.log'], 'releaseSelectedTests': counts['visible-eye-retention-release.log'],
    'sideCameraTests': 38, 'newVisibleEyeTests': 19,
    'executableSHA256': build['machO'][0]['sha256'],
    'contracts': ['Static absolute pose no longer blocks usable-eye calibration; relative motion/gap gates remain',
        'Left/right visible-eye fallback and explicitly preferred single-eye policy use mode-specific calibration',
        'Selection locks across width jitter and closure; no candidate crosses eye switches, gaps or leases',
        'Three calibration closures excluded; bilateral wink rejection retained; monocular closures are estimates',
        'Single/mixed provenance persists and is excluded from bilateral mean frequency and duration',
        'Evict least-progressed then least-recently-used calibration; verified baselines protected from exploration',
        'Relative-pose enter/exit hysteresis is bounded at 12/16 degrees; quality gate remains 85 percent',
        'Filter yaw and pitch before ranking, retain compatible ready calibration across small jitter',
        'Same camera arbitration/FIFO/deadline and 85 percent time coverage; original comparison retained'],
    'limitations': ['Vision can infer hidden contours; width is not calibrated visibility confidence',
        'Single-eye closures cannot distinguish a wink or confirm hidden-eye closure',
        'Threshold duration is not clinically measured eyelid closure time',
        'Synthetic high-pose metadata proves eligibility logic only, not Vision high-pose accuracy',
        'Human calibration, ten-closure comparison, interference cases and 180-second measurement remain separate live gates'],
    'sources': {p: h for p,h in build['sources'].items() if 'SideCamera' in p or p.endswith(('CameraFrameRun.swift','CameraPipeline.swift','Measurements.swift','CameraView.swift','StatisticsView.swift','AppModel.swift'))}
}
(folder / 'visible-eye-retention-integration-check.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
print('PASS: 183 Swift / 92 release, 38 side-camera tests (19 new); signed arm64 source match. Human visible-eye accuracy remains separate.')
